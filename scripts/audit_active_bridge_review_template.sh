#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/active_bridge_review_template_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/active_bridge_review_template_${STAMP}.txt"
TEMPLATE_LOG="${RESULT_DIR}/template_checks_${STAMP}.log"
BOUNDARY_LOG="${RESULT_DIR}/boundary_checks_${STAMP}.log"

TEMPLATE="docs/08_cable_active_bridge_code_review.md"

mkdir -p "${RESULT_DIR}"

fail() {
  echo "FAIL: $*" | tee -a "${SUMMARY_FILE}" >&2
  exit 1
}

pass() {
  echo "PASS: $*" | tee -a "${SUMMARY_FILE}"
}

{
  echo "scope=active_bridge_review_template"
  echo "phase_b_approved=false"
  echo "active_bridge_present=false"
  echo "publishes_fmu_in=false"
  echo "starts_px4=false"
  echo "starts_offboard=false"
  echo "arms=false"
} >"${SUMMARY_FILE}"

if [[ ! -f "${TEMPLATE}" ]]; then
  fail "missing review template: ${TEMPLATE}"
fi

{
  echo "[check] required review template sections"
  required_patterns=(
    '^## 1\. Review Scope$'
    '^## 2\. Required Inputs$'
    '^## 3\. Required Outputs$'
    '^## 4\. Required State Machine$'
    '^## 5\. Required Safety Gates$'
    '^## 6\. Required Abort Conditions$'
    '^## 7\. Required Tests$'
    '^## 8\. Review Decision Format$'
    'decision=not_started_cable_active_bridge_review'
    'phase_b_approved=false'
    'active_bridge_present=false'
    'publishes_fmu_in=false'
  )
  for pattern in "${required_patterns[@]}"; do
    if ! rg -n "${pattern}" "${TEMPLATE}" >/dev/null; then
      echo "missing pattern: ${pattern}"
      exit 1
    fi
    echo "ok ${pattern}"
  done
} >"${TEMPLATE_LOG}" 2>&1 || {
  cat "${TEMPLATE_LOG}" >&2
  fail "review template missing required section or decision field"
}
pass "review template sections accepted"

{
  echo "[check] no active bridge source/CMake/launch target exists yet"
  if rg -n 'cable_offboard_active_bridge' \
    ros2_ws/src/zcw_px4_baseline/CMakeLists.txt ros2_ws/src/zcw_px4_baseline/src ros2_ws/src/zcw_bringup/launch \
    >"${RESULT_DIR}/active_bridge_target_matches_${STAMP}.log"; then
    cat "${RESULT_DIR}/active_bridge_target_matches_${STAMP}.log"
    exit 1
  fi
  echo "ok"

  echo "[check] current dry-run boundary audit"
  scripts/audit_phase_b_active_preflight_boundary.sh
  echo "ok"

  echo "[check] current setpoint threshold audit"
  scripts/audit_cable_setpoint_thresholds.sh
  echo "ok"
} >"${BOUNDARY_LOG}" 2>&1 || {
  cat "${BOUNDARY_LOG}" >&2
  fail "current boundary is not ready for review-template baseline"
}
pass "current dry-run-only boundary accepted"

{
  echo "decision=accepted_active_bridge_review_template_audit"
  echo "phase_b_approved=false"
  echo "active_bridge_present=false"
  echo "publishes_fmu_in=false"
  echo "template_log=${TEMPLATE_LOG}"
  echo "boundary_log=${BOUNDARY_LOG}"
} >>"${SUMMARY_FILE}"

echo "Active bridge review template audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Template log: ${TEMPLATE_LOG}"
echo "Boundary log: ${BOUNDARY_LOG}"
