"""Tests for aws.terraform_data."""

from __future__ import annotations

from openemr_dr.aws import terraform_data

SAMPLE_STATE = {
    "values": {
        "root_module": {
            "resources": [
                {
                    "type": "aws_security_group",
                    "name": "rds",
                    "values": {"id": "sg-abc"},
                },
                {
                    "type": "aws_rds_cluster",
                    "name": "openemr",
                    "values": {
                        "serverlessv2_scaling_configuration": [
                            {"min_capacity": 1, "max_capacity": 8}
                        ]
                    },
                },
                {"type": "aws_rds_cluster_instance", "name": "openemr", "values": {}},
                {"type": "aws_rds_cluster_instance", "name": "openemr", "values": {}},
            ]
        }
    }
}


def test_rds_security_group_id() -> None:
    assert terraform_data.rds_security_group_id(SAMPLE_STATE) == "sg-abc"


def test_rds_scaling_config() -> None:
    assert terraform_data.rds_scaling_config(SAMPLE_STATE) == (1.0, 8.0)


def test_rds_instance_count() -> None:
    assert terraform_data.rds_instance_count(SAMPLE_STATE) == 2


def test_resource_values_missing() -> None:
    assert terraform_data.resource_values({}, "aws_vpc", "main") == {}
