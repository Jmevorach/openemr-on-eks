"""RDS cluster destroy, restore, and password reset."""

from __future__ import annotations

import time

from openemr_dr import config
from openemr_dr.aws import kms, terraform_data, wait
from openemr_dr.common import log
from openemr_dr.common.shell import run, run_json, terraform_output
from openemr_dr.errors import DrError
from openemr_dr.restore import aws_backup


def _cluster_exists(region: str, cluster_id: str) -> bool:
    probe = run(
        [
            "aws",
            "rds",
            "describe-db-clusters",
            "--region",
            region,
            "--db-cluster-identifier",
            cluster_id,
        ],
        capture=True,
        check=False,
    )
    return probe.returncode == 0


def _list_cluster_instances(region: str, cluster_id: str) -> list[str]:
    data = run_json(
        [
            "aws",
            "rds",
            "describe-db-instances",
            "--region",
            region,
        ],
        retries=3,
    )
    ids: list[str] = []
    for inst in data.get("DBInstances") or []:
        if inst.get("DBClusterIdentifier") == cluster_id:
            ident = inst.get("DBInstanceIdentifier")
            if ident:
                ids.append(str(ident))
    return ids


def destroy_existing_cluster(region: str, cluster_id: str) -> None:
    """Delete an existing Aurora cluster and its instances before restore."""
    log.step(f"Destroying existing RDS cluster: {cluster_id}")
    if not _cluster_exists(region, cluster_id):
        log.info("Cluster does not exist — nothing to destroy")
        return

    status_data = run_json(
        [
            "aws",
            "rds",
            "describe-db-clusters",
            "--region",
            region,
            "--db-cluster-identifier",
            cluster_id,
        ],
        retries=3,
    )
    status = (status_data.get("DBClusters") or [{}])[0].get("Status", "unknown")
    log.info(f"Current cluster status: {status}")

    instances = _list_cluster_instances(region, cluster_id)
    for instance in instances:
        log.info(f"Deleting instance: {instance}")
        run(
            [
                "aws",
                "rds",
                "delete-db-instance",
                "--region",
                region,
                "--db-instance-identifier",
                instance,
                "--skip-final-snapshot",
            ],
            retries=3,
        )
    for instance in instances:
        wait.wait_for_resource(
            "db-instance",
            instance,
            "deleted",
            region,
            max_wait_seconds=config.DB_INSTANCE_DELETE_TIMEOUT,
            check_interval=config.STATUS_CHECK_INTERVAL,
        )

    clusters = status_data.get("DBClusters") or [{}]
    if clusters[0].get("DeletionProtection"):
        log.warning("Disabling deletion protection")
        run(
            [
                "aws",
                "rds",
                "modify-db-cluster",
                "--region",
                region,
                "--db-cluster-identifier",
                cluster_id,
                "--no-deletion-protection",
            ],
            retries=3,
        )
        wait.wait_for_resource(
            "db-cluster",
            cluster_id,
            "available",
            region,
            max_wait_seconds=300,
            check_interval=config.STATUS_CHECK_INTERVAL,
        )

    run(
        [
            "aws",
            "rds",
            "delete-db-cluster",
            "--region",
            region,
            "--db-cluster-identifier",
            cluster_id,
            "--skip-final-snapshot",
        ],
        retries=3,
    )
    wait.wait_for_resource(
        "db-cluster",
        cluster_id,
        "deleted",
        region,
        max_wait_seconds=config.DB_CLUSTER_WAIT_TIMEOUT,
        check_interval=config.STATUS_CHECK_INTERVAL,
    )
    log.success("Existing cluster destroyed")


def _snapshot_details(region: str, snapshot_id: str) -> dict[str, str | int]:
    data = run_json(
        [
            "aws",
            "rds",
            "describe-db-cluster-snapshots",
            "--region",
            region,
            "--db-cluster-snapshot-identifier",
            snapshot_id,
        ],
        retries=3,
    )
    snap = (data.get("DBClusterSnapshots") or [{}])[0]
    engine = str(snap.get("Engine") or "aurora-mysql")
    port = snap.get("Port") or 3306
    if port in (0, "0"):
        port = 3306
    return {"engine": engine, "port": int(port)}


