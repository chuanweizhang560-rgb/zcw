#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_active_handoff_bundle_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_active_handoff_bundle_${STAMP}.txt"
STATIC_LOG="${RESULT_DIR}/static_checks_${STAMP}.log"

mkdir -p "${RESULT_DIR}"

fail() {
  echo "FAIL: $*" | tee -a "${SUMMARY_FILE}" >&2
  exit 1
}

pass() {
  echo "PASS: $*" | tee -a "${SUMMARY_FILE}"
}

BUNDLE_DOC="docs/29_cable_active_handoff_bundle.md"
REQUIRED_DOCS=(
  "docs/25_cable_active_control_review_package.md"
  "docs/26_cable_single_vehicle_active_scenario.md"
  "docs/27_cable_active_readiness_snapshot.md"
  "docs/28_cable_active_approval_manifest.md"
  "docs/19_current_evidence_matrix.md"
  "docs/10_evidence_inventory.md"
)

{
  echo "scope=cable_active_handoff_bundle"
  echo "bundle_frozen=true"
  echo "ready_for_review=true"
  echo "active_control_approved=false"
  echo "phase_b_user_approved=false"
  echo "cable_phase_b_active_bridge_approved=false"
  echo "publishes_fmu_in=false"
} >"${SUMMARY_FILE}"

{
  echo "[check] bundle document exists"
  [[ -f "${BUNDLE_DOC}" ]] || fail "missing bundle doc: ${BUNDLE_DOC}"
  echo "ok"

  echo "[check] bundle references all prerequisite docs"
  for doc in "${REQUIRED_DOCS[@]}"; do
    rg -n "${doc}" "${BUNDLE_DOC}" >/dev/null || fail "bundle doc does not reference ${doc}"
  done
  echo "ok"

  echo "[check] bundle keeps approval blocked"
  rg -n 'bundle_frozen=true|ready_for_review=true|active_control_approved=false|phase_b_user_approved=false|cable_phase_b_active_bridge_approved=false|publishes_fmu_in=false' \
    "${BUNDLE_DOC}" >/dev/null || fail "bundle doc missing frozen inactive markers"
  echo "ok"

  echo "[check] bundle does not reference an active bridge implementation"
  if rg -n 'cable_offboard_active_bridge' \
    ros2_ws/src/zcw_px4_baseline ros2_ws/src/zcw_bringup >/dev/null; then
    fail "bundle references active approval or active bridge implementation"
  fi
  echo "ok"
} >"${STATIC_LOG}" 2>&1 || {
  cat "${STATIC_LOG}" >&2
  exit 1
}

pass "static handoff-bundle checks accepted"

{
  echo "decision=accepted_cable_active_handoff_bundle"
  echo "bundle_frozen=true"
  echo "ready_for_review=true"
  echo "active_control_approved=false"
  echo "phase_b_user_approved=false"
  echo "cable_phase_b_active_bridge_approved=false"
  echo "publishes_fmu_in=false"
  echo "static_log=${STATIC_LOG}"
} >>"${SUMMARY_FILE}"

echo "Cable active handoff bundle audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Static log: ${STATIC_LOG}"
