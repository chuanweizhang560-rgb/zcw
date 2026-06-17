#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_single_vehicle_active_scenario_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_single_vehicle_active_scenario_${STAMP}.txt"
STATIC_LOG="${RESULT_DIR}/static_checks_${STAMP}.log"

mkdir -p "${RESULT_DIR}"

fail() {
  echo "FAIL: $*" | tee -a "${SUMMARY_FILE}" >&2
  exit 1
}

pass() {
  echo "PASS: $*" | tee -a "${SUMMARY_FILE}"
}

SCENARIO_DOC="docs/26_cable_single_vehicle_active_scenario.md"
REQUIRED_DOCS=(
  "docs/25_cable_active_control_review_package.md"
  "docs/20_active_control_review_entry.md"
  "docs/21_future_cable_active_bridge_design.md"
  "docs/06_cable_phase_b_active_bridge_preflight.md"
  "docs/05_cable_phase_b_gate_plan.md"
  "docs/24_cable_surface_current_acceptance.md"
)

{
  echo "scope=cable_single_vehicle_active_scenario"
  echo "scenario=single_vehicle_cable_short_active"
  echo "active_control_approved=false"
  echo "phase_b_user_approved=false"
  echo "publishes_fmu_in=false"
  echo "rate_hz=20"
  echo "duration_sec=60"
} >"${SUMMARY_FILE}"

{
  echo "[check] scenario document exists"
  [[ -f "${SCENARIO_DOC}" ]] || fail "missing scenario doc: ${SCENARIO_DOC}"
  echo "ok"

  echo "[check] scenario document contains frozen limits"
  rg -n 'single_vehicle_cable_short_active|20 Hz|2.5 m|0.5 s|60 s|/fmu/in/\*|PROCESS_LOG.md' "${SCENARIO_DOC}" >/dev/null \
    || fail "scenario doc missing frozen scenario markers"
  echo "ok"

  echo "[check] scenario document references required docs"
  for doc in "${REQUIRED_DOCS[@]}"; do
    rg -n "${doc}" "${SCENARIO_DOC}" >/dev/null || fail "scenario doc does not reference ${doc}"
  done
  echo "ok"

  echo "[check] review package points to scenario freeze"
  rg -n 'docs/26_cable_single_vehicle_active_scenario.md|single_vehicle_cable_short_active' docs/25_cable_active_control_review_package.md >/dev/null \
    || fail "review package does not point to the frozen scenario"
  echo "ok"

  echo "[check] no active bridge implementation is added by this freeze"
  if rg -n 'cable_offboard_active_bridge|phase_b_user_approved:=true|phase_b_user_approved=true' \
    ros2_ws/src/zcw_px4_baseline ros2_ws/src/zcw_bringup \
    >"${RESULT_DIR}/active_bridge_refs_${STAMP}.log"; then
    cat "${RESULT_DIR}/active_bridge_refs_${STAMP}.log"
    fail "source tree contains active bridge implementation references"
  fi
  echo "ok"
} >"${STATIC_LOG}" 2>&1 || {
  cat "${STATIC_LOG}" >&2
  exit 1
}

pass "static scenario-freeze checks accepted"

{
  echo "decision=accepted_cable_single_vehicle_active_scenario"
  echo "scenario_frozen=true"
  echo "active_control_approved=false"
  echo "phase_b_user_approved=false"
  echo "publishes_fmu_in=false"
  echo "static_log=${STATIC_LOG}"
} >>"${SUMMARY_FILE}"

echo "Cable single-vehicle active scenario audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Static log: ${STATIC_LOG}"
