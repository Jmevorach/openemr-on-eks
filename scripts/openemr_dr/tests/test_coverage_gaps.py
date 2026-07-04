"""Additional coverage for AWS RDS and wait modules."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from openemr_dr.aws import rds, wait


def test_list_cluster_instances() -> None:
    with patch("openemr_dr.aws.rds.run_json") as mock_json:
        mock_json.return_value = {
            "DBInstances": [
                {"DBInstanceIdentifier": "i-0", "DBClusterIdentifier": "c1"},
                {"DBInstanceIdentifier": "i-1", "DBClusterIdentifier": "c2"},
            ]
        }
        assert rds._list_cluster_instances("us-west-2", "c1") == ["i-0"]


def test_snapshot_details_default_port() -> None:
    with patch("openemr_dr.aws.rds.run_json") as mock_json:
        mock_json.return_value = {"DBClusterSnapshots": [{"Engine": "aurora-mysql", "Port": 0}]}
        assert rds._snapshot_details("us-west-2", "snap")["port"] == 3306


def test_wait_instance_deleted() -> None:
    with patch("openemr_dr.aws.rds.run") as mock_run:
        mock_run.return_value = MagicMock(returncode=1)
        assert wait.current_status("db-instance", "i-1", "us-west-2", expect_deleted=True) == "deleted"


def test_wait_job_timeout() -> None:
    with patch("openemr_dr.restore.aws_backup._run_json", return_value={"Status": "RUNNING"}):
        with patch("openemr_dr.restore.aws_backup.time.sleep"):
            with patch("openemr_dr.restore.aws_backup.time.time", side_effect=[0, 2]):
                with pytest.raises(TimeoutError):
                    from openemr_dr.restore import aws_backup

                    aws_backup.wait_for_restore_job("job", "us-west-2", timeout_seconds=1)


def test_shell_run_retry_succeeds() -> None:
    from openemr_dr.common.shell import run

    with patch("openemr_dr.common.shell.subprocess.run") as mock_sub:
        mock_sub.side_effect = [
            MagicMock(returncode=1, stdout="", stderr=""),
            MagicMock(returncode=0, stdout="ok", stderr=""),
        ]
        with patch("openemr_dr.common.shell.time.sleep"):
            result = run(["echo"], retries=2)
            assert result.returncode == 0


def test_data_job_failure_logs() -> None:
    from openemr_dr.errors import PhaseError
    from openemr_dr.models.restore import RestoreContext
    from openemr_dr.restore.phases import data

    ctx = RestoreContext(
        backup_bucket="b",
        snapshot_id="snap-backup-20260702-120000",
        app_data_key="application-data/app-data-backup-20260702-120000.tar.gz",
    )
    with patch(
        "openemr_dr.restore.phases.data.rds_ops.resolve_db_credentials",
        return_value=("endpoint", "pass"),
    ):
        with patch("openemr_dr.restore.phases.data._apply_configmap"):
            with patch("openemr_dr.restore.phases.data.run_cmd") as mock_run:
                mock_run.side_effect = [
                    MagicMock(returncode=0),
                    MagicMock(returncode=0),
                    MagicMock(returncode=0),
                    MagicMock(returncode=1),
                    MagicMock(returncode=0),
                ]
                with patch("openemr_dr.restore.phases.data.DATA_RESTORE_JOB") as job:
                    job.read_text.return_value = "${NAMESPACE}"
                    with pytest.raises(PhaseError):
                        data.run(ctx)
