from __future__ import annotations

"""Compatibility layer for K2-OpenHost's namespaced Kalico layout.

The K2 Cartographer fork historically imports Klipper modules through the
traditional top-level names (``mcu``, ``extras.homing`` and similar).  The
K2-OpenHost Kalico fork runs those modules as the ``klippy`` package
(``klippy.mcu``, ``klippy.extras.homing`` ...).

Install aliases only when running under Kalico so the original Klipper/K2
behaviour remains untouched.
"""

import importlib
import sys


_CORE_ALIASES = {
    "chelper": "klippy.chelper",
    "clocksync": "klippy.clocksync",
    "configfile": "klippy.configfile",
    "mcu": "klippy.mcu",
    "msgproto": "klippy.msgproto",
    "pins": "klippy.pins",
    "reactor": "klippy.reactor",
    "serialhdl": "klippy.serialhdl",
    "stepper": "klippy.stepper",
    "toolhead": "klippy.toolhead",
}

_EXTRA_ALIASES = (
    "axis_twist_compensation",
    "bed_mesh",
    "danger_options",
    "homing",
    "manual_probe",
    "probe",
    "temperature_mcu",
)


def _alias(alias: str, target: str) -> None:
    """Bind *alias* to the already canonical *target* module."""
    if alias in sys.modules:
        return
    sys.modules[alias] = importlib.import_module(target)


def install() -> bool:
    """Install legacy Klipper import aliases when running under Kalico.

    Returns ``True`` when the compatibility aliases were installed and
    ``False`` when this is not a Kalico runtime.
    """
    try:
        klippy = importlib.import_module("klippy")
    except ImportError:
        return False

    if getattr(klippy, "APP_NAME", None) != "Kalico":
        return False

    for alias, target in _CORE_ALIASES.items():
        _alias(alias, target)

    # Import canonical extras first, then expose the legacy package name.
    # This prevents loading a second copy of stateful extras such as
    # danger_options under an ``extras.*`` name.
    _alias("extras", "klippy.extras")
    for name in _EXTRA_ALIASES:
        _alias(f"extras.{name}", f"klippy.extras.{name}")

    return True
