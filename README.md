# Cartographer3D Plugin — K2-OpenHost

K2-OpenHost integration fork of Cartographer3D for Creality K2-series printers running the host stack on an external Kalico host.

## Lineage

This repository intentionally combines work from three places:

1. `Cartographer3D/cartographer3d-plugin` — upstream Cartographer plugin.
2. `Jacob10383/cartographer3d-plugin` — K2-specific port, reconnect handling, touch changes and K2 timing work.
3. `MzTechnology97/cartographer3d-plugin-k2openhost` — external-host/Kalico integration for K2-OpenHost.

The K2-specific work from Jacob is retained. K2-OpenHost adds compatibility with the namespaced `klippy.*` module layout used by `MzTechnology97/kalico-k2pro`, an editable-package installation workflow, current `register_as_probe` behavior and OpenHost-specific transport/update documentation.

## Current K2-OpenHost architecture

For K2-OpenHost the preferred Cartographer connection is **direct USB to the external host**.

```text
K2 main MCU     -> T113 ttyGS0 -> CM5 /dev/ttyUSB0
K2 nozzle MCU   -> T113 ttyGS1 -> CM5 /dev/ttyUSB1
K2 RS485 / CFS  -> T113 ttyGS2 -> CM5 /dev/ttyUSB2
Cartographer USB ----------------> CM5 USB host
```

Do not multiplex Cartographer onto the K2 service-port serial channels when a direct USB host port is available. Cartographer is a native Klipper MCU with continuous traffic and reset/re-enumeration behaviour; direct USB avoids an unnecessary PTY/MUX/DEMUX layer and leaves the three gadget serial channels dedicated to the K2 hardware buses.

The experimental T113 MUX/DEMUX path did prove real Cartographer MCU streaming, but it is no longer the target architecture. It also helped expose a duplicate GS2 bridge/process-contention condition; once GS2 returned to a single direct RS-485 bridge, closed-loop motor communication returned to normal.

After connecting Cartographer directly to the host, find its persistent device name with:

```bash
ls -l /dev/serial/by-id/
```

Prefer `/dev/serial/by-id/...` over `/dev/ttyACM0` because the ACM number may change after a reboot or USB re-enumeration.

## Installation

Clone the repository on the external Kalico host:

```bash
cd ~
git clone https://github.com/MzTechnology97/cartographer3d-plugin-k2openhost.git
cd cartographer3d-plugin-k2openhost

./scripts/install.sh \
  --klipper ~/klipper \
  --klippy-env ~/klippy-env
```

The installer installs this checkout into the Klippy virtual environment in **editable mode**.

On `MzTechnology97/kalico-k2pro:k2-pro-openhost`, the Cartographer loader is already tracked by the Kalico repository at:

```text
~/klipper/klippy/extras/cartographer.py
```

The installer now detects and reuses that tracked loader and removes an untracked duplicate from `klippy/plugins/` if one exists. This avoids the Kalico error:

```text
Module 'cartographer' found in both extras and plugins!
```

On other compatible hosts without a tracked loader, the installer creates a single normal loader containing:

```python
from cartographer.extra import *
```

Because the package is editable, a Git update changes the code imported by Kalico immediately. A normal repository update therefore does not need to reinstall the package. Runtime dependency changes are tracked in `requirements.txt` so Moonraker can update them when required.

## Cartographer configuration

For a direct USB connection use a persistent serial path:

```ini
[mcu cartographer]
serial: /dev/serial/by-id/usb-REPLACE_WITH_YOUR_CARTOGRAPHER_ID
restart_method: command
is_non_critical: True
reconnect_interval: 2.0

[cartographer]
mcu: cartographer
x_offset: 0
y_offset: -15
verbose: yes
register_as_probe: true
```

The offsets above are examples for the K2 mounting arrangement used during development. Verify the offsets on the actual machine before probing.

## Normal mode — Cartographer is the probe

```ini
register_as_probe: true
```

Cartographer owns:

- the Klipper/Kalico `probe` printer object;
- `probe:z_virtual_endstop`;
- `PROBE`;
- `PROBE_ACCURACY`;
- `QUERY_PROBE`;
- `Z_OFFSET_APPLY_PROBE`.

If Cartographer performs Z homing, the Z stepper normally references:

```ini
[stepper_z]
endstop_pin: probe:z_virtual_endstop
homing_retract_dist: 0
```

Do not enable a second probe implementation that also claims the `probe` object in this mode.

## Mixed mode — PRTouch for Z reference, Cartographer for scanning

K2-OpenHost carries the newer Cartographer `register_as_probe` behavior while retaining Jacob's K2-specific adapter/reconnect work.

Use:

```ini
[cartographer]
mcu: cartographer
x_offset: 0
y_offset: -15
verbose: yes
register_as_probe: false
```

With `register_as_probe: false`:

