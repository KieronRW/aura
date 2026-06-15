"""Weather fetching via Open-Meteo (no API key required).

Keeps a simple in-process cache keyed by (lat, lon) rounded to 2 d.p.
Callers should check for None and fall back to a previous cached value.
"""

import logging
import time
import urllib.error
import urllib.parse
import urllib.request
import json

log = logging.getLogger(__name__)

_WEATHER_CACHE_TTL = 1800  # 30 minutes

_cache: dict[tuple[float, float], dict] = {}

# WMO code → human-readable description (simplified)
_WMO_MAP: dict[int, str] = {
    0: "Clear",
    1: "Mostly clear",
    2: "Partly cloudy",
    3: "Cloudy",
    45: "Foggy",
    48: "Foggy",
    51: "Drizzle",
    53: "Drizzle",
    55: "Drizzle",
    61: "Rain",
    63: "Rain",
    65: "Heavy rain",
    66: "Freezing rain",
    67: "Freezing rain",
    71: "Snow",
    73: "Snow",
    75: "Heavy snow",
    77: "Snow grains",
    80: "Showers",
    81: "Showers",
    82: "Heavy showers",
    85: "Snow showers",
    86: "Heavy snow showers",
    95: "Thunderstorm",
    96: "Thunderstorm",
    99: "Thunderstorm",
}


def weather_code_to_description(code: int) -> str:
    """Map a WMO weather interpretation code to a short description."""
    return _WMO_MAP.get(code, "—")


def get_weather(lat: float, lon: float) -> dict | None:
    """Fetch current weather for (lat, lon) from Open-Meteo, with caching.

    Returns {"temp_c": float, "weather_code": int, "fetched_at": float} or None on error.
    Cached results are returned until _WEATHER_CACHE_TTL seconds have elapsed.
    """
    key = (round(lat, 2), round(lon, 2))
    now = time.monotonic()

    cached = _cache.get(key)
    if cached and (now - cached["fetched_at"]) < _WEATHER_CACHE_TTL:
        log.debug("Weather cache hit for %s", key)
        return cached

    params = urllib.parse.urlencode({
        "latitude": key[0],
        "longitude": key[1],
        "current": "temperature_2m,weather_code",
        "timezone": "auto",
    })
    url = f"https://api.open-meteo.com/v1/forecast?{params}"

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "aura/1.0"})
        with urllib.request.urlopen(req, timeout=8) as resp:
            body = json.loads(resp.read().decode())

        current = body.get("current") or {}
        temp_c = current.get("temperature_2m")
        weather_code = current.get("weather_code")

        if temp_c is None or weather_code is None:
            log.warning("Weather API: unexpected response structure — %s", body)
            return cached  # return stale cache if available

        result = {
            "temp_c": float(temp_c),
            "weather_code": int(weather_code),
            "fetched_at": now,
        }
        _cache[key] = result
        log.info("Weather fetched: lat=%.2f lon=%.2f temp=%.1f°C code=%d", key[0], key[1], temp_c, weather_code)
        return result

    except urllib.error.URLError as exc:
        log.warning("Weather fetch failed (network): %s", exc)
    except Exception as exc:
        log.warning("Weather fetch failed: %s", exc)

    return cached  # stale cache is better than nothing
