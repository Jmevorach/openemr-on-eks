"""Tests for restore phases."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from openemr_dr.errors import PhaseError
from openemr_dr.models.restore import RestoreContext
from openemr_dr.restore.phases import bootstrap, data, deploy, rds, verify


def test_bootstrap_dry_run() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s", dry_run=True)
    bootstrap.run(ctx)


def test_rds_dry_run() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s", dry_run=True)
    with patch("openemr_dr.restore.phases.rds.terraform_output", return_value="cluster-1"):
        rds.run(ctx)


def test_rds_missing_cluster_id() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s")
    with patch("openemr_dr.restore.phases.rds.terraform_output", return_value=""):
        with pytest.raises(PhaseError, match="aurora_cluster_id"):
            rds.run(ctx)


def test_deploy_success() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s")
    with patch("openemr_dr.restore.phases.deploy.run_cmd") as mock_run:
        mock_run.return_value = MagicMock(returncode=0)
        with patch("openemr_dr.restore.phases.deploy.verify_phase.prepare_single_replica"):
            with patch("openemr_dr.restore.phases.deploy.verify_phase.cleanup_crypto_keys"):
                deploy.run(ctx)


def test_verify_dry_run() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s", dry_run=True)
    verify.run(ctx)


def test_verify_success() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s", namespace="openemr")
    with patch("openemr_dr.restore.phases.verify.verify_once", return_value=True):
        with patch("openemr_dr.restore.phases.verify.restore_autoscaling"):
            verify.run(ctx)


def test_data_dry_run() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="snap-backup-20260702-120000", app_data_key="k")
    with patch("openemr_dr.restore.phases.data.rds_ops.resolve_db_credentials", return_value=("endpoint", "pass")):
        ctx.dry_run = True
        data.run(ctx)
