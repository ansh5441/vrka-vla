"""Contract test for 25 Hz Flow-Matching VLA proposer (Scenario S-01)."""

from __future__ import annotations

import pytest

from vrka_proposer import PROPOSER_NOMINAL_HZ, ActionChunk

EXPECTED_PROPOSER_HZ: int = 25
EXPECTED_CHUNK_TTL: int = 3
EXPECTED_CMD_VEL: float = 1.5


@pytest.mark.skip(reason="vrka-contract")
def test_s01_proposer_chunk_contract() -> None:
    """Verify action chunk dataclass constraints and nominal frequency."""
    assert PROPOSER_NOMINAL_HZ == EXPECTED_PROPOSER_HZ

    chunk = ActionChunk(chunk_ttl=EXPECTED_CHUNK_TTL, cmd_vel=EXPECTED_CMD_VEL, epoch=1)
    assert chunk.is_valid()
    assert chunk.chunk_ttl == EXPECTED_CHUNK_TTL
    assert chunk.cmd_vel == EXPECTED_CMD_VEL

    invalid_chunk = ActionChunk(chunk_ttl=0, cmd_vel=EXPECTED_CMD_VEL, epoch=1)
    assert not invalid_chunk.is_valid()
