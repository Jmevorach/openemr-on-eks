"""Unit tests for restore checkpoint state."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from state import PHASES, RestoreState  # noqa: E402


class TestRestoreState(unittest.TestCase):
    def test_phases_order(self) -> None:
        self.assertEqual(PHASES, ("preflight", "bootstrap", "rds", "data", "deploy", "verify"))

    def test_save_and_load_roundtrip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_file = Path(tmp) / ".restore-state"
            state = RestoreState(
                backup_bucket="bucket-x",
                snapshot_id="snap-y",
                app_data_key="application-data/app.tar.gz",
                metadata_uri="s3://bucket/metadata/meta.json",
                aws_region="us-east-1",
                use_aws_backup=True,
                legacy_order=False,
            )
            state.set_path(str(state_file))
            state.mark_complete("bootstrap")

            loaded = RestoreState()
            loaded.set_path(str(state_file))
            loaded.load(str(state_file))

            self.assertEqual(loaded.completed_phase, "bootstrap")
            self.assertEqual(loaded.backup_bucket, "bucket-x")
            self.assertEqual(loaded.snapshot_id, "snap-y")
            self.assertEqual(loaded.app_data_key, "application-data/app.tar.gz")
            self.assertEqual(loaded.metadata_uri, "s3://bucket/metadata/meta.json")
            self.assertEqual(loaded.aws_region, "us-east-1")
            self.assertTrue(loaded.use_aws_backup)
            self.assertFalse(loaded.legacy_order)

    def test_should_run_after_checkpoint(self) -> None:
        state = RestoreState()
        state.completed_phase = "rds"
        self.assertFalse(state.should_run("preflight", None))
        self.assertFalse(state.should_run("rds", None))
        self.assertTrue(state.should_run("data", None))
        self.assertTrue(state.should_run("deploy", None))

    def test_should_run_from_phase_overrides_checkpoint(self) -> None:
        state = RestoreState()
        state.completed_phase = "deploy"
        self.assertFalse(state.should_run("preflight", "data"))
        self.assertFalse(state.should_run("bootstrap", "data"))
        self.assertFalse(state.should_run("rds", "data"))
        self.assertTrue(state.should_run("data", "data"))
        self.assertTrue(state.should_run("verify", "data"))

    def test_should_run_fresh_state_runs_all(self) -> None:
        state = RestoreState()
        for phase in PHASES:
            self.assertTrue(state.should_run(phase, None))

    def test_unknown_completed_phase_runs_next(self) -> None:
        state = RestoreState()
        state.completed_phase = "unknown-phase"
        self.assertTrue(state.should_run("preflight", None))


if __name__ == "__main__":
    unittest.main()
