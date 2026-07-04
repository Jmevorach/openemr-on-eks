"""Extended AWS module tests."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from openemr_dr.aws import kms, rds, wait
from openemr_dr.aws.terraform_data import load_state, rds_scaling_config, rds_security_group_id
from openemr_dr.errors import DrError
from openemr_dr.restore import aws_backup


def test_wait_snapshot_status() -> None:
    with patch("openemr_dr.aws.wait.run_json") as mock_json:
        mock_json.return_value = {"DBClusterSnapshots": [{"Status": "available"}]}
        assert wait.current_status("snapshot", "s1", "us-west-2") == "available"


def test_wait_unknown_resource_type() -> None:
    with pytest.raises(DrError):
        wait.wait_for_resource("invalid", "x", "available", "us-west-2", max_wait_seconds=1, check_interval=1)  # type: ignore[arg-type]


def test_kms_cancel_pending_deletion() -> None:
    with patch("openemr_dr.aws.kms.run_json") as mock_json:
        mock_json.return_value = {"DBClusterSnapshots": [{"KmsKeyId": "key-1"}]}
        with patch(
            "openemr_dr.aws.kms._describe_key",
            side_effect=[("PendingDeletion", False), ("Enabled", True)],
        ):
            with patch("openemr_dr.aws.kms.run") as mock_run:
                mock_run.return_value = MagicMock(returncode=0)
                kms.recover_snapshot_kms_key("us-west-2", "snap")


def test_destroy_existing_cluster_full_path() -> None:
    with patch("openemr_dr.aws.rds._cluster_exists", return_value=True):
        with patch("openemr_dr.aws.rds.run_json") as mock_json:
            mock_json.side_effect = [
                {"DBClusters": [{"Status": "available", "DeletionProtection": True}]},
                {"DBInstances": [{"DBInstanceIdentifier": "i-0", "DBClusterIdentifier": "c1"}]},
            ]
            with patch("openemr_dr.aws.rds._list_cluster_instances", return_value=["i-0"]):
                with patch("openemr_dr.aws.rds.run"):
                    with patch("openemr_dr.aws.rds.wait.wait_for_resource"):
                        rds.destroy_existing_cluster("us-west-2", "c1")


def test_restore_via_aws_backup_success() -> None:
    with patch(
        "openemr_dr.aws.rds.terraform_output",
        side_effect=lambda n: {"backup_vault_name": "v", "backup_iam_role_arn": "arn"}.get(n, "x"),
    ):
        with patch("openemr_dr.aws.rds.terraform_data.rds_security_group_id", return_value="sg"):
            with patch("openemr_dr.aws.rds.destroy_existing_cluster"):
                with patch(
                    "openemr_dr.aws.rds.aws_backup.find_recovery_point_for_snapshot",
                    return_value="rp",
                ):
                    with patch("openemr_dr.aws.rds.aws_backup.start_rds_restore_job", return_value="job"):
                        with patch("openemr_dr.aws.rds.aws_backup.wait_for_restore_job"):
                            with patch("openemr_dr.aws.rds.reset_master_password"):
                                rds.restore_via_aws_backup("us-west-2", "c1", "snap")


def test_aws_backup_wait_job_failure() -> None:
    with patch("openemr_dr.restore.aws_backup._run_json") as mock_json:
        mock_json.return_value = {"Status": "FAILED"}
        with patch("openemr_dr.restore.aws_backup.time.sleep"):
            with pytest.raises(RuntimeError):
                aws_backup.wait_for_restore_job("job", "us-west-2", timeout_seconds=1)


def test_aws_backup_start_job_missing_id() -> None:
    with patch("openemr_dr.restore.aws_backup._run_json", return_value={}):
        with pytest.raises(RuntimeError):
            aws_backup.start_rds_restore_job("rp", "c", "us-west-2", "arn", "subnet", [])


def test_aws_backup_find_recovery_point() -> None:
    with patch("openemr_dr.restore.aws_backup._run_json") as mock_json:
        mock_json.return_value = {"RecoveryPoints": [{"RecoveryPointArn": "arn:snap-1"}]}
        assert aws_backup.find_recovery_point_for_snapshot("vault", "snap-1", "us-west-2") == "arn:snap-1"


def test_load_state() -> None:
    with patch("openemr_dr.aws.terraform_data.run") as mock_run:
        mock_run.return_value = MagicMock(stdout='{"values": {}}')
        assert load_state() == {"values": {}}


def test_rds_scaling_invalid_values() -> None:
    state = {
        "values": {
            "root_module": {
                "resources": [
                    {
                        "type": "aws_rds_cluster",
                        "name": "openemr",
                        "values": {"serverlessv2_scaling_configuration": [{"min_capacity": "x", "max_capacity": "y"}]},
                    }
                ]
            }
        }
    }
    assert rds_scaling_config(state) == (0.5, 16.0)
    assert rds_security_group_id({}) == ""
