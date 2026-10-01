# Direct USB transport for K2-OpenHost

## Recommended topology

K2-OpenHost uses the three working USB gadget serial functions on the stock T113 only for the K2 internal hardware buses:

```text
T113 ttyS2 -> ttyGS0 -> external host /dev/ttyUSB0  (main MCU)
T113 ttyS3 -> ttyGS1 -> external host /dev/ttyUSB1  (nozzle MCU)
T113 ttyS5 -> ttyGS2 -> external host /dev/ttyUSB2  (RS485 / CFS)
```

Cartographer should be connected directly to a USB host port on the external Kalico computer:

```text
Cartographer USB -> external host USB -> /dev/serial/by-id/...
```

This is the preferred permanent architecture.

## Why direct USB

Cartographer is itself a Klipper MCU. It continuously streams samples and may reset/re-enumerate its USB device when Klipper performs a firmware restart or automated MCU reset.

A previous K2-OpenHost experiment transported Cartographer through the stock T113 userspace USB bridge, a PTY, a custom multiplexer, the third USB gadget serial channel, a host-side demultiplexer and another PTY. The experiment demonstrated that the protocol could be carried, but it also added unnecessary reset/reconnect and scheduling failure modes and shared bandwidth/latency with the K2 RS485 bus.

The external host already has a native USB host controller, so the additional transport layer is unnecessary.

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

Before any Z movement:

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

`QUERY_PROBE` is only owned by Cartographer when `register_as_probe: true`. In mixed mode it remains owned by the primary probe implementation.

## Remove the experimental MUX/DEMUX path

When moving to direct USB, do not leave the experimental Cartographer MUX/DEMUX active on the third gadget channel. The third channel should return to the dedicated RS485 bridge:

```text
ttyGS2 <-> ttyS5 @ 230400
```

On the external host the RS485 configuration should therefore use the dedicated third service-port channel again:

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
