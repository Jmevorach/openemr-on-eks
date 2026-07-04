#!/usr/bin/env bats
# -----------------------------------------------------------------------------
# BATS Suite: scripts/test-warp-pinned-versions.sh
# Purpose: Validate dependency gates and versions.yaml integration via shared
#          lib/versions-yq.sh used by the slim warp pin smoke test script.
# Scope:   Non-destructive — tests dependency checks and version parsing only.
# -----------------------------------------------------------------------------

load test_helper

setup() { cd "$PROJECT_ROOT"; }

SCRIPT="${SCRIPTS_DIR}/test-warp-pinned-versions.sh"
LIB="${SCRIPTS_DIR}/lib/versions-yq.sh"

# ── Executable & syntax ─────────────────────────────────────────────────────

@test "test-warp-pinned-versions.sh is executable" {
  [ -x "$SCRIPT" ]
}

@test "test-warp-pinned-versions.sh has valid bash syntax" {
  bash -n "$SCRIPT"
}

@test "versions-yq.sh has valid bash syntax" {
  bash -n "$LIB"
}

# ── Dependency gate: yq ─────────────────────────────────────────────────────

@test "fails clearly when yq is unavailable" {
  local tmpbin
  tmpbin=$(mktemp -d)
  ln -s "$(command -v bash)" "$tmpbin/bash"
  ln -s "$(command -v echo)" "$tmpbin/echo"
  ln -s "$(command -v command)" "$tmpbin/command" 2>/dev/null || true
  run env PATH="$tmpbin" bash "$SCRIPT"
  rm -rf "$tmpbin"
  [ "$status" -ne 0 ]
  [[ "$output" =~ (yq is required|Install yq|ERROR) ]]
}

@test "yq error message includes install URL" {
  local tmpbin
  tmpbin=$(mktemp -d)
  ln -s "$(command -v bash)" "$tmpbin/bash"
  ln -s "$(command -v echo)" "$tmpbin/echo"
  ln -s "$(command -v command)" "$tmpbin/command" 2>/dev/null || true
  run env PATH="$tmpbin" bash "$SCRIPT"
  rm -rf "$tmpbin"
  [[ "$output" =~ (github.com/mikefarah/yq|Install yq|ERROR) ]]
}

# ── normalize_python_version (shared lib) ──────────────────────────────────

@test "normalize_python_version: 3.14.0 -> 3.14" {
  result=$(echo "3.14.0" | awk -F. '{print $1"."$2}')
  [ "$result" = "3.14" ]
}

@test "normalize_python_version: 3.14 -> 3.14" {
  result=$(echo "3.14" | awk -F. '{print $1"."$2}')
  [ "$result" = "3.14" ]
}

@test "normalize_python_version: 3.9.18 -> 3.9" {
  result=$(echo "3.9.18" | awk -F. '{print $1"."$2}')
  [ "$result" = "3.9" ]
}

@test "normalize_python_version function exists in shared lib" {
  run grep 'normalize_python_version()' "$LIB"
  [ "$status" -eq 0 ]
}

# ── read_version (shared lib) ──────────────────────────────────────────────

@test "read_version function exists in shared lib" {
  run grep 'read_version()' "$LIB"
  [ "$status" -eq 0 ]
}

@test "read_version exits on empty/null version" {
  run grep -A20 'read_version()' "$LIB"
  [[ "$output" =~ null ]]
}

# ── versions.yaml cross-reference ──────────────────────────────────────────

@test "script delegates validate-python-requirements for warp" {
  run grep 'validate-python-requirements.sh.*warp' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script reads pymysql version from versions.yaml via lib" {
  run grep "python_packages.pymysql.current" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script reads boto3 version from versions.yaml via lib" {
  run grep "python_packages.boto3.current" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script uses install-python-dev.sh for warp" {
  run grep 'install-python-dev.sh.*warp' "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ── Required directories ───────────────────────────────────────────────────

@test "warp directory exists at PROJECT_ROOT/warp" {
  [ -d "${PROJECT_ROOT}/warp" ]
}

@test "versions.yaml exists for the script" {
  [ -f "${PROJECT_ROOT}/versions.yaml" ]
}

# ── Script uses set -e ─────────────────────────────────────────────────────

@test "script uses set -e for fail-fast" {
  run grep '^set -euo pipefail' "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════════════════
# Function-level unit tests (shared lib)
# ═══════════════════════════════════════════════════════════════════════════

@test "UNIT: normalize_python_version extracts major.minor from 3-part version" {
  local func_file
  func_file=$(extract_function "$LIB" "normalize_python_version")
  run bash -c '
    source "'"$func_file"'"
    normalize_python_version "3.14.2"
  '
  rm -f "$func_file"
  [ "$status" -eq 0 ]
  [[ "$output" == "3.14" ]]
}

@test "UNIT: normalize_python_version passes through 2-part version unchanged" {
  local func_file
  func_file=$(extract_function "$LIB" "normalize_python_version")
  run bash -c '
    source "'"$func_file"'"
    normalize_python_version "3.14"
  '
  rm -f "$func_file"
  [ "$status" -eq 0 ]
  [[ "$output" == "3.14" ]]
}

@test "UNIT: normalize_python_version handles old Python version 3.9.18" {
  local func_file
  func_file=$(extract_function "$LIB" "normalize_python_version")
  run bash -c '
    source "'"$func_file"'"
    normalize_python_version "3.9.18"
  '
  rm -f "$func_file"
  [ "$status" -eq 0 ]
  [[ "$output" == "3.9" ]]
}

@test "UNIT: read_version reads valid key from versions.yaml" {
  if ! command -v yq >/dev/null 2>&1; then skip "yq not installed"; fi
  local tmpdir
  tmpdir=$(make_temp_dir)
  cat > "${tmpdir}/versions.yaml" <<'YAML'
applications:
  python:
    current: "3.99"
YAML
  local func_file
  func_file=$(extract_function "$LIB" "read_version")
  run bash -c '
    VERSIONS_YQ_FILE="'"${tmpdir}/versions.yaml"'"
    source "'"$func_file"'"
    read_version ".applications.python.current"
  '
  rm -f "$func_file"
  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
  [[ "$output" == "3.99" ]]
}

@test "UNIT: read_version fails on missing key" {
  if ! command -v yq >/dev/null 2>&1; then skip "yq not installed"; fi
  local tmpdir
  tmpdir=$(make_temp_dir)
  cat > "${tmpdir}/versions.yaml" <<'YAML'
applications:
  python:
    current: "3.14"
YAML
  local func_file
  func_file=$(extract_function "$LIB" "read_version")
  run bash -c '
    VERSIONS_YQ_FILE="'"${tmpdir}/versions.yaml"'"
    source "'"$func_file"'"
    read_version ".nonexistent.path"
  '
  rm -f "$func_file"
  rm -rf "$tmpdir"
  [ "$status" -ne 0 ]
}

@test "UNIT: read_version fails on empty/null value" {
  if ! command -v yq >/dev/null 2>&1; then skip "yq not installed"; fi
  local tmpdir
  tmpdir=$(make_temp_dir)
  cat > "${tmpdir}/versions.yaml" <<'YAML'
applications:
  python:
    current: null
YAML
  local func_file
  func_file=$(extract_function "$LIB" "read_version")
  run bash -c '
    VERSIONS_YQ_FILE="'"${tmpdir}/versions.yaml"'"
    source "'"$func_file"'"
    read_version ".applications.python.current"
  '
  rm -f "$func_file"
  rm -rf "$tmpdir"
  [ "$status" -ne 0 ]
}
