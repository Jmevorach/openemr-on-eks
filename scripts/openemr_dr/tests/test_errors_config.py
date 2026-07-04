"""Tests for errors and config."""

from __future__ import annotations

from openemr_dr.config import DB_CLUSTER_WAIT_TIMEOUT, VERIFICATION_MAX_ATTEMPTS
from openemr_dr.errors import DrError, PhaseError, PreflightError


def test_preflight_error_message() -> None:
    err = PreflightError(["RDS snapshot"], "failed")
    assert "RDS snapshot" in str(err)
    assert err.failed_checks == ["RDS snapshot"]


def test_phase_error() -> None:
    err = PhaseError("rds", "boom")
    assert err.phase == "rds"
    assert isinstance(err, DrError)


def test_config_defaults() -> None:
    assert DB_CLUSTER_WAIT_TIMEOUT >= 600
    assert VERIFICATION_MAX_ATTEMPTS >= 1
