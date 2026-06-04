import logging
import re
import socket

logger = logging.getLogger(__name__)


def _local_ip() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"


class DiscoveryService:
    _SERVICE_TYPE = "_aura._tcp.local."

    def __init__(self, installation_key: str, version: str, port: int = 8000) -> None:
        self._installation_key = installation_key
        self._version = version
        self._port = port
        self._zeroconf = None
        self._info = None

    def start(self) -> None:
        try:
            from zeroconf import ServiceInfo, Zeroconf

            ip = _local_ip()
            safe_key = re.sub(r"[^A-Za-z0-9-]+", "-", self._installation_key).strip("-")
            service_name = f"AURA-{safe_key}.{self._SERVICE_TYPE}"
            self._zeroconf = Zeroconf()
            self._info = ServiceInfo(
                self._SERVICE_TYPE,
                service_name,
                addresses=[socket.inet_aton(ip)],
                port=self._port,
                properties={
                    "installation_key": self._installation_key,
                    "version": self._version,
                    "ip": ip,
                },
            )
            self._zeroconf.register_service(self._info)
            logger.info(
                "mDNS discovery: broadcasting %s on %s:%d",
                service_name, ip, self._port,
            )
        except Exception as exc:
            logger.warning("mDNS discovery start failed: %s", exc)

    def stop(self) -> None:
        if self._zeroconf is None:
            return
        try:
            if self._info is not None:
                self._zeroconf.unregister_service(self._info)
            self._zeroconf.close()
            logger.info("mDNS discovery stopped")
        except Exception as exc:
            logger.warning("mDNS discovery stop failed: %s", exc)
        finally:
            self._zeroconf = None
            self._info = None
