"""Tests for backup orchestrator."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

from openemr_dr.backup.orchestrator import run_backup_cli


def test_backup_cli_runs_bash() -> None:
    with patch("openemr_dr.backup.orchestrator.run") as mock_run:
        mock_run.return_value = MagicMock(returncode=0)
        assert run_backup_cli(["--cluster-name", "test"]) == 0
        args = mock_run.call_args[0][0]
        assert "backup.sh" in args[1]
