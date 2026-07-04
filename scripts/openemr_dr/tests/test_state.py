"""Tests for RestoreState."""

from __future__ import annotations

import tempfile
from pathlib import Path

from openemr_dr.models.restore import RestoreContext
from openemr_dr.models.state import RestoreState


def test_state_roundtrip() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / ".restore-state"
        state = RestoreState()
        state.set_path(str(path))
        state.backup_bucket = "b"
        state.snapshot_id = "s"
        state.mark_complete("preflight")
        state.load()
        assert state.completed_phase == "preflight"
        assert state.backup_bucket == "b"


def test_should_run_from_phase() -> None:
    state = RestoreState()
    assert state.should_run("rds", "rds") is True
    assert state.should_run("preflight", "rds") is False


def test_sync_from_context() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s", use_aws_backup=True)
    state = RestoreState()
    state.sync_from_context(ctx)
    assert state.use_aws_backup is True
