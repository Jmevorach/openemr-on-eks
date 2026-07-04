"""AWS Backup RDS restore helpers."""

from __future__ import annotations

import json
import subprocess
import time
from typing import Any


def _run_json(cmd: list[str]) -> Any:
    result = subprocess.run(cmd, check=False, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return json.loads(result.stdout or "null")


def find_recovery_point_for_snapshot(
    vault_name: str,
    snapshot_id: str,
    region: str,
) -> str | None:
    """Find AWS Backup recovery point ARN matching an RDS snapshot identifier."""
    points = _run_json(
        [
            "aws",
            "backup",
            "list-recovery-points-by-backup-vault",
            "--backup-vault-name",
            vault_name,
            "--region",
            region,
            "--output",
            "json",
        ]
    )
    for point in points.get("RecoveryPoints") or []:
        arn = point.get("RecoveryPointArn") or ""
        if snapshot_id in arn or snapshot_id in json.dumps(point):
            return arn
        meta = point.get("ResourceArn") or ""
        if snapshot_id in meta:
            return arn
    return None


def start_rds_restore_job(
    recovery_point_arn: str,
    cluster_identifier: str,
    region: str,
    iam_role_arn: str,
    subnet_group: str,
    security_groups: list[str],
) -> str:
    metadata = {
        "DBClusterIdentifier": cluster_identifier,
        "DBSubnetGroupName": subnet_group,
        "VpcSecurityGroupIds": security_groups,
    }
    result = _run_json(
        [
            "aws",
            "backup",
            "start-restore-job",
            "--recovery-point-arn",
            recovery_point_arn,
            "--iam-role-arn",
            iam_role_arn,
            "--metadata",
            json.dumps(metadata),
            "--region",
            region,
            "--output",
            "json",
        ]
    )
    job_id = result.get("RestoreJobId")
    if not job_id:
        raise RuntimeError("start-restore-job did not return RestoreJobId")
    return job_id


def wait_for_restore_job(job_id: str, region: str, timeout_seconds: int = 3600) -> None:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        job = _run_json(
            [
                "aws",
                "backup",
                "describe-restore-job",
                "--restore-job-id",
                job_id,
                "--region",
                region,
                "--output",
                "json",
            ]
        )
        status = job.get("Status")
        if status == "COMPLETED":
            return
        if status in {"ABORTED", "FAILED"}:
            raise RuntimeError(f"AWS Backup restore job failed: {status} - {job.get('StatusMessage')}")
        time.sleep(30)
    raise TimeoutError(f"AWS Backup restore job {job_id} did not complete within {timeout_seconds}s")
