"""Tests for verify helpers."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

from openemr_dr.models.restore import RestoreContext
from openemr_dr.restore.phases import verify


def test_normalize_replica_count() -> None:
    assert verify._normalize_replica_count("") == 0
    assert verify._normalize_replica_count("2") == 2
    assert verify._normalize_replica_count("x") == 0


def test_openemr_pod_is_healthy() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s", namespace="openemr")
    with patch("openemr_dr.restore.phases.verify._running_pod", return_value="pod-1"):
        with patch("openemr_dr.restore.phases.verify._pod_is_ready", return_value=True):
            with patch("openemr_dr.restore.phases.verify._pod_serves_http", return_value=True):
                assert verify.openemr_pod_is_healthy(ctx.namespace) is True


def test_prepare_single_replica() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s", namespace="openemr")
    with patch("openemr_dr.restore.phases.verify.run_cmd") as mock_run:
        mock_run.return_value = MagicMock(returncode=0)
        verify.prepare_single_replica(ctx)
