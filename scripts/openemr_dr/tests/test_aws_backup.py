"""Tests for AWS Backup helpers."""

from __future__ import annotations

import unittest
from unittest.mock import patch

from openemr_dr.restore import aws_backup


class TestAwsBackup(unittest.TestCase):
    @patch("openemr_dr.restore.aws_backup._run_json")
    def test_find_recovery_point(self, mock_json) -> None:
        mock_json.return_value = {
            "RecoveryPoints": [{"RecoveryPointArn": "arn:backup:rp:openemr-backup-20260702"}]
        }
        arn = aws_backup.find_recovery_point_for_snapshot("vault", "openemr-backup-20260702", "us-west-2")
        self.assertIsNotNone(arn)

    @patch("openemr_dr.restore.aws_backup._run_json")
    def test_start_job(self, mock_json) -> None:
        mock_json.return_value = {"RestoreJobId": "job-1"}
        jid = aws_backup.start_rds_restore_job("arn:rp", "cluster", "us-west-2", "arn:role", "subnet", [])
        self.assertEqual(jid, "job-1")


if __name__ == "__main__":
    unittest.main()
