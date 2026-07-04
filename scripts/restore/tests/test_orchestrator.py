"""Unit tests for restore orchestrator."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import orchestrator  # noqa: E402
from state import RestoreState  # noqa: E402


class TestOrchestratorHelpers(unittest.TestCase):
    def test_phase_sequence_default(self) -> None:
        state = RestoreState()
        self.assertEqual(
            orchestrator._phase_sequence(state),
            ["preflight", "bootstrap", "rds", "data", "deploy", "verify"],
        )

    def test_phase_sequence_legacy(self) -> None:
        state = RestoreState(legacy_order=True)
        self.assertEqual(orchestrator._phase_sequence(state), ["preflight", "legacy", "verify"])

    def test_list_phases_exits_zero(self) -> None:
        self.assertEqual(orchestrator.main(["--list-phases"]), 0)

    def test_missing_args_returns_error(self) -> None:
        self.assertEqual(orchestrator.main([]), 1)

    @patch.object(orchestrator, "_run_phase")
    def test_runs_phases_in_order(self, mock_run: MagicMock) -> None:
        code = orchestrator.main(["my-bucket", "my-snapshot", "--region", "us-west-2"])
        self.assertEqual(code, 0)
        called_phases = [call.args[1] for call in mock_run.call_args_list]
        self.assertEqual(called_phases, ["preflight", "bootstrap", "rds", "data", "deploy", "verify"])

    @patch.object(orchestrator, "_run_phase")
    def test_from_phase_skips_completed(self, mock_run: MagicMock) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_file = Path(tmp) / ".restore-state"
            state_file.write_text(
                "COMPLETED_PHASE=rds\nBACKUP_BUCKET=b\nSNAPSHOT_ID=s\nAPP_DATA_KEY=\n"
                "METADATA_URI=\nAWS_REGION=us-west-2\nUSE_AWS_BACKUP=false\nLEGACY_ORDER=false\n",
                encoding="utf-8",
            )
            code = orchestrator.main(
                ["my-bucket", "my-snapshot", "--from-phase", "data", "--state-file", str(state_file)]
            )
        self.assertEqual(code, 0)
        called_phases = [call.args[1] for call in mock_run.call_args_list]
        self.assertEqual(called_phases, ["data", "deploy", "verify"])

    @patch.object(orchestrator, "subprocess")
    @patch.object(orchestrator, "_run_phase")
    def test_legacy_order_runs_bash_legacy(self, mock_run: MagicMock, mock_subprocess: MagicMock) -> None:
        mock_subprocess.run.return_value = MagicMock(returncode=0)
        code = orchestrator.main(["my-bucket", "my-snapshot", "--legacy-order"])
        self.assertEqual(code, 0)
        mock_run.assert_called_once_with(unittest.mock.ANY, "preflight")
        self.assertTrue(mock_subprocess.run.called)


if __name__ == "__main__":
    unittest.main()
