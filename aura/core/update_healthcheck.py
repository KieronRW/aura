import json
import logging
import subprocess
import threading
import time
import urllib.request
from pathlib import Path

log = logging.getLogger(__name__)

_REPO = Path("/home/aura/aura")
_SENTINEL_FILE = _REPO / ".update_in_progress"
_HEALTH_URL = "http://localhost:8000/health"
_STARTUP_WAIT = 30  # seconds to wait for the API to be ready


def _do_healthcheck(prev_hash: str, command_id: str) -> None:
    log.info("update_healthcheck: waiting %ds before health check", _STARTUP_WAIT)
    time.sleep(_STARTUP_WAIT)

    health_ok = False
    try:
        with urllib.request.urlopen(_HEALTH_URL, timeout=10) as resp:
            health_ok = resp.status == 200
        log.info("update_healthcheck: /health returned %s", resp.status)
    except Exception as exc:
        log.warning("update_healthcheck: /health unreachable: %s", exc)

    from aura.core.commands import _mark

    if health_ok:
        try:
            new_hash = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=str(_REPO),
                capture_output=True,
                text=True,
            ).stdout.strip()
        except Exception:
            new_hash = "unknown"
        log.info("update_healthcheck: update confirmed — new_hash=%s", new_hash[:8])
        _mark(command_id, "executed", {
            "previous_hash": prev_hash,
            "new_hash": new_hash,
            "health": "ok",
        })
    else:
        log.warning("update_healthcheck: rolling back to %s", prev_hash[:8])
        try:
            subprocess.run(
                ["git", "reset", "--hard", prev_hash],
                cwd=str(_REPO),
                check=True,
                capture_output=True,
            )
            log.info("update_healthcheck: rollback complete")
        except Exception as exc:
            log.warning("update_healthcheck: git reset failed: %s", exc)
        _mark(command_id, "failed", {
            "error": "health check failed after update — rolled back",
            "previous_hash": prev_hash,
            "rolled_back_to": prev_hash,
        })
        log.info("update_healthcheck: restarting service after rollback")
        subprocess.run(["sudo", "systemctl", "restart", "aura"], check=False)

    try:
        _SENTINEL_FILE.unlink(missing_ok=True)
    except Exception as exc:
        log.warning("update_healthcheck: failed to remove sentinel: %s", exc)


def check_and_rollback_if_needed() -> None:
    """Check for a pending update and spawn a daemon thread to verify health.

    Returns immediately — the health check runs 30s later in the background.
    """
    if not _SENTINEL_FILE.exists():
        return

    try:
        data = json.loads(_SENTINEL_FILE.read_text())
        prev_hash = data["previous_hash"]
        command_id = data["command_id"]
    except Exception as exc:
        log.warning("update_healthcheck: unreadable sentinel — removing: %s", exc)
        _SENTINEL_FILE.unlink(missing_ok=True)
        return

    log.info(
        "update_healthcheck: pending update detected (command=%s prev=%s) — verifying in %ds",
        command_id, prev_hash[:8], _STARTUP_WAIT,
    )
    threading.Thread(
        target=_do_healthcheck,
        args=(prev_hash, command_id),
        daemon=True,
        name="update-healthcheck",
    ).start()