def restore_cluster_from_snapshot(
    region: str,
    cluster_id: str,
    snapshot_id: str,
    *,
    custom_kms_key: str = "",
) -> None:
    """Restore Aurora cluster from snapshot, apply scaling, create instances."""
    kms.recover_snapshot_kms_key(region, snapshot_id)
    destroy_existing_cluster(region, cluster_id)

    details = _snapshot_details(region, snapshot_id)
    engine = details["engine"]
    port = details["port"]
    subnet_group = terraform_output("aurora_db_subnet_group_name")
    engine_version = terraform_output("aurora_engine_version") or "8.0.mysql_aurora.3.12.0"
    sg_id = terraform_data.rds_security_group_id()

    log.info(f"Restoring cluster {cluster_id} from {snapshot_id}")
    cmd = [
        "aws",
        "rds",
        "restore-db-cluster-from-snapshot",
        "--region",
        region,
        "--db-cluster-identifier",
        cluster_id,
        "--snapshot-identifier",
        snapshot_id,
        "--engine",
        str(engine),
        "--engine-version",
        engine_version,
        "--port",
        str(port),
    ]
    if subnet_group:
        cmd.extend(["--db-subnet-group-name", subnet_group])
    if sg_id:
        cmd.extend(["--vpc-security-group-ids", sg_id])
    if custom_kms_key:
        cmd.extend(["--kms-key-id", custom_kms_key])
    run(cmd, retries=2)

    wait.wait_for_resource(
        "db-cluster",
        cluster_id,
        "available",
        region,
        max_wait_seconds=config.DB_CLUSTER_WAIT_TIMEOUT,
        check_interval=config.STATUS_CHECK_INTERVAL,
    )

    min_cap, max_cap = terraform_data.rds_scaling_config()
    log.info(f"Applying serverless scaling: min={min_cap}, max={max_cap}")
    run(
        [
            "aws",
            "rds",
            "modify-db-cluster",
            "--region",
            region,
            "--db-cluster-identifier",
            cluster_id,
            "--serverless-v2-scaling-configuration",
            f"MinCapacity={min_cap},MaxCapacity={max_cap}",
        ],
        retries=3,
    )

    cluster_name = terraform_output("cluster_name") or "openemr-eks"
    instance_count = terraform_data.rds_instance_count()
    log.info(f"Creating {instance_count} db.serverless instances")
    for index in range(instance_count):
        instance_id = f"{cluster_name}-aurora-{index}"
        run(
            [
                "aws",
                "rds",
                "create-db-instance",
                "--region",
                region,
                "--db-instance-identifier",
                instance_id,
                "--db-cluster-identifier",
                cluster_id,
                "--db-instance-class",
                "db.serverless",
                "--engine",
                str(engine),
            ],
            retries=3,
        )
        wait.wait_for_resource(
            "db-instance",
            instance_id,
            "available",
            region,
            max_wait_seconds=config.DB_CLUSTER_WAIT_TIMEOUT,
            check_interval=config.STATUS_CHECK_INTERVAL,
        )

    reset_master_password(region, cluster_id)
    log.success("RDS cluster restored from snapshot")


def restore_via_aws_backup(
    region: str,
    cluster_id: str,
    snapshot_id: str,
) -> None:
    """Restore RDS using AWS Backup recovery point matching snapshot_id."""
    vault_name = terraform_output("backup_vault_name")
    role_arn = terraform_output("backup_iam_role_arn")
    subnet_group = terraform_output("aurora_db_subnet_group_name")
    sg_id = terraform_data.rds_security_group_id()

    if not vault_name or not role_arn:
        log.warning("AWS Backup vault/role missing — falling back to direct snapshot restore")
        restore_cluster_from_snapshot(region, cluster_id, snapshot_id)
        return

    destroy_existing_cluster(region, cluster_id)
    recovery_point = aws_backup.find_recovery_point_for_snapshot(vault_name, snapshot_id, region)
    if not recovery_point:
        raise DrError(f"No AWS Backup recovery point for snapshot {snapshot_id}")
    job_id = aws_backup.start_rds_restore_job(
        recovery_point,
        cluster_id,
        region,
        role_arn,
        subnet_group,
        [sg_id] if sg_id else [],
    )
    aws_backup.wait_for_restore_job(job_id, region)
    reset_master_password(region, cluster_id)
    log.success("RDS restored via AWS Backup")


def reset_master_password(region: str, cluster_id: str) -> None:
    """Align RDS master password with Terraform state."""
    password = terraform_output("aurora_password")
    if not password:
        raise DrError("Could not read aurora_password from Terraform")
    log.step(f"Resetting master password for {cluster_id}")
    for attempt in range(1, config.PASSWORD_RESET_MAX_ATTEMPTS + 1):
        log.info(f"Password reset attempt {attempt}/{config.PASSWORD_RESET_MAX_ATTEMPTS}")
        result = run(
            [
                "aws",
                "rds",
                "modify-db-cluster",
                "--region",
                region,
                "--db-cluster-identifier",
                cluster_id,
                "--master-user-password",
                password,
                "--apply-immediately",
            ],
            check=False,
            retries=1,
        )
        if result.returncode == 0:
            log.success("Master password reset")
            return
        if attempt < config.PASSWORD_RESET_MAX_ATTEMPTS:
            time.sleep(config.PASSWORD_RESET_RETRY_DELAY)
    raise DrError("Failed to reset RDS master password")


def cluster_endpoint(region: str, cluster_id: str) -> str:
    """Read Aurora cluster endpoint from AWS (used when Terraform skip_rds_creation is active)."""
    data = run_json(
        [
            "aws",
            "rds",
            "describe-db-clusters",
            "--region",
            region,
            "--db-cluster-identifier",
            cluster_id,
        ],
        retries=3,
    )
    endpoint = (data.get("DBClusters") or [{}])[0].get("Endpoint") or ""
    return str(endpoint).strip()


def resolve_db_credentials(region: str, cluster_id: str = "") -> tuple[str, str]:
    """Resolve DB endpoint and password after snapshot restore.

    When E2E step 7 applies skip_rds_creation=true, Terraform outputs aurora_endpoint as
    pending-restore even though the cluster exists in AWS after the RDS restore phase.
    """
    resolved_cluster = cluster_id or terraform_output("aurora_cluster_id")
    db_pass = terraform_output("aurora_password").strip().strip("%").strip()
    db_endpoint = terraform_output("aurora_endpoint").strip().strip("%").strip()

    if not db_endpoint or db_endpoint == "pending-restore":
        if not resolved_cluster:
            raise DrError("Could not resolve aurora_cluster_id for DB endpoint lookup")
        log.info(f"Terraform aurora_endpoint unavailable — reading AWS endpoint for {resolved_cluster}")
        db_endpoint = cluster_endpoint(region, resolved_cluster)

    if not db_endpoint:
        raise DrError("Database endpoint not available after RDS restore")
    if not db_pass:
        raise DrError("Database password not available from Terraform state")
    return db_endpoint, db_pass
