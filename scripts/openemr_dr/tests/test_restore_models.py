"""Tests for RestoreContext."""

from __future__ import annotations

import pytest

from openemr_dr.models.restore import RestoreContext


def test_resolve_app_data_key_explicit() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="s", app_data_key="application-data/x.tar.gz")
    assert ctx.resolve_app_data_key() == "application-data/x.tar.gz"


def test_resolve_app_data_key_from_snapshot() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="cluster-backup-20260702-120000")
    assert "20260702-120000" in ctx.resolve_app_data_key()


def test_resolve_app_data_key_failure() -> None:
    ctx = RestoreContext(backup_bucket="b", snapshot_id="no-timestamp")
    with pytest.raises(ValueError):
        ctx.resolve_app_data_key()
