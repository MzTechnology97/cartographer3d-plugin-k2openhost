try:
    from cartographer.__version__ import version as __version__
except ImportError:
    __version__ = "unknown"

# K2-OpenHost runs Kalico using the namespaced ``klippy.*`` package layout,
# while the K2 Cartographer port still contains a number of traditional
# Klipper imports (``mcu``, ``extras.homing`` and similar).  Install aliases
# only for Kalico; regular Klipper behaviour remains unchanged.
try:
    from klippy import APP_NAME
except ImportError:
    APP_NAME = None

if APP_NAME == "Kalico":
    from cartographer.k2openhost_compat import install as _install_k2openhost_compat

    _install_k2openhost_compat()

__all__ = ["__version__"]
