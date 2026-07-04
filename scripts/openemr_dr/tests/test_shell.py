"""Tests for shell helpers."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from openemr_dr.common.shell import run, run_json, terraform_output
from openemr_dr.errors import DrError


def test_run_success() -> None:
    with patch("openemr_dr.common.shell.subprocess.run") as mock_sub:
        mock_sub.return_value = MagicMock(returncode=0, stdout="ok", stderr="")
        result = run(["echo", "hi"], capture=True)
        assert result.returncode == 0


def test_run_raises_dr_error() -> None:
    with patch("openemr_dr.common.shell.subprocess.run") as mock_sub:
        mock_sub.return_value = MagicMock(returncode=1, stdout="", stderr="fail")
        with pytest.raises(DrError):
            run(["false"], retries=1)


def test_run_json_parses() -> None:
    with patch("openemr_dr.common.shell.run") as mock_run:
        mock_run.return_value = MagicMock(stdout='{"a": 1}')
        assert run_json(["aws", "sts"]) == {"a": 1}


def test_terraform_output() -> None:
    with patch("openemr_dr.common.shell.run") as mock_run:
        mock_run.return_value = MagicMock(stdout="value\n")
        assert terraform_output("x") == "value"
