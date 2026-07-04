"""Tests for restore orchestrator."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from openemr_dr.models.restore import RestoreContext
from openemr_dr.restore.orchestrator import run_restore


class TestRunRestore(unittest.TestCase):
    @patch("openemr_dr.restore.orchestrator.run_phase")
    def test_runs_all_phases(self, mock_phase: MagicMock) -> None:
        ctx = RestoreContext(backup_bucket="b", snapshot_id="s")
        with tempfile.TemporaryDirectory() as tmp:
            sf = Path(tmp) / ".restore-state"
            run_restore(ctx, state_file=str(sf))
        self.assertEqual(mock_phase.call_count, 6)
        self.assertFalse(sf.exists())

    @patch("openemr_dr.restore.orchestrator.run_phase")
    def test_single_phase_only(self, mock_phase: MagicMock) -> None:
        ctx = RestoreContext(backup_bucket="b", snapshot_id="s", dry_run=True)
        with tempfile.TemporaryDirectory() as tmp:
            run_restore(ctx, state_file=str(Path(tmp) / ".restore-state"), single_phase="preflight")
        mock_phase.assert_called_once_with("preflight", ctx)

    @patch("openemr_dr.restore.orchestrator.run_phase")
    @patch("openemr_dr.restore.orchestrator.rds_ops._cluster_exists", return_value=False)
    @patch("openemr_dr.restore.orchestrator.terraform_output", return_value="openemr-eks-test-aurora-abc")
    def test_invalidates_stale_rds_checkpoint(
        self,
        _tf: MagicMock,
        _exists: MagicMock,
        mock_phase: MagicMock,
    ) -> None:
        ctx = RestoreContext(backup_bucket="b", snapshot_id="s", aws_region="us-west-2")
        with tempfile.TemporaryDirectory() as tmp:
            sf = Path(tmp) / ".restore-state"
            sf.write_text("COMPLETED_PHASE=rds\nBACKUP_BUCKET=b\nSNAPSHOT_ID=s\n", encoding="utf-8")
            run_restore(ctx, state_file=str(sf))
        phases_run = [call.args[0] for call in mock_phase.call_args_list]
        self.assertIn("rds", phases_run)
        self.assertNotIn("preflight", phases_run)


class TestE2ERunner(unittest.TestCase):
    def test_step_groups_inplace_skips_destroy(self) -> None:
        from openemr_dr.e2e.runner import STEP_GROUPS

        f, t, skip = STEP_GROUPS["backup-restore-inplace"]
        self.assertEqual((f, t), (4, 9))
        self.assertIn("5", skip)
        self.assertIn("6", skip)
        self.assertIn("7", skip)


if __name__ == "__main__":
    unittest.main()
