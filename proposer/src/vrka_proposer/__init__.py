"""25 Hz Flow-Matching VLA trajectory proposer package for vrka-vla."""

from __future__ import annotations

import math
from dataclasses import dataclass

PROPOSER_NOMINAL_HZ: int = 25


@dataclass(frozen=True, slots=True)
class ActionChunk:
    """Action chunk emitted by the 25 Hz VLA proposer."""

    chunk_ttl: int
    cmd_vel: float
    epoch: int

    def is_valid(self) -> bool:
        """Validate finite numerical constraints and positive lease duration."""
        return (
            self.chunk_ttl > 0
            and math.isfinite(self.cmd_vel)
            and self.cmd_vel >= 0.0
            and self.epoch >= 0
        )


__all__: tuple[str, ...] = (
    "PROPOSER_NOMINAL_HZ",
    "ActionChunk",
)
