from __future__ import annotations

import logging
from typing import TYPE_CHECKING, cast, final

from mcu import MCU_endstop
from typing_extensions import override

from cartographer.adapters.klipper_like.utils import reraise_for_klipper
from cartographer.interfaces.printer import HomingAxis, HomingState

if TYPE_CHECKING:
    from extras.homing import Homing
    from mcu import MCU
    from reactor import ReactorCompletion
    from stepper import MCU_stepper

    from cartographer.adapters.klipper.mcu.mcu import KlipperCartographerMcu
    from cartographer.interfaces.printer import Endstop

logger = logging.getLogger(__name__)

axis_mapping: dict[HomingAxis, int] = {
    "x": 0,
    "y": 1,
    "z": 2,
}


def axis_to_index(axis: HomingAxis) -> int:
    return axis_mapping[axis]


@final
class KlipperHomingState(HomingState):
    def __init__(self, homing: Homing) -> None:
        self.homing = homing

    @override
    def is_homing_z(self) -> bool:
        return axis_to_index("z") in self.homing.get_axes()

    @override
    def set_z_homed_position(self, position: float) -> None:
        logger.debug("Setting homed distance for z to %.3f", position)
        self.homing.set_homed_position([None, None, position])


class KlipperEndstopBase(MCU_endstop):
    """Bridge Cartographer's endstop interface to Klipper/Kalico MCU_endstop.

    The base intentionally does not expose ``get_position_endstop``.  Newer
    Klipper/Kalico homing code uses the presence of that method to decide
    whether Z homing should be routed through the canonical probe object.  In
    mixed mode Cartographer is not that object, so the plain endstop must not
    advertise probe-session semantics.
    """

    def __init__(self, mcu: KlipperCartographerMcu, endstop: Endstop):
        self.mcu = mcu
        self.endstop = endstop

    @override
    def get_mcu(self) -> MCU:
        return self.mcu.klipper_mcu

    @override
    def add_stepper(self, stepper: MCU_stepper) -> None:
        return self.mcu.dispatch.add_stepper(stepper)

    @override
    def get_steppers(self) -> list[MCU_stepper]:
        return self.mcu.dispatch.get_steppers()

    @override
    @reraise_for_klipper
    def home_start(
        self,
        print_time: float,
        sample_time: float,
        sample_count: int,
        rest_time: float,
        triggered: bool = True,
    ) -> ReactorCompletion:
        del sample_time, sample_count, rest_time, triggered
        return cast("ReactorCompletion", self.endstop.home_start(print_time))

    @override
    @reraise_for_klipper
    def home_wait(self, home_end_time: float) -> float:
        return self.endstop.home_wait(home_end_time)

    @override
    @reraise_for_klipper
    def query_endstop(self, print_time: float) -> int:
        # Preserve Jacob's K2 non-critical MCU behaviour.  When Cartographer is
        # temporarily disconnected, report the endstop as triggered so an
        # unsafe Z move is not started through the missing sensor path.
        klipper_mcu = self.mcu.klipper_mcu
        is_disconnected = (
            hasattr(klipper_mcu, "is_non_critical")
            and klipper_mcu.is_non_critical
            and hasattr(klipper_mcu, "non_critical_disconnected")
            and klipper_mcu.non_critical_disconnected
        )
        if is_disconnected:
            return 1
        return 1 if self.endstop.query_is_triggered(print_time) else 0


@final
class KlipperProbeEndstop(KlipperEndstopBase):
    """Endstop used when Cartographer owns the canonical ``probe`` object.

    Exposing ``get_position_endstop`` tells newer Klipper/Kalico homing code
    that this endstop may use the probe-session Z-homing path.
    """

    @override
    def get_position_endstop(self) -> float:
        return self.endstop.get_endstop_position()


@final
class KlipperEndstop(KlipperEndstopBase):
    """Plain endstop for mixed mode and Cartographer-internal probing moves.

    Deliberately does not expose ``get_position_endstop``.  This prevents a
    Cartographer endstop registered as ``cartographer_probe`` from being routed
    through a different primary probe object such as K2 PRTouch.
    """

    pass
