"""Placeholder smoke test for the vrka-proposer package."""

from __future__ import annotations

from vrka_proposer import PROPOSER_NOMINAL_HZ


def test_proposer_nominal_frequency() -> None:
    """Verify nominal proposer frequency constant."""
    assert PROPOSER_NOMINAL_HZ == 25
