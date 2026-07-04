"""Parse Terraform state for restore operations."""

from __future__ import annotations

import json
from typing import Any, cast

from openemr_dr.common.paths import TERRAFORM_DIR
from openemr_dr.common.shell import run


def load_state() -> dict[str, Any]:
    result = run(["terraform", "show", "-json"], cwd=str(TERRAFORM_DIR), capture=True, retries=3)
    return cast(dict[str, Any], json.loads(result.stdout or "{}"))


def _root_resources(state: dict[str, Any]) -> list[dict[str, Any]]:
    return list(state.get("values", {}).get("root_module", {}).get("resources") or [])


def resource_values(state: dict[str, Any], resource_type: str, name: str) -> dict[str, Any]:
    for resource in _root_resources(state):
        if resource.get("type") == resource_type and resource.get("name") == name:
            values = resource.get("values")
            if isinstance(values, dict):
                return values
    return {}


def rds_security_group_id(state: dict[str, Any] | None = None) -> str:
    st = state if state is not None else load_state()
    return str(resource_values(st, "aws_security_group", "rds").get("id") or "")


def rds_scaling_config(state: dict[str, Any] | None = None) -> tuple[float, float]:
    st = state if state is not None else load_state()
    cluster = resource_values(st, "aws_rds_cluster", "openemr")
    scaling = cluster.get("serverlessv2_scaling_configuration") or cluster.get(
        "serverless_v2_scaling_configuration"
    )
    if isinstance(scaling, list) and scaling:
        scaling = scaling[0]
    if not isinstance(scaling, dict):
        return 0.5, 16.0
    min_cap = scaling.get("min_capacity", 0.5)
    max_cap = scaling.get("max_capacity", 16.0)
    try:
        return float(min_cap), float(max_cap)
    except (TypeError, ValueError):
        return 0.5, 16.0


def rds_instance_count(state: dict[str, Any] | None = None) -> int:
    st = state if state is not None else load_state()
    count = sum(
        1
        for resource in _root_resources(st)
        if resource.get("type") == "aws_rds_cluster_instance" and resource.get("name") == "openemr"
    )
    return count if count > 0 else 2
