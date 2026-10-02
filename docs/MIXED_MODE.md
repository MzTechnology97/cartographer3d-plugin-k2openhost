# Mixed mode: PRTouch + Cartographer

## Goal

Mixed mode keeps the K2 stock PRTouch/load-cell path as the primary physical Z reference while using Cartographer for fast, high-density bed scanning.

Conceptually:

```text
PRTouch / load cell
    -> canonical Klipper/Kalico `probe`
    -> probe:z_virtual_endstop
    -> Z homing / nozzle-to-bed reference / Z offset

Cartographer
    -> independent Cartographer MCU
    -> scanning / bed mesh / Cartographer-specific commands
    -> cartographer_probe:z_virtual_endstop (separate namespace)
```

This mirrors the purpose of the newer upstream Cartographer `register_as_probe` option while preserving Jacob's K2-specific adapter, touch and reconnect changes.

## Current K2-OpenHost baseline

As of **2026-10-02**, the K2 Pro known-good baseline includes a full homing cycle with **PRTouch only** and Cartographer disabled. X/Y stall homing and the complete Z homing path are therefore known-good independently of Cartographer.

The same external-host Kalico stack also completed a real Klippain-ShakeTune resonance test. This is important because mixed-mode work now starts from a machine-control baseline that has already demonstrated motion, homing and accelerometer operation.

Mixed mode itself remains optional and is **not yet validated as a complete automatic Z/mesh workflow**. Direct-USB Cartographer must be validated first.

## Plugin behaviour

### `register_as_probe: true`

Cartographer behaves as the primary probe and claims the normal probe interface.

```ini
[cartographer]
register_as_probe: true
```

Cartographer owns:

```text
probe object
probe:z_virtual_endstop
PROBE
PROBE_ACCURACY
QUERY_PROBE
Z_OFFSET_APPLY_PROBE
```

### `register_as_probe: false`

```ini
[cartographer]
register_as_probe: false
```

K2-OpenHost then:

1. loads Cartographer normally;
2. does not register the Cartographer `probe` object;
3. does not replace `PROBE`, `PROBE_ACCURACY`, `QUERY_PROBE` or `Z_OFFSET_APPLY_PROBE`;
4. registers the Cartographer virtual endstop as `cartographer_probe:z_virtual_endstop` rather than `probe:z_virtual_endstop`;
5. keeps Cartographer-specific commands and its bed-mesh integration available.

The primary PRTouch implementation can therefore retain the canonical `probe` namespace.

## Example Cartographer section

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
register_as_probe: false
```

The serial ID and physical offsets must be taken from the actual printer.

## PRTouch side

Keep the K2 PRTouch configuration that provides the primary `probe` object. The exact PRTouch sections depend on the K2/Kalico port in use and are intentionally not duplicated in this repository.

The important ownership rule is:

```text
PRTouch      -> probe:z_virtual_endstop
Cartographer -> cartographer_probe:z_virtual_endstop
```

If PRTouch is responsible for Z homing, `[stepper_z]` must continue to use the PRTouch/primary-probe virtual endstop rather than the Cartographer endstop.

Do not copy a `[stepper_z] endstop_pin: cartographer_probe:z_virtual_endstop` line into a mixed-mode setup unless the intention is explicitly to home Z using Cartographer instead of PRTouch.

## Bed mesh

Mixed mode is intended to keep Cartographer's `BED_MESH_CALIBRATE` implementation available. This allows the stock probe to provide the Z reference while Cartographer performs the scanning work.

A typical workflow is therefore:

```text
1. Home X/Y.
2. Establish Z using PRTouch/load cell.
3. Move to the safe scanning height.
4. Run the Cartographer bed-mesh workflow.
5. Apply the mesh while retaining the PRTouch-derived nozzle/bed reference.
```

The exact print-start macro should only be changed after both probe paths have been validated separately.

## Cartographer Touch in mixed mode

Cartographer Touch commands remain available because they are Cartographer-specific commands. That does not mean they should automatically replace the PRTouch Z-reference workflow.

During initial mixed-mode validation, use PRTouch for the physical Z reference and treat Cartographer Touch as a separately testable feature.

## Validation order

Do not begin with mixed-mode `G28 Z`.

Recommended validation sequence:

1. Keep the already-validated PRTouch-only configuration as the rollback baseline.
2. Connect Cartographer directly to the external host by USB.
3. Confirm the Cartographer MCU identifies and streams without reconnect loops.
4. Validate Cartographer standalone with `register_as_probe: true` if Cartographer-controlled probing is required.
5. For mixed mode, restore the known-working PRTouch configuration and set `register_as_probe: false`.
6. Confirm Klipper starts without a duplicate `probe` object or duplicate probe commands.
7. Run `QUERY_PROBE` and verify it reports the PRTouch/primary-probe state.
8. Run `CARTOGRAPHER_QUERY` and verify Cartographer remains independently available.
9. Verify Cartographer scan data changes with target distance without commanding Z motion.
10. Repeat controlled Z homing with the primary PRTouch path and compare it with the known-good PRTouch-only baseline.
11. Validate Cartographer mesh generation only after Z homing remains proven safe.

## Expected command ownership

With `register_as_probe: false`:

```text
QUERY_PROBE                  -> primary probe / PRTouch
PROBE                        -> primary probe / PRTouch
PROBE_ACCURACY               -> primary probe / PRTouch
Z_OFFSET_APPLY_PROBE         -> primary probe / PRTouch

CARTOGRAPHER_QUERY           -> Cartographer
CARTOGRAPHER_STREAM          -> Cartographer
CARTOGRAPHER_SCAN_CALIBRATE  -> Cartographer
CARTOGRAPHER_SCAN_ACCURACY   -> Cartographer
CARTOGRAPHER_TOUCH_*         -> Cartographer
BED_MESH_CALIBRATE           -> Cartographer integration
```

## Troubleshooting

### Duplicate `probe` object or command

Check that Cartographer actually has:

```ini
register_as_probe: false
```

and that the K2-OpenHost fork is the package loaded by the Klippy virtual environment.

### `Option 'register_as_probe' is not valid`

The host is loading an older plugin version or an old checkout. Update the K2-OpenHost repository and restart Klipper.

### Cartographer loads but PRTouch commands disappear

Confirm the log contains the K2-OpenHost load line with:

```text
register_as_probe=False
```

If it reports `True`, inspect the active `[cartographer]` section and included configuration files.

### Z endstop conflict

In mixed mode Cartographer should register:

```text
cartographer_probe:z_virtual_endstop
```

while PRTouch retains:

```text
probe:z_virtual_endstop
```

A configuration referencing the wrong virtual endstop can move Z using the wrong sensing path. Resolve this before any homing attempt.

## Status

The mixed-mode registration logic is implemented in the K2-OpenHost fork. The PRTouch-only full-homing baseline is hardware-validated. Full K2 Pro validation of the combined PRTouch + direct-USB Cartographer Z/mesh workflow is still required before mixed mode should be considered production-ready.