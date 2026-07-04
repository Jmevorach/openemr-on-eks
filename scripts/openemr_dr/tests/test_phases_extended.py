"""Phase module extended tests."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from openemr_dr.errors import PhaseError
from openemr_dr.models.restore import RestoreContext
from openemr_dr.restore.phases import bootstrap, data, deploy, rds, verify


def test_bootstrap_failure() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s")
    with patch("openemr_dr.restore.phases.bootstrap.run_cmd") as mock_run:
        mock_run.return_value = MagicMock(returncode=1)
        with pytest.raises(PhaseError):
            bootstrap.run(ctx)


def test_rds_live_failure() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s")
    with patch("openemr_dr.restore.phases.rds.terraform_output", return_value="cluster"):
        with patch(
            "openemr_dr.restore.phases.rds.rds_ops.restore_cluster_from_snapshot",
            side_effect=RuntimeError("aws"),
        ):
            with pytest.raises(PhaseError):
                rds.run(ctx)


def test_deploy_failure_defaults() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s")
    with patch("openemr_dr.restore.phases.deploy.run_cmd") as mock_run:
        mock_run.return_value = MagicMock(returncode=1)
        with pytest.raises(PhaseError):
            deploy.run(ctx)


def test_verify_failure() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s", namespace="openemr")
    with patch("openemr_dr.restore.phases.verify.verify_once", return_value=False):
        with patch("openemr_dr.restore.phases.verify.cleanup_crypto_keys"):
            with patch("openemr_dr.restore.phases.verify._deployment_replicas", return_value=(0, 1)):
                with pytest.raises(PhaseError):
                    verify.run(ctx)


def test_data_restore_job_path(tmp_path) -> None:
    ctx = RestoreContext(
        backup_bucket="b",
        snapshot_id="snap-backup-20260702-120000",
        app_data_key="application-data/app-data-backup-20260702-120000.tar.gz",
        namespace="openemr",
    )
    job_file = tmp_path / "job.yaml"
    job_file.write_text("${NAMESPACE}", encoding="utf-8")
    script_file = tmp_path / "script.sh"
    script_file.write_text("#!/bin/sh", encoding="utf-8")
    with patch("openemr_dr.restore.phases.data.DATA_RESTORE_JOB", job_file):
        with patch("openemr_dr.restore.phases.data.DATA_RESTORE_SCRIPT", script_file):
            with patch(
                "openemr_dr.restore.phases.data.rds_ops.resolve_db_credentials",
                return_value=("endpoint", "pass"),
            ):
                with patch("openemr_dr.restore.phases.data.run_cmd") as mock_run:
                    mock_run.return_value = MagicMock(returncode=0, stdout="apiVersion: v1")
                    with patch("openemr_dr.restore.phases.data.subprocess.run"):
                        data.run(ctx)
                    assert mock_run.call_count >= 3
