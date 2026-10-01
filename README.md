# Cartographer3D Plugin — K2-OpenHost

K2-OpenHost integration fork of Cartographer3D for Creality K2 Pro running the host stack on external Kalico.

## Lineage

This repository is based on:

1. `Cartographer3D/cartographer3d-plugin`
2. `Jacob10383/cartographer3d-plugin` — K2-specific port and optimizations
3. `MzTechnology97/cartographer3d-plugin-k2openhost` — K2-OpenHost integration

The K2-specific work from Jacob is intentionally retained. K2-OpenHost adds compatibility with the namespaced `klippy.*` module layout used by `MzTechnology97/kalico-k2pro` and provides a local editable installation workflow.

## K2-OpenHost installation

Clone this repository on the external Kalico host and run:

```bash
cd ~
git clone https://github.com/MzTechnology97/cartographer3d-plugin-k2openhost.git
cd cartographer3d-plugin-k2openhost

./scripts/install.sh \
  --klipper /home/alfio/klipper \
  --klippy-env /home/alfio/klippy-env
```

The installer installs this checkout into the Klippy virtual environment with `pip install -e`, then creates the normal Cartographer loader:

```python
from cartographer.extra import *
```

in `klippy/extras/cartographer.py` (or `klippy/plugins/cartographer.py` when that directory is used by the host).

Because the package is installed in editable mode, subsequent `git pull` operations update the code used by Kalico without replacing it with the PyPI package.

## K2-OpenHost transport

In the current K2-OpenHost architecture Cartographer is exposed to Kalico through the host-side demultiplexer. A typical MCU section is:

```ini
[mcu cartographer]
serial: /dev/k2-cartographer
restart_method: command
is_non_critical: True
reconnect_interval: 2.0
```

Transport plumbing is maintained by the `K2-OpenHost` project and is intentionally separate from this plugin.

## Status

Import/package integration with `MzTechnology97/kalico-k2pro` is under active validation. Motion/probing commands should only be enabled after the Cartographer MCU connection and K2-specific trigger-dispatch compatibility have been validated on hardware.

## Upstream documentation

General Cartographer documentation remains available from the Cartographer3D project. This fork does not replace upstream calibration and probe documentation except where K2-OpenHost requires a different transport or host integration.
