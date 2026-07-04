"""E2E runner tests."""

from __future__ import annotations

from unittest.mock import patch

from openemr_dr.e2e.runner import run_e2e_cli


def test_list_steps(capsys) -> None:
    assert run_e2e_cli(["--list-steps"]) == 0
    out = capsys.readouterr().out
    assert "Step 1" in out


def test_list_groups(capsys) -> None:
    assert run_e2e_cli(["--list-groups"]) == 0
    assert "backup-restore-inplace" in capsys.readouterr().out


def test_delegates_to_bash() -> None:
    with patch("openemr_dr.e2e.runner._run_bash_e2e", return_value=0) as mock_bash:
        assert run_e2e_cli(["--group", "backup", "--cluster-name", "c"]) == 0
        args = mock_bash.call_args[0][0]
        assert "--from-step" in args
        assert "4" in args


def test_single_step() -> None:
    with patch("openemr_dr.e2e.runner._run_bash_e2e", return_value=0) as mock_bash:
        run_e2e_cli(["--step", "8"])
        args = mock_bash.call_args[0][0]
        idx = args.index("--from-step")
        assert args[idx + 1] == args[args.index("--to-step") + 1] == "8"
