#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_active_readiness_snapshot_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_active_readiness_snapshot_${STAMP}.txt"
STATIC_LOG="${RESULT_DIR}/static_checks_${STAMP}.log"

mkdir -p "${RESULT_DIR}"

fail() {
  echo "FAIL: $*" | tee -a "${SUMMARY_FILE}" >&2
  exit 1
}

pass() {
  echo "PASS: $*" | tee -a "${SUMMARY_FILE}"
}

REQUIRED_FILES=(
  "docs/25_cable_active_control_review_package.md"
  "docs/26_cable_single_vehicle_active_scenario.md"
  "docs/10_evidence_inventory.md"
  "data/results/cable_offboard_gate_rviz_overlay_20260617_171815/cable_offboard_gate_rviz_overlay_20260617_171815.txt"
  "data/screenshots/cable_offboard_gate_dry_run_rviz_overlay_20260617_171815.png"
  "data/results/cable_active_control_review_package_20260617_165225/cable_active_control_review_package_20260617_165225.txt"
  "data/results/cable_single_vehicle_active_scenario_20260617_171327/cable_single_vehicle_active_scenario_20260617_171327.txt"
)

{
  echo "scope=cable_active_readiness_snapshot"
  echo "ready_for_review=true"
  echo "active_control_approved=false"
  echo "phase_b_user_approved=false"
  echo "publishes_fmu_in=false"
} >"${SUMMARY_FILE}"

{
  echo "[check] required files exist"
  for path in "${REQUIRED_FILES[@]}"; do
    [[ -f "${path}" ]] || fail "missing required file: ${path}"
  done
  echo "ok"

  echo "[check] package and scenario freeze markers are present"
  rg -n 'active_control_approved=false|phase_b_user_approved=false|single_vehicle_cable_short_active|publishes_fmu_in=false|20 Hz' \
    docs/25_cable_active_control_review_package.md docs/26_cable_single_vehicle_active_scenario.md \
    >/dev/null || fail "package or scenario markers missing"
  echo "ok"

  echo "[check] refreshed RViz capture is inactive"
  rg -n 'decision=accepted_cable_offboard_gate_rviz_overlay_capture|phase_b_allowed=false|publishes_fmu_in=false' \
    data/results/cable_offboard_gate_rviz_overlay_20260617_171815/cable_offboard_gate_rviz_overlay_20260617_171815.txt >/dev/null \
    || fail "refresh capture not accepted or not inactive"
  echo "ok"

  echo "[check] evidence inventory already references the refresh"
  rg -n 'offboard_gate_rviz_summary_refresh|offboard_gate_rviz_screenshot_refresh' docs/10_evidence_inventory.md scripts/audit_evidence_inventory.sh >/dev/null \
    || fail "inventory does not reference refreshed overlay evidence"
  echo "ok"
} >"${STATIC_LOG}" 2>&1 || {
  cat "${STATIC_LOG}" >&2
  exit 1
}

pass "static readiness snapshot checks accepted"

{
  echo "decision=accepted_cable_active_readiness_snapshot"
  echo "ready_for_review=true"
  echo "active_control_approved=false"
  echo "phase_b_user_approved=false"
  echo "publishes_fmu_in=false"
  echo "static_log=${STATIC_LOG}"
} >>"${SUMMARY_FILE}"

echo "Cable active readiness snapshot completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Static log: ${STATIC_LOG}"
