from __future__ import annotations

import logging

from cartographer import __version__
from cartographer.core import PrinterCartographer
from cartographer.runtime.loader import init_adapter, init_integrator

logger = logging.getLogger(__name__)

# These are the standard Klipper/Kalico probe commands.  When Cartographer is
# used in mixed mode (register_as_probe: false) they must remain owned by the
# stock/PRTouch probe instead of being replaced by Cartographer.
_STANDARD_PROBE_MACROS = frozenset(
    {
        "PROBE",
        "PROBE_ACCURACY",
        "QUERY_PROBE",
        "Z_OFFSET_APPLY_PROBE",
    }
)


def _read_register_as_probe(config: object) -> bool:
    """Read and consume Cartographer's modern register_as_probe option.

    Jacob's K2 port predates this option, while current Cartographer supports
    running as a scanner without claiming Klipper's ``probe`` object.  Reading
    the option directly from the Klipper ConfigWrapper both marks it as used
    and lets K2-OpenHost provide the same mixed-mode behaviour without
    discarding Jacob's K2-specific adapter and reconnect work.
    """
    getboolean = getattr(config, "getboolean", None)
    if getboolean is None:
        return True
    return bool(getboolean("register_as_probe", True))


def load_config(config: object) -> object:
    register_as_probe = _read_register_as_probe(config)

    adapters = init_adapter(config)
    integrator = init_integrator(adapters)

    integrator.setup()

    cartographer = PrinterCartographer(adapters)

    # Normal mode: Cartographer owns the canonical Klipper/Kalico `probe`
    # object.  Mixed mode: leave that object untouched so PRTouch (or another
    # probe implementation) can continue to provide Z homing / Z offset.
    if register_as_probe:
        integrator.register_cartographer(cartographer)

    for macro in cartographer.macros:
        if not register_as_probe and macro.name in _STANDARD_PROBE_MACROS:
            continue
        integrator.register_macro(macro)

    integrator.register_coil_temperature_sensor()

    # Match the current upstream Cartographer convention.  In mixed mode the
    # Cartographer virtual endstop remains available, but under its own chip
    # name so it cannot collide with PRTouch's probe:z_virtual_endstop.
    chip_name = "probe" if register_as_probe else "cartographer_probe"
    integrator.register_endstop_pin(chip_name, "z_virtual_endstop", cartographer.scan_mode)

    integrator.register_ready_callback(cartographer.ready_callback)

    integrator_name = integrator.__class__.__name__
    logger.info(
        "Loaded Cartographer3D Plugin version %s using %s (register_as_probe=%s)",
        __version__,
        integrator_name,
        register_as_probe,
    )

    return cartographer
