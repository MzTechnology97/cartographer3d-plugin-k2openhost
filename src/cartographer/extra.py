from __future__ import annotations

import logging

from cartographer import __version__
from cartographer.core import PrinterCartographer
from cartographer.runtime.loader import init_adapter, init_integrator

logger = logging.getLogger(__name__)


def _consume_register_as_probe(config: object) -> None:
    """Accept the modern Cartographer ``register_as_probe`` option.

    Jacob's K2 port predates this upstream option and always registers
    Cartographer as the Klipper/Kalico ``probe`` object.  K2-OpenHost keeps
    that behaviour for now, but explicitly consumes the option so current
    Cartographer configs remain valid.
    """
    getboolean = getattr(config, "getboolean", None)
    if getboolean is None:
        return

    register_as_probe = getboolean("register_as_probe", True)
    if not register_as_probe:
        raise RuntimeError(
            "K2-OpenHost currently requires 'register_as_probe: true'; "
            "support for register_as_probe: false has not been ported from upstream yet."
        )


def load_config(config: object) -> object:
    _consume_register_as_probe(config)

    adapters = init_adapter(config)
    integrator = init_integrator(adapters)

    integrator.setup()

    cartographer = PrinterCartographer(adapters)

    integrator.register_cartographer(cartographer)

    for macro in cartographer.macros:
        integrator.register_macro(macro)

    integrator.register_coil_temperature_sensor()
    integrator.register_endstop_pin("probe", "z_virtual_endstop", cartographer.scan_mode)

    integrator.register_ready_callback(cartographer.ready_callback)

    integrator_name = integrator.__class__.__name__
    logger.info("Loaded Cartographer3D Plugin version %s using %s", __version__, integrator_name)

    return cartographer
