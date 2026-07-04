"""Tests for aws.rds operations."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from openemr_dr.aws import rds
from openemr_dr.errors import DrError


def test_destroy_skips_missing_cluster() -> None:
    with patch("openemr_dr.aws.rds._cluster_exists", return_value=False):
        rds.destroy_existing_cluster("us-west-2", "cluster-1")


def test_reset_master_password_success() -> None:
    with patch("openemr_dr.aws.rds.terraform_output", return_value="secret"):
        with patch("openemr_dr.aws.rds.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)
            rds.reset_master_password("us-west-2", "cluster-1")


def test_reset_master_password_failure() -> None:
    with patch("openemr_dr.aws.rds.terraform_output", return_value="secret"):
        with patch("openemr_dr.aws.rds.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=1)
            with patch("openemr_dr.aws.rds.time.sleep"), pytest.raises(DrError, match="Failed to reset"):
                rds.reset_master_password("us-west-2", "cluster-1")


def test_restore_cluster_from_snapshot() -> None:
    tf_outputs = {
        "aurora_db_subnet_group_name": "subnet-g",
        "aurora_engine_version": "8.0",
        "cluster_name": "openemr-eks-test",
    }
    with (
        patch("openemr_dr.aws.rds.kms.recover_snapshot_kms_key"),
        patch("openemr_dr.aws.rds.destroy_existing_cluster"),
        patch("openemr_dr.aws.rds._snapshot_details", return_value={"engine": "aurora-mysql", "port": 3306}),
        patch("openemr_dr.aws.rds.terraform_output", side_effect=lambda n: tf_outputs.get(n, "")),
        patch("openemr_dr.aws.rds.terraform_data.rds_security_group_id", return_value="sg-1"),
        patch("openemr_dr.aws.rds.run"),
        patch("openemr_dr.aws.rds.wait.wait_for_resource"),
        patch("openemr_dr.aws.rds.terraform_data.rds_scaling_config", return_value=(0.5, 16)),
        patch("openemr_dr.aws.rds.terraform_data.rds_instance_count", return_value=1),
        patch("openemr_dr.aws.rds.reset_master_password"),
    ):
        rds.restore_cluster_from_snapshot("us-west-2", "c1", "snap-1")


def test_restore_via_aws_backup_fallback() -> None:
    with patch("openemr_dr.aws.rds.terraform_output", return_value=""):
        with patch("openemr_dr.aws.rds.terraform_data.rds_security_group_id", return_value="sg-1"):
            with patch("openemr_dr.aws.rds.restore_cluster_from_snapshot") as mock_snap:
                rds.restore_via_aws_backup("us-west-2", "c1", "snap-1")
                mock_snap.assert_called_once()


def test_resolve_db_credentials_from_aws_when_pending() -> None:
    with patch("openemr_dr.aws.rds.terraform_output", side_effect=lambda name: {
        "aurora_cluster_id": "cluster-1",
        "aurora_password": "secret",
        "aurora_endpoint": "pending-restore",
    }.get(name, "")):
        with patch(
            "openemr_dr.aws.rds.cluster_endpoint",
            return_value="cluster-1.cluster.rds.amazonaws.com",
        ) as mock_ep:
            endpoint, password = rds.resolve_db_credentials("us-west-2")
            assert endpoint == "cluster-1.cluster.rds.amazonaws.com"
            assert password == "secret"
            mock_ep.assert_called_once_with("us-west-2", "cluster-1")


def test_resolve_db_credentials_uses_terraform_endpoint() -> None:
    with patch("openemr_dr.aws.rds.terraform_output", side_effect=lambda name: {
        "aurora_cluster_id": "cluster-1",
        "aurora_password": "secret",
        "aurora_endpoint": "tf-endpoint.rds.amazonaws.com",
    }.get(name, "")):
        endpoint, password = rds.resolve_db_credentials("us-west-2")
        assert endpoint == "tf-endpoint.rds.amazonaws.com"
        assert password == "secret"
