"""Backup manifest v2 builder."""

from __future__ import annotations

from typing import Any


def build_manifest(
    *,
    backup_id: str,
    timestamp: str,
    source_region: str,
    backup_region: str,
    cluster_name: str,
    namespace: str,
    backup_bucket: str,
    openemr_version: str,
    aurora_cluster_id: str,
    snapshot_id: str,
    backup_success: bool,
    backup_strategy: str,
    target_account_id: str,
    kms_key_id: str,
    copy_tags: bool,
    app_backup_file: str,
    database_config: dict[str, Any],
    created_by: str,
    aws_account: str,
) -> dict[str, Any]:
    app_data_key = f"application-data/{app_backup_file}"
    metadata_key = f"backup-metadata-{timestamp}.json"
    return {
        "manifest_version": 2,
        "backup_id": backup_id,
        "timestamp": timestamp,
        "source_region": source_region,
        "backup_region": backup_region,
        "cluster_name": cluster_name,
        "namespace": namespace,
        "backup_bucket": backup_bucket,
        "openemr_version": openemr_version,
        "aurora_cluster_id": aurora_cluster_id or "none",
        "aurora_snapshot_id": snapshot_id or "none",
        "backup_success": backup_success,
        "backup_strategy": backup_strategy,
        "target_account_id": target_account_id or "none",
        "kms_key_id": kms_key_id or "auto-detected",
        "copy_tags": copy_tags,
        "components": {
            "aurora_rds": bool(snapshot_id),
            "kubernetes_config": True,
            "application_data": True,
        },
        "restore_plan": {
            "backup_bucket": backup_bucket,
            "snapshot_id": snapshot_id or "none",
            "app_data_key": app_data_key,
            "openemr_version": openemr_version,
            "backup_strategy": backup_strategy,
            "backup_region": backup_region,
            "kms_key_id": kms_key_id or "auto-detected",
        },
        "database_config": database_config,
        "restore_command": f"./restore.sh --from-metadata s3://{backup_bucket}/metadata/{metadata_key}",
        "created_by": created_by,
        "aws_account": aws_account,
    }
