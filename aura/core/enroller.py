import asyncio
import logging
import os
import threading
from pathlib import Path

import cv2
import numpy as np
from dotenv import load_dotenv

from aura.core.fingerprint import (
    extract_fingerprint,
    fingerprint_to_json,
    json_to_fingerprint,
    Fingerprint,
)

load_dotenv(Path(__file__).parent.parent / "config" / ".env")

log = logging.getLogger(__name__)

_SUPABASE_URL = os.getenv("SUPABASE_URL", "")
_SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")
_BUCKET = "reference-images"
_MIN_IMAGES_FOR_SEED = 3


def _fingerprint_from_bytes(image_bytes: bytes) -> Fingerprint | None:
    """Decode image bytes and extract a full fingerprint (ORB descriptors + histogram)."""
    arr = np.frombuffer(image_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        return None
    return extract_fingerprint(img)


class ReferenceImageEnroller:
    """
    Subscribes to vehicle_reference_images INSERTs and computes ORB fingerprints
    for each new reference image. Once a vehicle has MIN_IMAGES_FOR_SEED images
    all fingerprinted, aggregates them into vehicles.fingerprint_data and sets
    vehicles.fingerprint_seeded = true.
    """

    def __init__(self) -> None:
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()

    def start(self) -> None:
        if not _SUPABASE_URL or not _SUPABASE_KEY:
            log.info("Enroller: Supabase not configured — skipping")
            return
        self._thread = threading.Thread(target=self._run, daemon=True, name="enroller")
        self._thread.start()
        log.info("Enroller: started")

    def stop(self) -> None:
        self._stop.set()

    # ------------------------------------------------------------------
    # Thread body
    # ------------------------------------------------------------------

    def _run(self) -> None:
        try:
            self._run_realtime()
        except Exception:
            log.exception("Enroller: realtime loop failed — falling back to polling")
            self._run_polling()

    def _run_realtime(self) -> None:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            loop.run_until_complete(self._realtime_main())
        finally:
            loop.close()

    async def _realtime_main(self) -> None:
        from supabase import acreate_client, create_client

        sync_client = create_client(_SUPABASE_URL, _SUPABASE_KEY)
        rt_client = await acreate_client(_SUPABASE_URL, _SUPABASE_KEY)

        queue: asyncio.Queue = asyncio.Queue()
        loop = asyncio.get_running_loop()

        def _on_insert(payload, *_) -> None:
            record = (payload or {}).get("new", {})
            if record and record.get("fingerprint_data") is None:
                loop.call_soon_threadsafe(queue.put_nowait, record)

        channel = rt_client.channel("enroller:vehicle_reference_images")
        channel.on_postgres_changes(
            event="INSERT",
            schema="public",
            table="vehicle_reference_images",
            callback=_on_insert,
        ).subscribe()
        log.info("Enroller: subscribed to vehicle_reference_images INSERT events")

        while not self._stop.is_set():
            try:
                record = await asyncio.wait_for(queue.get(), timeout=1.0)
            except asyncio.TimeoutError:
                continue
            await loop.run_in_executor(None, self._process, record, sync_client)

        try:
            await rt_client.realtime.remove_channel(channel)
        except Exception:
            pass

    # ------------------------------------------------------------------
    # Polling fallback
    # ------------------------------------------------------------------

    def _run_polling(self) -> None:
        try:
            from supabase import create_client
            client = create_client(_SUPABASE_URL, _SUPABASE_KEY)
        except Exception as exc:
            log.warning("Enroller: could not create Supabase client: %s", exc)
            return

        log.info("Enroller: running in polling mode (30 s interval)")
        while not self._stop.is_set():
            try:
                resp = (
                    client.table("vehicle_reference_images")
                    .select("id, storage_path, vehicle_id")
                    .is_("fingerprint_data", "null")
                    .execute()
                )
                for row in (resp.data or []):
                    self._process(row, client)
            except Exception:
                log.exception("Enroller: polling error")
            self._stop.wait(30.0)

    # ------------------------------------------------------------------
    # Record processing (sync — safe to call from executor or polling)
    # ------------------------------------------------------------------

    def _process(self, record: dict, client) -> None:
        row_id = record.get("id")
        storage_path = record.get("storage_path")
        vehicle_id = record.get("vehicle_id")

        if not (row_id and storage_path and vehicle_id):
            log.warning(
                "Enroller: incomplete record — id=%s path=%s vehicle_id=%s",
                row_id, storage_path, vehicle_id,
            )
            return

        log.info("Enroller: processing ref image id=%s vehicle_id=%s", row_id, vehicle_id)

        try:
            image_bytes = bytes(client.storage.from_(_BUCKET).download(storage_path))
        except Exception as exc:
            log.warning("Enroller: download failed for %s: %s", storage_path, exc)
            return

        fp = _fingerprint_from_bytes(image_bytes)
        if fp is None:
            log.warning("Enroller: could not decode image %s — skipping", storage_path)
            return

        descriptor_count = len(fp.descriptors) if fp.descriptors is not None else 0
        fp_json = fingerprint_to_json(fp)

        try:
            client.table("vehicle_reference_images").update(
                {"fingerprint_data": fp_json}
            ).eq("id", row_id).execute()
            log.info(
                "Enroller: wrote fingerprint_data for ref image id=%s (%d descriptors)",
                row_id, descriptor_count,
            )
        except Exception as exc:
            log.warning("Enroller: update failed for id=%s: %s", row_id, exc)
            return

        self._maybe_seed_vehicle(vehicle_id, client)

    def _maybe_seed_vehicle(self, vehicle_id, client) -> None:
        try:
            resp = (
                client.table("vehicle_reference_images")
                .select("fingerprint_data")
                .eq("vehicle_id", vehicle_id)
                .execute()
            )
        except Exception as exc:
            log.warning("Enroller: query failed for vehicle %s: %s", vehicle_id, exc)
            return

        rows = resp.data or []
        seeded_rows = [r for r in rows if r.get("fingerprint_data") is not None]

        if len(seeded_rows) < _MIN_IMAGES_FOR_SEED:
            log.debug(
                "Enroller: vehicle %s has %d/%d fingerprinted images — not ready",
                vehicle_id, len(seeded_rows), _MIN_IMAGES_FOR_SEED,
            )
            return

        log.info(
            "Enroller: vehicle %s has %d fingerprinted images — aggregating",
            vehicle_id, len(seeded_rows),
        )

        all_descriptors: list[np.ndarray] = []
        all_histograms: list[np.ndarray] = []

        for row in seeded_rows:
            try:
                fp = json_to_fingerprint(row["fingerprint_data"])
                all_histograms.append(fp.histogram)
                if fp.descriptors is not None:
                    all_descriptors.append(fp.descriptors)
            except Exception as exc:
                log.warning("Enroller: could not parse fingerprint row: %s", exc)

        if not all_descriptors:
            log.warning("Enroller: no valid descriptors for vehicle %s — skipping seed", vehicle_id)
            return

        combined = Fingerprint(
            histogram=np.mean(all_histograms, axis=0).astype(np.float32),
            descriptors=np.vstack(all_descriptors),
        )
        combined_json = fingerprint_to_json(combined)

        try:
            client.table("vehicles").update({
                "fingerprint_data": combined_json,
                "fingerprint_seeded": True,
            }).eq("id", vehicle_id).execute()
            log.info(
                "Enroller: seeded vehicle %s — %d combined descriptors from %d images",
                vehicle_id, len(combined.descriptors), len(seeded_rows),
            )
        except Exception as exc:
            log.warning("Enroller: failed to seed vehicle %s: %s", vehicle_id, exc)
