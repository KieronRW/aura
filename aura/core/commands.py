import asyncio
import logging
import subprocess
import threading
import time
from datetime import datetime, timezone

from aura.core.cloud import _get_client, _SUPABASE_URL, _SUPABASE_KEY

log = logging.getLogger(__name__)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _mark(command_id, status: str, result: dict | None = None) -> None:
    """Update a command row's status. Logs on error; never raises."""
    client = _get_client()
    if client is None:
        return
    payload: dict = {"status": status, "executed_at": _now_iso()}
    if result is not None:
        payload["result"] = result
    try:
        client.table("commands").update(payload).eq("id", command_id).execute()
        log.info("commands: command %s → %s", command_id, status)
    except Exception as exc:
        log.warning("commands: failed to mark %s as %r: %s", command_id, status, exc)


def _dispatch(record: dict) -> None:
    """Execute a single command. Runs in a background thread."""
    command_id = record.get("id")
    command_type = record.get("command_type")

    if record.get("status") != "pending":
        log.debug("commands: skipping %s — status=%r", command_id, record.get("status"))
        return

    log.info("commands: dispatching command_type=%r id=%s", command_type, command_id)

    # Mark executing first so the app knows we picked it up
    client = _get_client()
    if client is None:
        log.warning("commands: no Supabase client — cannot process command %s", command_id)
        return
    try:
        client.table("commands").update({"status": "executing"}).eq("id", command_id).execute()
    except Exception as exc:
        log.warning("commands: failed to mark %s as executing: %s", command_id, exc)
        return

    if command_type == "reboot":
        # Mark executed BEFORE rebooting — the Pi won't be able to write after restart
        _mark(command_id, "executed")
        log.info("commands: reboot scheduled in 2 s")

        def _reboot() -> None:
            time.sleep(2)
            log.info("commands: rebooting now")
            subprocess.run(["sudo", "reboot"], check=False)

        threading.Thread(target=_reboot, daemon=True, name="cmd-reboot").start()

    elif command_type == "sync_settings":
        try:
            from aura.core.cloud import sync_settings
            settings = sync_settings()
            log.info("commands: sync_settings fetched %d keys", len(settings))
            _mark(command_id, "executed", {"synced_keys": list(settings.keys())})
        except Exception as exc:
            log.warning("commands: sync_settings error: %s", exc)
            _mark(command_id, "failed", {"error": str(exc)})

    elif command_type == "clear_cache":
        log.info("commands: clear_cache not yet implemented")
        _mark(command_id, "failed", {"error": "not implemented"})

    elif command_type == "run_diagnostics":
        log.info("commands: run_diagnostics not yet implemented")
        _mark(command_id, "failed", {"error": "not implemented"})

    elif command_type == "update_software":
        log.info("commands: update_software not yet implemented")
        _mark(command_id, "failed", {"error": "not implemented"})

    else:
        log.warning("commands: unknown command_type=%r — marking failed", command_type)
        _mark(command_id, "failed", {"error": f"unknown command_type: {command_type}"})


def start_command_listener(installation_id: str) -> None:
    """Subscribe to Realtime INSERT events on the commands table for this installation.

    Runs an asyncio event loop in a daemon thread — same pattern as subscribe_visitor_updates.
    Falls back silently if Supabase is unavailable.
    """
    if not _SUPABASE_URL or not _SUPABASE_KEY:
        log.warning("start_command_listener: Supabase not configured — skipping")
        return

    async def _realtime_main() -> None:
        from supabase import acreate_client
        rt_client = await acreate_client(_SUPABASE_URL, _SUPABASE_KEY)

        def _callback(payload, *_) -> None:
            record = (payload or {}).get("record") or {}
            log.info("commands: Realtime INSERT received — %s", record.get("command_type"))
            # Run in a thread so we never block the asyncio event loop
            threading.Thread(
                target=_dispatch,
                args=(record,),
                daemon=True,
                name="cmd-dispatch",
            ).start()

        channel = rt_client.channel(f"aura-commands-{installation_id}")
        channel.on_postgres_changes(
            event="INSERT",
            schema="public",
            table="commands",
            filter=f"installation_id=eq.{installation_id}",
            callback=_callback,
        )
        await channel.subscribe()
        log.info("commands: subscribed to commands INSERT (installation_id=%s)", installation_id)

        while True:
            await asyncio.sleep(1.0)

    def _run() -> None:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            loop.run_until_complete(_realtime_main())
        except Exception as exc:
            log.warning("commands: Realtime subscription failed: %s", exc)
        finally:
            loop.close()

    threading.Thread(target=_run, daemon=True, name="realtime-commands").start()
