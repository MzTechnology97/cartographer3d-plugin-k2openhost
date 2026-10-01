# Direct USB transport for K2-OpenHost

Updated: **2026-10-01**.

## Recommended topology

K2-OpenHost uses the three working USB gadget serial functions on the stock T113 only for the K2 internal hardware buses:

```text
T113 ttyS2 -> ttyGS0 -> external host /dev/ttyUSB0  (main MCU)
T113 ttyS3 -> ttyGS1 -> external host /dev/ttyUSB1  (nozzle MCU)
T113 ttyS5 -> ttyGS2 -> external host /dev/ttyUSB2  (RS485 / CFS / closed-loop)
```

Cartographer should be connected directly to a USB host port on the external Kalico computer:

```text
Cartographer USB -> external host USB -> /dev/serial/by-id/...
```

This is the preferred permanent architecture.

## Known-good baseline before adding Cartographer

On the real K2 Pro, the direct three-channel OpenHost stack has already completed:

- Main + Nozzle MCU communication;
- closed-loop motor communication;
- normal CoreXY motion;
- X/Y sensorless/stall homing;
- correct Z direction;
- complete homing with the original PRTouch stack;
- bed/nozzle/chamber heater tests and PID tuning;
- emergency shutdown of active heater loads;
- a successful Klippain-ShakeTune resonance test.

Keep this PRTouch-only state as the rollback baseline while validating direct-USB Cartographer.

## Why direct USB

Cartographer is itself a Klipper MCU. It continuously streams samples and may reset/re-enumerate its USB device when Klipper performs a firmware restart or automated MCU reset.

A previous K2-OpenHost experiment transported Cartographer through the stock T113 userspace USB bridge, a PTY, a custom multiplexer, the third USB gadget serial channel, a host-side demultiplexer and another PTY. The experiment demonstrated that the protocol could be carried and live Cartographer samples reached external Kalico, but it also added unnecessary reset/reconnect and scheduling failure modes.

During that experiment a duplicate GS2 bridge process was also found, causing RS-485/motor-control contention. After restoring exactly one direct `ttyGS2 <-> ttyS5` bridge, motor communication returned to normal. The final design therefore keeps GS2 dedicated to RS-485/CFS and gives Cartographer its own native CM5 USB path.

## Find the device

After physically connecting Cartographer to the external host:

```bash
lsusb
ls -l /dev/ttyACM* 2>/dev/null || true
ls -l /dev/serial/by-id/
```

Use the persistent `/dev/serial/by-id/...` entry in the configuration.

Example:

```ini
[mcu cartographer]
serial: /dev/serial/by-id/usb-REPLACE_WITH_YOUR_CARTOGRAPHER_ID
restart_method: command
is_non_critical: True
reconnect_interval: 2.0
```

Do not copy a serial identifier from another printer.

## First connection validation

Before any Cartographer-controlled Z movement:

```bash
grep -Ei \
'cartographer|Starting serial connect|identify_response|Timeout on connect|Unable to connect|Serial connection closed' \
~/printer_data/logs/klippy.log | tail -100
```

A successful plugin load should report the Cartographer plugin and the Cartographer MCU should complete its identify/configure sequence without repeated connect timeouts.

From the Klipper console, non-motion checks include:

```text
CARTOGRAPHER_QUERY
QUERY_PROBE
```

`QUERY_PROBE` is only owned by Cartographer when `register_as_probe: true`. In mixed mode it remains owned by the primary probe implementation, expected to be PRTouch in the current K2-OpenHost design.

## Validation sequence

Recommended order:

1. confirm `/dev/ttyUSB0`, `/dev/ttyUSB1` and `/dev/ttyUSB2` remain stable;
2. connect Cartographer directly to the CM5;
3. identify its `/dev/serial/by-id/...` path;
4. start Kalico and confirm Cartographer identifies without reconnect loops;
5. issue non-motion Cartographer queries;
6. verify sensor data changes with target distance;
7. test automated restart/reconnect;
8. only then perform controlled Cartographer probe/touch/scan operations;
9. keep the known-good PRTouch-only configuration available for immediate rollback.

## Remove the experimental MUX/DEMUX path

When moving to direct USB, do not leave the experimental Cartographer MUX/DEMUX active on the third gadget channel. The third channel must be the dedicated RS485 bridge:

```text
ttyGS2 <-> ttyS5 @ 230400
```

On the external host:

```ini
[serial_485 serial485]
serial: /dev/ttyUSB2
baud: 230400
```

There must be exactly one process opening the T113 `ttyGS2`/`ttyS5` pair. Multiple bridge processes or a bridge and multiplexer opening the same TTYs concurrently will cause lost/duplicated traffic and motor/CFS timeouts.

## Reset behaviour

For USB Cartographer, keep:

```ini
restart_method: command
```

A direct USB connection allows the host to observe the normal disconnect/re-enumeration sequence without translating it through a PTY chain.

If an automated reset still fails on direct USB, inspect the real USB device lifecycle (`dmesg`, `/dev/serial/by-id`, Klippy log) before changing firmware or probing configuration.

## Firmware

K2-OpenHost does not require reflashing a known-working Cartographer solely to move it from the T113 to the external host. Validate the existing firmware over direct USB first. Firmware updates should be treated as a separate operation after transport stability is established.

## Status

The direct-USB topology is the selected final design but has not yet completed its full hardware validation cycle. The earlier bridged path proved plugin import and live Cartographer data flow; direct USB is intended to remove the reset/re-enumeration failure modes introduced by the bridge chain.