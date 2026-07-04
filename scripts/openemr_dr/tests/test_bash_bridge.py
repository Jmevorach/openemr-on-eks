"""Tests for bash bridge and phase registry."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from openemr_dr.errors import PhaseError
from openemr_dr.models.restore import RestoreContext
from openemr_dr.restore import bash_bridge
from openemr_dr.restore.phases import BASH_BRIDGE, NATIVE, run_phase


def test_native_phases_registered() -> None:
    assert set(NATIVE) == {"preflight", "bootstrap", "rds", "data", "deploy", "verify"}
    assert frozenset({"legacy"}) == BASH_BRIDGE


def test_run_unknown_phase() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s")
    with pytest.raises(ValueError, match="Unknown phase"):
        run_phase("nope", ctx)


def test_bash_bridge_failure() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s")
    with patch("openemr_dr.restore.bash_bridge.run") as mock_run:
        mock_run.return_value = MagicMock(returncode=1)
        with pytest.raises(PhaseError):
            bash_bridge.run_bash_phase("legacy", ctx)
