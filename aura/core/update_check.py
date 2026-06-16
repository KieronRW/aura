import logging
import subprocess
from pathlib import Path

log = logging.getLogger(__name__)

_REPO = Path("/home/aura/aura")


def get_current_commit() -> str:
    result = subprocess.run(
        ["git", "rev-parse", "--short", "HEAD"],
        cwd=str(_REPO),
        capture_output=True,
        text=True,
        timeout=10,
        check=True,
    )
    return result.stdout.strip()


def get_remote_commit() -> str | None:
    try:
        subprocess.run(
            ["git", "fetch", "origin", "main", "--quiet"],
            cwd=str(_REPO),
            capture_output=True,
            timeout=30,
        )
        result = subprocess.run(
            ["git", "rev-parse", "--short", "origin/main"],
            cwd=str(_REPO),
            capture_output=True,
            text=True,
            timeout=10,
        )
        return result.stdout.strip() or None
    except Exception as exc:
        log.warning("update_check: get_remote_commit failed: %s", exc)
        return None


def is_update_available() -> bool:
    try:
        current = get_current_commit()
        remote = get_remote_commit()
        if remote is None:
            return False
        return current != remote
    except Exception as exc:
        log.warning("update_check: is_update_available failed: %s", exc)
        return False


def get_remote_version() -> str | None:
    try:
        result = subprocess.run(
            ["git", "show", "origin/main:VERSION"],
            cwd=str(_REPO),
            capture_output=True,
            text=True,
            timeout=10,
        )
        return result.stdout.strip() or None
    except Exception as exc:
        log.warning("update_check: get_remote_version failed: %s", exc)
        return None
