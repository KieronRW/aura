import asyncio
import logging
import os
import threading
from pathlib import Path

import cv2
import numpy as np
from dotenv import load_dotenv

from aura.core.fingerprint import Fingerprint, extract_fingerprint, fingerprint_to_json

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
    Processes vehicle_reference_images rows that have no fingerprint_data yet.
    On startup runs an immediate backfill poll, then subscribes to Realtime for
    future INSERTs. Falls back to periodic polling if Realtime is unavailable.
    Once a vehicle has MIN_IMAGES_FOR_SEED fingerprinted images, aggregates them
    into vehicles.fingerprint_data and sets vehicles.fingerprint_seeded = true.
    """

    def __init__(self, on_vehicle_updated=None) -> None:
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()
        self._on_vehicle_updated = on_vehicle_updated

    def start(self) -> None:
        log.info(
            "Enroller: start() called — URL configured: %s, KEY configured: %s",
            bool(_SUPABASE_URL), bool(_SUPABASE_KEY),
        )
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
            from supabase import create_client
            sync_client = create_client(_SUPABASE_URL, _SUPABASE_KEY)
        except Exception:
            log.exception("Enroller: could not create Supabase client")
            return

        # Always backfill existing unprocessed rows immediately on startup
        log.info("Enroller: running startup backfill poll")
        self._poll_once(sync_client)

        if self._stop.is_set():
            return

        # Subscribe to Realtime for future INSERTs; fall back to polling if unavailable
        try:
            self._run_realtime(sync_client)
        except Exception:
            log.exception("Enroller: realtime loop failed — falling back to polling")
            self._run_polling(sync_client)

    # ------------------------------------------------------------------
    # Realtime path
    # ------------------------------------------------------------------

    def _run_realtime(self, sync_client) -> None:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            loop.run_until_complete(self._realtime_main(sync_client))
        finally:
            loop.close()

    async def _realtime_main(self, sync_client) -> None:
        from supabase import acreate_client

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
        )
        await channel.subscribe()
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

    def _run_polling(self, sync_client) -> None:
        log.info("Enroller: running in polling mode (30 s interval)")
        while not self._stop.is_set():
            self._poll_once(sync_client)
            self._stop.wait(30.0)

    def _poll_once(self, client) -> None:
        try:
            resp = (
                client.table("vehicle_reference_images")
                .select("id, storage_path, vehicle_id")
                .is_("fingerprint_data", "null")
                .execute()
            )
            rows = resp.data or []
            log.info("Enroller: poll found %d unprocessed row(s)", len(rows))
            for row in rows:
                self._process(row, client)
        except Exception:
            log.exception("Enroller: poll error")

    # ------------------------------------------------------------------
    # Record processing (sync — called from executor or polling)
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

        if self._on_vehicle_updated:
            try:
                self._on_vehicle_updated()
            except Exception:
                log.exception("Enroller: on_vehicle_updated callback failed")

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
            "Enroller: vehicle %s has %d fingerprinted images — ready to seed",
            vehicle_id, len(seeded_rows),
        )

        try:
            client.table("vehicles").update({
                "fingerprint_seeded": True,
            }).eq("id", vehicle_id).execute()
            log.info(
                "Enroller: marked vehicle %s as fingerprint_seeded (%d reference images)",
                vehicle_id, len(seeded_rows),
            )
        except Exception as exc:
            log.warning("Enroller: failed to seed vehicle %s: %s", vehicle_id, exc)
