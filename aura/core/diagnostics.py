import logging
import threading
from datetime import datetime, timezone

log = logging.getLogger(__name__)


def _insert(severity: str, category: str, message: str, metadata: dict | None) -> None:
    from aura.core.cloud import _get_client, _get_installation_uuid
    client = _get_client()
    if client is None:
        return
    uuid = _get_installation_uuid()
    if uuid is None:
        return
    try:
        client.table("diagnostics_logs").insert({
            "installation_id": uuid,
            "severity": severity,
            "category": category,
            "message": message,
            "metadata": metadata,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }).execute()
    except Exception as exc:
        log.debug("diagnostics_logs insert failed: %s", exc)


def log_event(severity: str, category: str, message: str, metadata: dict | None = None) -> None:
    """Fire-and-forget diagnostics log. Never raises."""
    try:
        threading.Thread(
            target=_insert,
            args=(severity, category, message, metadata),
            daemon=True,
            name="diag-log",
        ).start()
    except Exception as exc:
        log.debug("log_event thread start failed: %s", exc)


def log_event_sync(severity: str, category: str, message: str, metadata: dict | None = None) -> None:
    """Synchronous variant — blocks until the insert completes. Use for shutdown."""
    try:
        _insert(severity, category, message, metadata)
    except Exception as exc:
        log.debug("log_event_sync failed: %s", exc)


def log_info(category: str, message: str, metadata: dict | None = None) -> None:
    log_event("info", category, message, metadata)


def log_warning(category: str, message: str, metadata: dict | None = None) -> None:
    log_event("warning", category, message, metadata)


def log_error(category: str, message: str, metadata: dict | None = None) -> None:
    log_event("error", category, message, metadata)


def log_critical(category: str, message: str, metadata: dict | None = None) -> None:
    log_event("critical", category, message, metadata)
