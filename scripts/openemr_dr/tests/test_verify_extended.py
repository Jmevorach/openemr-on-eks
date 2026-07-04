"""Extended verify phase tests."""

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from openemr_dr.errors import PhaseError
from openemr_dr.models.restore import RestoreContext
from openemr_dr.restore.phases import verify


def test_deployment_replicas() -> None:
    with patch("openemr_dr.restore.phases.verify.run_cmd") as mock_run:
        mock_run.side_effect = [
            MagicMock(stdout="2"),
            MagicMock(stdout="3"),
        ]
        assert verify._deployment_replicas("openemr") == (2, 3)


def test_running_pod_and_health() -> None:
    with patch("openemr_dr.restore.phases.verify.run_cmd") as mock_run:
        mock_run.side_effect = [
            MagicMock(stdout="pod-1"),
            MagicMock(stdout="True"),
            MagicMock(returncode=0),
        ]
        assert verify._running_pod("openemr") == "pod-1"
        assert verify._pod_is_ready("openemr", "pod-1") is True
        assert verify._pod_serves_http("openemr", "pod-1") is True


def test_restore_autoscaling_applies(tmp_path: Path) -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s", namespace="openemr")
    hpa = tmp_path / "hpa.yaml"
    hpa.write_text("replicas: 2", encoding="utf-8")
    with patch("openemr_dr.restore.phases.verify.K8S_DIR", tmp_path):
        with patch("openemr_dr.restore.phases.verify.run_cmd") as mock_run:
            verify.restore_autoscaling(ctx)
            mock_run.assert_called_once()


def test_restore_autoscaling_skips_placeholders(tmp_path: Path) -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s")
    hpa = tmp_path / "hpa.yaml"
    hpa.write_text("${OPENEMR_MIN_REPLICAS}", encoding="utf-8")
    with patch("openemr_dr.restore.phases.verify.K8S_DIR", tmp_path):
        verify.restore_autoscaling(ctx)


def test_cleanup_crypto_keys_no_pods() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s", namespace="openemr")
    with patch("openemr_dr.restore.phases.verify.time.sleep"):
        with patch("openemr_dr.restore.phases.verify.run_cmd", return_value=MagicMock(stdout="")):
            verify.cleanup_crypto_keys(ctx)


def test_cleanup_crypto_keys_with_pods() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s", namespace="openemr")
    with patch("openemr_dr.restore.phases.verify.time.sleep"):
        with patch("openemr_dr.restore.phases.verify.run_cmd", return_value=MagicMock(stdout="pod-a pod-b")):
            verify.cleanup_crypto_keys(ctx)


def test_verify_once_success() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s", namespace="openemr")
    with patch("openemr_dr.restore.phases.verify._deployment_replicas", return_value=(1, 1)):
        with patch("openemr_dr.restore.phases.verify.openemr_pod_is_healthy", return_value=True):
            assert verify.verify_once(ctx) is True


def test_verify_once_no_deployment() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s", namespace="openemr")
    with patch("openemr_dr.restore.phases.verify._deployment_replicas", return_value=(0, 0)):
        with patch("openemr_dr.restore.phases.verify.time.sleep"):
            assert verify.verify_once(ctx) is False


def test_openemr_pod_unhealthy() -> None:
    with patch("openemr_dr.restore.phases.verify._running_pod", return_value=""):
        assert verify.openemr_pod_is_healthy("openemr") is False


def test_prepare_single_replica_no_deployment() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s", namespace="openemr")
    with patch("openemr_dr.restore.phases.verify.run_cmd") as mock_run:
        mock_run.side_effect = [
            MagicMock(returncode=0),
            MagicMock(returncode=1),
        ]
        verify.prepare_single_replica(ctx)


def test_deploy_failure_on_deploy_sh() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s")
    with patch("openemr_dr.restore.phases.deploy.run_cmd") as mock_run:
        mock_run.side_effect = [
            MagicMock(returncode=0),
            MagicMock(returncode=0),
            MagicMock(returncode=1),
        ]
        with pytest.raises(PhaseError, match=r"deploy\.sh"):
            from openemr_dr.restore.phases import deploy

            deploy.run(ctx)
