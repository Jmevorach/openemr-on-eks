"""Extended tests for preflight phase."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from openemr_dr.errors import PreflightError
from openemr_dr.models.restore import RestoreContext
from openemr_dr.restore.phases import preflight


def _terraform_state(exists: bool) -> MagicMock:
    state = MagicMock()
    state.exists.return_value = exists
    tf = MagicMock()
    tf.__truediv__.return_value = state
    return tf


def test_preflight_all_pass() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s", aws_region="us-west-2")
    with patch.object(preflight, "TERRAFORM_DIR", _terraform_state(True)):
        with patch("openemr_dr.restore.phases.preflight.run_cmd") as mock_run:
            mock_run.return_value = MagicMock(returncode=0, stdout="arn:user")
            with patch("openemr_dr.restore.phases.preflight.run_json") as mock_json:
                mock_json.return_value = {"DBClusterSnapshots": [{"Status": "available"}]}
                preflight.run(ctx)


def test_preflight_missing_terraform() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s")
    with patch.object(preflight, "TERRAFORM_DIR", _terraform_state(False)):
        with pytest.raises(PreflightError, match="Terraform"):
            preflight.run(ctx)


def test_preflight_missing_bucket() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s")
    with patch.object(preflight, "TERRAFORM_DIR", _terraform_state(True)):
        with patch("openemr_dr.restore.phases.preflight.run_cmd") as mock_run:
            mock_run.return_value = MagicMock(returncode=1)
            with pytest.raises(PreflightError, match="Backup bucket"):
                preflight.run(ctx)


def test_preflight_missing_snapshot() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s")
    with patch.object(preflight, "TERRAFORM_DIR", _terraform_state(True)):
        with patch("openemr_dr.restore.phases.preflight.run_cmd") as mock_run:
            mock_run.return_value = MagicMock(returncode=0, stdout="identity")
            with patch("openemr_dr.restore.phases.preflight.run_json", side_effect=RuntimeError("missing")):
                with pytest.raises(PreflightError, match="RDS snapshot"):
                    preflight.run(ctx)


def test_preflight_snapshot_not_available() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s")
    with patch.object(preflight, "TERRAFORM_DIR", _terraform_state(True)):
        with patch("openemr_dr.restore.phases.preflight.run_cmd") as mock_run:
            mock_run.return_value = MagicMock(returncode=0, stdout="identity")
            with patch("openemr_dr.restore.phases.preflight.run_json") as mock_json:
                mock_json.return_value = {"DBClusterSnapshots": [{"Status": "creating"}]}
                with pytest.raises(PreflightError):
                    preflight.run(ctx)
