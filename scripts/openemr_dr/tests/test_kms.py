"""Tests for aws.kms."""

from __future__ import annotations

from unittest.mock import patch

import pytest

from openemr_dr.aws import kms
from openemr_dr.errors import DrError


def test_recover_unencrypted_snapshot() -> None:
    with patch("openemr_dr.aws.kms.run_json") as mock_json:
        mock_json.return_value = {"DBClusterSnapshots": [{"KmsKeyId": None}]}
        kms.recover_snapshot_kms_key("us-west-2", "snap-1")


def test_recover_enabled_key() -> None:
    with patch("openemr_dr.aws.kms.run_json") as mock_json:
        mock_json.return_value = {"DBClusterSnapshots": [{"KmsKeyId": "key-1"}]}
        with patch("openemr_dr.aws.kms._describe_key", return_value=("Enabled", True)):
            kms.recover_snapshot_kms_key("us-west-2", "snap-1")


def test_recover_enables_disabled_key() -> None:
    with patch("openemr_dr.aws.kms.run_json") as mock_json:
        mock_json.return_value = {"DBClusterSnapshots": [{"KmsKeyId": "key-1"}]}
        with patch("openemr_dr.aws.kms._describe_key", side_effect=[("Disabled", False), ("Enabled", True)]):
            with patch("openemr_dr.aws.kms.run") as mock_run:
                mock_run.return_value.returncode = 0
                kms.recover_snapshot_kms_key("us-west-2", "snap-1")
                mock_run.assert_called_once()


def test_recover_fails_when_still_disabled() -> None:
    with patch("openemr_dr.aws.kms.run_json") as mock_json:
        mock_json.return_value = {"DBClusterSnapshots": [{"KmsKeyId": "key-1"}]}
        with patch("openemr_dr.aws.kms._describe_key", return_value=("Disabled", False)):
            with patch("openemr_dr.aws.kms.run"):
                with pytest.raises(DrError, match="not enabled"):
                    kms.recover_snapshot_kms_key("us-west-2", "snap-1")
