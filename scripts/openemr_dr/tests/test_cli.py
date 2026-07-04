"""Tests for CLI entrypoints."""

from __future__ import annotations

from unittest.mock import patch

from openemr_dr.cli import main


def test_main_help() -> None:
    assert main([]) == 1
    assert main(["--help"]) == 0


def test_main_restore_delegates() -> None:
    with patch("openemr_dr.cli.run_restore_cli", return_value=0) as mock_restore:
        assert main(["restore", "b", "s"]) == 0
        mock_restore.assert_called_once()


def test_main_backup_delegates() -> None:
    with patch("openemr_dr.cli.run_backup_cli", return_value=0) as mock_backup:
        assert main(["backup"]) == 0
        mock_backup.assert_called_once()


def test_main_unknown_command() -> None:
    assert main(["nope"]) == 1