- Cartographer remains loaded and available for scanning, mesh generation, temperature compensation and Cartographer-specific commands;
- Cartographer does **not** replace the canonical `probe` printer object;
- the standard `PROBE`, `PROBE_ACCURACY`, `QUERY_PROBE` and `Z_OFFSET_APPLY_PROBE` commands remain available to PRTouch or another primary probe;
- Cartographer's virtual endstop is registered separately as `cartographer_probe:z_virtual_endstop`;
- PRTouch may retain `probe:z_virtual_endstop` for Z homing / nozzle-contact Z reference.

This is the intended basis for the K2 mixed configuration: **PRTouch/load-cell for the physical nozzle-to-bed Z reference and Cartographer for fast bed scanning**.

## Known-good probe baseline on K2-OpenHost

As of **2026-10-01**, a complete homing cycle has been verified on the real K2 Pro using **PRTouch only**, with Cartographer disabled. The same OpenHost stack also completed a **Klippain-ShakeTune resonance test** successfully.

This PRTouch-only state is the reference baseline before direct-USB Cartographer is reintroduced. Mixed mode is optional and remains hardware-unvalidated as a complete automatic-Z workflow.

Validate Cartographer standalone on direct USB first, then validate mixed mode only if it is actually desired.

See [`docs/MIXED_MODE.md`](docs/MIXED_MODE.md) for the integration details and validation order.

## Updating from Mainsail / Moonraker

### Cartographer K2-OpenHost repository

Use:

```ini
[update_manager cartographer]
type: git_repo
channel: dev
path: ~/cartographer3d-plugin-k2openhost
origin: https://github.com/MzTechnology97/cartographer3d-plugin-k2openhost.git
primary_branch: main
virtualenv: ~/klippy-env
requirements: requirements.txt
is_system_service: False
managed_services: klipper
info_tags:
  desc=Cartographer3D Plugin - K2-OpenHost
```

The same section is provided in [`moonraker-cartographer.conf`](moonraker-cartographer.conf).

Do **not** use the old pattern:

```ini
# env: ~/klippy-env/bin/python
# install_script: install.sh
```

Why:

- use `virtualenv` instead of the deprecated `env` option;
- this repository's installer is `scripts/install.sh`, not a root-level `install.sh`;
- Moonraker's `install_script` is not a generic post-update hook;
- the editable install means a Git pull already updates the imported Cartographer code;
- `requirements.txt` gives Moonraker a supported dependency-update path.

Moonraker only updates a Git repository when its working tree is valid/pristine. Local edits inside the Cartographer repository should therefore be committed or removed before updating from Mainsail.

### Kalico / K2-OpenHost Klipper repository

Make sure the local Kalico checkout tracks the K2-OpenHost branch:

```bash
cd ~/klipper
git remote set-url origin https://github.com/MzTechnology97/kalico-k2pro.git
git fetch origin
git checkout k2-pro-openhost
git branch --set-upstream-to=origin/k2-pro-openhost k2-pro-openhost
```

The Moonraker override can remain minimal:

```ini
[update_manager klipper]
channel: dev
```

Locally installed Klipper extras should not overwrite files tracked by `kalico-k2pro`. Keep third-party extras outside Git tracking so Mainsail does not mark the Kalico repository dirty.

See [`docs/UPDATE_MANAGER.md`](docs/UPDATE_MANAGER.md) for troubleshooting and validation commands.

## K2-specific status

Validated during K2-OpenHost development:

- editable package import on external Kalico;
- Kalico adapter selection;
- Cartographer V4 MCU communication through the experimental bridge;
- live Cartographer sensor data streaming;
- normal `register_as_probe: true` configuration loading;
- tracked-loader coexistence with the `kalico-k2pro` source tree;
- PRTouch-only complete homing baseline on the same K2-OpenHost machine;
- successful ShakeTune resonance test on the same external-host stack.

Still requiring final Cartographer hardware validation:

- direct-USB cold boot and automated-reset behavior on the external host;
- controlled Cartographer Z homing / touch / scan calibration;
- full Cartographer bed mesh on direct USB;
- optional `register_as_probe: false` mixed PRTouch + Cartographer workflow.

Do not perform unattended Cartographer-controlled Z homing until the direct-USB path has been verified on the machine.

## Documentation

- [`docs/DIRECT_USB.md`](docs/DIRECT_USB.md) — preferred K2-OpenHost Cartographer transport.
- [`docs/MIXED_MODE.md`](docs/MIXED_MODE.md) — PRTouch + Cartographer mixed mode.
- [`docs/UPDATE_MANAGER.md`](docs/UPDATE_MANAGER.md) — Moonraker/Mainsail updater setup.

General calibration procedures remain documented by the upstream Cartographer3D project. K2-OpenHost documentation only overrides upstream instructions where the external-host architecture or K2-specific integration differs.