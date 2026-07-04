"""Tests for aws.wait."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from openemr_dr.aws import wait
from openemr_dr.errors import DrError


def test_current_status_cluster_available() -> None:
    with patch("openemr_dr.aws.wait.run_json") as mock_json:
        mock_json.return_value = {"DBClusters": [{"Status": "available"}]}
        assert wait.current_status("db-cluster", "c1", "us-west-2") == "available"


def test_current_status_cluster_deleted() -> None:
    with patch("openemr_dr.aws.wait.run") as mock_run:
        mock_run.return_value = MagicMock(returncode=1)
        assert wait.current_status("db-cluster", "c1", "us-west-2", expect_deleted=True) == "deleted"


def test_wait_for_resource_success() -> None:
    with patch("openemr_dr.aws.wait.current_status", side_effect=["creating", "available"]):
        with patch("openemr_dr.aws.wait.time.sleep"):
            wait.wait_for_resource("db-cluster", "c1", "available", "us-west-2", max_wait_seconds=60, check_interval=1)


def test_wait_for_resource_timeout() -> None:
    with patch("openemr_dr.aws.wait.current_status", return_value="creating"):
        with patch("openemr_dr.aws.wait.time.sleep"):
            with pytest.raises(DrError, match="Timeout"):
                wait.wait_for_resource(
                    "db-cluster",
                    "c1",
                    "available",
                    "us-west-2",
                    max_wait_seconds=1,
                    check_interval=1,
                )
