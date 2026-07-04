"""Extended orchestrator and CLI tests."""

from __future__ import annotations

import tempfile
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from openemr_dr.errors import DrError
from openemr_dr.models.restore import RestoreContext
from openemr_dr.restore.orchestrator import context_from_metadata, run_restore, run_restore_cli


def test_context_from_metadata_kms() -> None:
    plan = MagicMock(
        backup_bucket="b",
        snapshot_id="s",
        app_data_key="k",
        backup_region="us-east-1",
        metadata_uri="uri",
        kms_key_id="key-123",
    )
    with patch("openemr_dr.restore.orchestrator.load_metadata", return_value=plan):
        ctx = context_from_metadata("uri", "us-west-2")
        assert ctx.custom_kms_key == "key-123"


def test_run_restore_cli_list_phases(capsys: pytest.CaptureFixture[str]) -> None:
    assert run_restore_cli(["--list-phases"]) == 0
    assert "preflight" in capsys.readouterr().out


def test_run_restore_cli_missing_args() -> None:
    with pytest.raises(SystemExit):
        run_restore_cli([])


def test_run_restore_cli_dr_error() -> None:
    with patch("openemr_dr.restore.orchestrator.run_restore", side_effect=DrError("boom")):
        assert run_restore_cli(["b", "s"]) == 1


def test_run_restore_from_metadata() -> None:
    with patch("openemr_dr.restore.orchestrator.context_from_metadata") as mock_ctx:
        mock_ctx.return_value = RestoreContext(backup_bucket="b", snapshot_id="s")
        with patch("openemr_dr.restore.orchestrator.run_restore"):
            assert run_restore_cli(["--from-metadata", "s3://b/m.json", "--region", "us-west-2"]) == 0


def test_run_restore_legacy_order() -> None:
    with patch("openemr_dr.restore.orchestrator.run_phase") as mock_phase:
        ctx = RestoreContext(backup_bucket="b", snapshot_id="s", legacy_order=True)
        with tempfile.TemporaryDirectory() as tmp:
            run_restore(ctx, state_file=str(Path(tmp) / ".restore-state"))
        assert mock_phase.call_count == 3


def test_run_restore_from_phase_skip() -> None:
    with patch("openemr_dr.restore.orchestrator.run_phase") as mock_phase:
        ctx = RestoreContext(backup_bucket="b", snapshot_id="s")
        with tempfile.TemporaryDirectory() as tmp:
            sf = Path(tmp) / ".restore-state"
            run_restore(ctx, from_phase="data", state_file=str(sf))
        called = [call.args[0] for call in mock_phase.call_args_list]
        assert "preflight" not in called
        assert "data" in called
