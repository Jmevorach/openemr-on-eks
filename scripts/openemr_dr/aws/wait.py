"""Poll AWS resources until they reach an expected status."""

from __future__ import annotations

import time
from typing import Literal

from openemr_dr.common import log
from openemr_dr.common.shell import run, run_json
from openemr_dr.errors import DrError

ResourceType = Literal["db-cluster", "db-instance", "snapshot"]


def _cluster_status(region: str, resource_id: str, *, deleted: bool) -> str:
    if deleted:
        probe = run(
            [
                "aws",
                "rds",
                "describe-db-clusters",
                "--region",
                region,
                "--db-cluster-identifier",
                resource_id,
            ],
            capture=True,
            check=False,
        )
        return "deleting" if probe.returncode == 0 else "deleted"
    data = run_json(
        [
            "aws",
            "rds",
            "describe-db-clusters",
            "--region",
            region,
            "--db-cluster-identifier",
            resource_id,
        ],
        check=False,
        retries=2,
    )
    clusters = data.get("DBClusters") or []
    if not clusters:
        return "unknown"
    return str(clusters[0].get("Status", "unknown"))


def _instance_status(region: str, resource_id: str, *, deleted: bool) -> str:
    if deleted:
        probe = run(
            [
                "aws",
                "rds",
                "describe-db-instances",
                "--region",
                region,
                "--db-instance-identifier",
                resource_id,
            ],
            capture=True,
            check=False,
        )
        return "deleting" if probe.returncode == 0 else "deleted"
    data = run_json(
        [
            "aws",
            "rds",
            "describe-db-instances",
            "--region",
            region,
            "--db-instance-identifier",
            resource_id,
        ],
        check=False,
        retries=2,
    )
    instances = data.get("DBInstances") or []
    if not instances:
        return "unknown"
    return str(instances[0].get("DBInstanceStatus", "unknown"))


def _snapshot_status(region: str, resource_id: str) -> str:
    data = run_json(
        [
            "aws",
            "rds",
            "describe-db-cluster-snapshots",
            "--region",
            region,
            "--db-cluster-snapshot-identifier",
            resource_id,
        ],
        check=False,
        retries=2,
    )
    snaps = data.get("DBClusterSnapshots") or []
    if not snaps:
        return "unknown"
    return str(snaps[0].get("Status", "unknown"))


def current_status(
    resource_type: ResourceType,
    resource_id: str,
    region: str,
    *,
    expect_deleted: bool = False,
) -> str:
    if resource_type == "db-cluster":
        return _cluster_status(region, resource_id, deleted=expect_deleted)
    if resource_type == "db-instance":
        return _instance_status(region, resource_id, deleted=expect_deleted)
    if resource_type == "snapshot":
        return _snapshot_status(region, resource_id)
    raise DrError(f"Unknown resource type: {resource_type}")


def wait_for_resource(
    resource_type: ResourceType,
    resource_id: str,
    expected_status: str,
    region: str,
    *,
    max_wait_seconds: int = 600,
    check_interval: int = 30,
) -> None:
    log.info(f"Waiting for {resource_type} '{resource_id}' → {expected_status}")
    elapsed = 0
    last = ""
    expect_deleted = expected_status == "deleted"
    while elapsed < max_wait_seconds:
        status = current_status(resource_type, resource_id, region, expect_deleted=expect_deleted)
        if status == expected_status:
            log.success(f"{resource_type} '{resource_id}' reached {expected_status}")
            return
        if status != last:
            log.info(f"  status: {status}")
            last = status
        time.sleep(check_interval)
        elapsed += check_interval
    raise DrError(
        f"Timeout waiting for {resource_type} '{resource_id}' "
        f"(expected {expected_status}, last={last})"
    )
