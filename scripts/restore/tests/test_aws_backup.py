"""Unit tests for AWS Backup restore helpers."""

from __future__ import annotations

import json
import unittest
from pathlib import Path
from unittest.mock import patch

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import aws_backup  # noqa: E402


class TestAwsBackupHelpers(unittest.TestCase):
    def test_find_recovery_point_match_in_arn(self) -> None:
        snapshot = "openemr-eks-test-backup-20260702-213048"
        payload = {
            "RecoveryPoints": [
                {
                    "RecoveryPointArn": f"arn:aws:backup:us-west-2:123:recovery-point:{snapshot}",
                    "ResourceArn": "arn:aws:rds:us-west-2:123:cluster:openemr",
                }
            ]
        }

        with patch.object(aws_backup, "_run_json", return_value=payload):
            arn = aws_backup.find_recovery_point_for_snapshot("vault", snapshot, "us-west-2")

        self.assertIn(snapshot, arn or "")

    def test_find_recovery_point_no_match(self) -> None:
        with patch.object(aws_backup, "_run_json", return_value={"RecoveryPoints": []}):
            arn = aws_backup.find_recovery_point_for_snapshot("vault", "missing", "us-west-2")
        self.assertIsNone(arn)

    def test_start_rds_restore_job_returns_id(self) -> None:
        with patch.object(aws_backup, "_run_json", return_value={"RestoreJobId": "job-123"}):
            job_id = aws_backup.start_rds_restore_job(
                "arn:recovery:point",
                "cluster-id",
                "us-west-2",
                "arn:iam::123:role/backup",
                "subnet-group",
                ["sg-abc"],
            )
        self.assertEqual(job_id, "job-123")

    def test_start_rds_restore_job_missing_id_raises(self) -> None:
        with patch.object(aws_backup, "_run_json", return_value={}):
            with self.assertRaises(RuntimeError):
                aws_backup.start_rds_restore_job(
                    "arn:recovery:point", "c", "us-west-2", "role", "subnet", []
                )

    def test_wait_for_restore_job_completed(self) -> None:
        with patch.object(aws_backup, "_run_json", return_value={"Status": "COMPLETED"}):
            aws_backup.wait_for_restore_job("job-1", "us-west-2", timeout_seconds=5)

    def test_wait_for_restore_job_failed(self) -> None:
        with patch.object(aws_backup, "_run_json", return_value={"Status": "FAILED", "StatusMessage": "boom"}):
            with self.assertRaises(RuntimeError):
                aws_backup.wait_for_restore_job("job-1", "us-west-2", timeout_seconds=5)

    def test_start_restore_passes_metadata_json(self) -> None:
        captured: list[list[str]] = []

        def fake_run_json(cmd: list[str]) -> dict:
            captured.append(cmd)
            return {"RestoreJobId": "job-99"}

        with patch.object(aws_backup, "_run_json", side_effect=fake_run_json):
            aws_backup.start_rds_restore_job(
                "arn:rp", "cluster-x", "us-west-2", "arn:role", "subnet-y", ["sg-1", "sg-2"]
            )

        metadata_arg = captured[0][captured[0].index("--metadata") + 1]
        meta = json.loads(metadata_arg)
        self.assertEqual(meta["DBClusterIdentifier"], "cluster-x")
        self.assertEqual(meta["VpcSecurityGroupIds"], ["sg-1", "sg-2"])


if __name__ == "__main__":
    unittest.main()
