"""AWS Backup RDS restore helpers."""

from __future__ import annotations

import json
import time

from openemr_dr.common.shell import run_json as _run_json


def find_recovery_point_for_snapshot(
    vault_name: str,
    snapshot_id: str,
    region: str,
) -> str | None:
    points = _run_json(
        [
            "aws",
            "backup",
            "list-recovery-points-by-backup-vault",
            "--backup-vault-name",
            vault_name,
            "--region",
            region,
        ]
    )
    for point in points.get("RecoveryPoints") or []:
        arn = point.get("RecoveryPointArn") or ""
        if snapshot_id in arn or snapshot_id in json.dumps(point):
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
        ]
    )
    job_id = result.get("RestoreJobId")
    if not job_id:
        raise RuntimeError("start-restore-job did not return RestoreJobId")
    return str(job_id)


def wait_for_restore_job(job_id: str, region: str, timeout_seconds: int = 3600) -> None:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        job = _run_json(
            ["aws", "backup", "describe-restore-job", "--restore-job-id", job_id, "--region", region]
        )
        status = job.get("Status")
        if status == "COMPLETED":
            return
        if status in {"ABORTED", "FAILED"}:
            raise RuntimeError(f"AWS Backup restore job failed: {status}")
        time.sleep(30)
    raise TimeoutError(f"Restore job {job_id} timed out")
