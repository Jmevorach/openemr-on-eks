# Disaster Recovery — Python Architecture

OpenEMR backup, restore, and E2E testing are migrating from large bash scripts to the **`openemr_dr`** Python package under `scripts/openemr_dr/`. Bash entrypoints remain for compatibility but delegate to Python.

## Why Python

- **Testable phases** — each restore step has unit tests; no AWS required for most tests
- **Checkpoints** — `.restore-state` with `--from-phase` resume after long failures
- **Manifest v2** — typed restore plans from backup metadata
- **Single orchestrator** — one code path for CLI, E2E step 8, and future automation

## Package layout

```
scripts/openemr_dr/
  cli.py                 # python -m openemr_dr {restore|backup|e2e}
  common/                # shell helpers, paths, logging
  aws/                   # RDS, KMS, wait, terraform_data
  models/                # RestoreContext, RestoreState
  backup/                # manifest builder, metadata loader, orchestrator
  restore/
    orchestrator.py      # phased restore runner
    bash_bridge.py       # legacy phase only
    phases/              # all restore phases (native Python)
  e2e/runner.py          # E2E driver (delegates to bash E2E today)
  tests/                 # pytest suite (91%+ coverage)
  pyproject.toml         # ruff, mypy strict, bandit, pytest-cov 90%
```

## Restore flow (default — inverted)

| Phase | Implementation | What it does |
|-------|----------------|--------------|
| `preflight` | Python | Validate bucket, snapshot, Terraform state |
| `bootstrap` | Python → `k8s/restore-bootstrap.sh` | Namespace, EFS PVC, IRSA |
| `rds` | Python | Destroy empty cluster, restore from snapshot / AWS Backup |
| `data` | Python | Apply `k8s/jobs/data-restore-job.yaml` |
| `deploy` | Python → shell scripts | `restore-defaults.sh` + `k8s/deploy.sh` |
| `verify` | Python | Health check, crypto cleanup, re-apply HPA |
| `legacy` | Bash bridge | Old restore order only |

## Usage

### Restore

```bash
# Default (Python orchestrator via restore.sh wrapper)
./scripts/restore.sh BACKUP_BUCKET SNAPSHOT_ID --region us-west-2

# From manifest v2
./scripts/restore.sh --from-metadata s3://BUCKET/metadata/backup-metadata-TIMESTAMP.json

# Direct Python CLI
cd scripts && python3 -m openemr_dr restore BACKUP_BUCKET SNAPSHOT_ID --region us-west-2

# Single phase (for debugging)
python3 -m openemr_dr restore BUCKET SNAP --phase preflight --dry-run

# Resume after failure
python3 -m openemr_dr restore BUCKET SNAP --from-phase data --state-file .restore-state

# Legacy order (old clean→deploy→RDS→data)
python3 -m openemr_dr restore BUCKET SNAP --legacy-order --bash-only
```

### E2E tests

```bash
# Python driver (wraps bash E2E script; same behavior today)
cd scripts && python3 -m openemr_dr e2e --group full --cluster-name openemr-eks-test

# Fast in-place restore tier (~45–60 min after steps 1–3)
python3 -m openemr_dr e2e --group backup-restore-inplace

# List steps / groups
python3 -m openemr_dr e2e --list-steps
python3 -m openemr_dr e2e --list-groups
```

### Unit tests and CI (no AWS)

**Dependency model:** `versions.yaml` is the source of truth. Pinned lockfiles live in `scripts/requirements/`. CI installs via `scripts/install-python-dev.sh`.

```bash
./scripts/validate-python-requirements.sh openemr_dr   # pins match versions.yaml
./scripts/test-openemr-dr-pinned-versions.sh           # install + import smoke test
./scripts/run-dr-tests.sh                              # full gate: ruff, mypy, bandit, pytest ≥90%
# equivalent:
./scripts/ci/run-python-ci.sh openemr_dr
```

CI jobs **`openemr-dr-ci`**, **`warp-ci`**, and **`credential-rotation-ci`** use path filters (`dorny/paths-filter`) so they only run when relevant files change. All three share `scripts/ci/run-python-ci.sh` and `scripts/install-python-dev.sh`. A dedicated **`python-requirements-validate`** job runs when `versions.yaml` or `scripts/requirements/` change.

Shared libraries: `scripts/lib/versions-yq.sh`, `scripts/lib/python-venv.sh`.

Project profiles are declared in `versions.yaml` under **`python_projects`**.

```bash
# Or via main test suite
./scripts/run-test-suite.sh -s script_validation
```

### Backup

```bash
cd scripts && python3 -m openemr_dr backup --cluster-name openemr-eks-test
```

## Migration roadmap

Phases marked **native** are implemented in Python. Others use **bash bridge** (`RESTORE_INTERNAL=1 restore.sh --bash-only`) until ported.

| Component | Status | Next step |
|-----------|--------|-----------|
| Restore phases (preflight→verify) | Native Python | — |
| backup.sh AWS operations | Bash (via `openemr_dr backup`) | Port snapshot/S3/k8s export to Python |
| E2E steps 1–10 | Bash (via runner) | Port one step at a time to `openemr_dr/e2e/steps/` |
| destroy.sh / deploy.sh | Bash subprocess targets | Keep until lower-level APIs exist |

### How to port a phase

1. Add `openemr_dr/restore/phases/<name>.py` with `run(ctx: RestoreContext) -> None`
2. Register in `restore/phases/__init__.py` → `NATIVE`
3. Add tests in `openemr_dr/tests/`
4. Run `./scripts/run-dr-tests.sh`
5. Validate with `--phase <name>` against a dev cluster
6. Remove from `BASH_BRIDGE`

## Terraform restore mode

E2E step 7 applies `-var=skip_rds_creation=true` so RDS is created from snapshot in step 8, not as an empty cluster.

## Related docs

- [Backup & Restore Guide](BACKUP_RESTORE_GUIDE.md)
- [Testing Guide](TESTING_GUIDE.md)
- [End-to-End Testing Requirements](END_TO_END_TESTING_REQUIREMENTS.md)
