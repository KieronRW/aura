#!/usr/bin/env python3
"""Apply the saved display rotation from Supabase at boot time."""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from aura.core.display_settings import get_settings, apply_rotation

settings = get_settings()
rotation = settings.get("display_rotation", 90)
ok = apply_rotation(rotation)
sys.exit(0 if ok else 1)
