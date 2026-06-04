#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/dry_run_readiness_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/dry_run_readiness_${STAMP}.txt"
STATIC_LOG="${RESULT_DIR}/static_repo_checks_${STAMP}.log"
PX4_ISOLATION_LOG="${RESULT_DIR}/px4_isolation_${STAMP}.log"
PHASE_B_LOG="${RESULT_DIR}/phase_b_preflight_${STAMP}.log"
THRESHOLD_LOG="${RESULT_DIR}/thresholds_${STAMP}.log"
REVIEW_TEMPLATE_LOG="${RESULT_DIR}/review_template_${STAMP}.log"

mkdir -p "${RESULT_DIR}"

fail() {
  echo "FAIL: $*" | tee -a "${SUMMARY_FILE}" >&2
  exit 1
}

pass() {
  echo "PASS: $*" | tee -a "${SUMMARY_FILE}"
}

{
  echo "scope=dry_run_readiness"
  echo "phase_b_approved=false"
  echo "active_bridge_present=false"
  echo "publishes_fmu_in=false"
  echo "starts_ros=false"
  echo "starts_px4=false"
  echo "starts_gazebo=false"
  echo "starts_offboard=false"
  echo "arms=false"
} >"${SUMMARY_FILE}"

{
  echo "[check] active bridge target is absent"
  if rg -n 'cable_offboard_active_bridge' \
    ros2_ws/src/zcw_px4_baseline/CMakeLists.txt ros2_ws/src/zcw_px4_baseline/src ros2_ws/src/zcw_bringup/launch \
    >"${RESULT_DIR}/active_bridge_target_matches_${STAMP}.log"; then
    cat "${RESULT_DIR}/active_bridge_target_matches_${STAMP}.log"
    exit 1
  fi
  echo "ok"

  echo "[check] active approval is not enabled in scripts"
  if rg -n 'phase_b_user_approved:=true|phase_b_user_approved:=[Tt]rue' scripts \
    --glob '!audit_phase_b_active_preflight_boundary.sh' \
    --glob '!audit_dry_run_readiness.sh' \
    >"${RESULT_DIR}/phase_b_true_script_matches_${STAMP}.log"; then
    cat "${RESULT_DIR}/phase_b_true_script_matches_${STAMP}.log"
    exit 1
  fi
  echo "ok"

  echo "[check] generated/heavy directories are ignored"
  ignored_probes=(
    "data/logs/__probe__"
    "data/results/__probe__"
    "data/screenshots/__probe__"
    "data/training/__probe__"
    "third_party/__probe__"
    ".venv/__probe__"
    "build/__probe__"
    "install/__probe__"
    "log/__probe__"
    "ros2_ws/build/__probe__"
    "ros2_ws/install/__probe__"
    "ros2_ws/log/__probe__"
  )
  for path in "${ignored_probes[@]}"; do
    if ! git check-ignore -q "${path}"; then
      echo "not ignored: ${path}"
      exit 1
    fi
    echo "ignored ${path}"
  done
} >"${STATIC_LOG}" 2>&1 || {
  cat "${STATIC_LOG}" >&2
  fail "static repository readiness checks failed"
}
pass "static repository readiness checks accepted"

scripts/audit_px4_isolation.sh >"${PX4_ISOLATION_LOG}" 2>&1 ||
  { cat "${PX4_ISOLATION_LOG}" >&2; fail "PX4 isolation audit failed"; }
pass "PX4 isolation audit accepted"

scripts/audit_phase_b_active_preflight_boundary.sh >"${PHASE_B_LOG}" 2>&1 ||
  { cat "${PHASE_B_LOG}" >&2; fail "Phase B active preflight boundary audit failed"; }
pass "Phase B active preflight boundary accepted"

scripts/audit_cable_setpoint_thresholds.sh >"${THRESHOLD_LOG}" 2>&1 ||
  { cat "${THRESHOLD_LOG}" >&2; fail "Cable setpoint threshold audit failed"; }
pass "Cable setpoint threshold audit accepted"

scripts/audit_active_bridge_review_template.sh >"${REVIEW_TEMPLATE_LOG}" 2>&1 ||
  { cat "${REVIEW_TEMPLATE_LOG}" >&2; fail "Active bridge review template audit failed"; }
pass "Active bridge review template audit accepted"

{
  echo "decision=accepted_dry_run_readiness"
  echo "phase_b_approved=false"
  echo "active_bridge_present=false"
  echo "publishes_fmu_in=false"
  echo "static_log=${STATIC_LOG}"
  echo "px4_isolation_log=${PX4_ISOLATION_LOG}"
  echo "phase_b_log=${PHASE_B_LOG}"
  echo "threshold_log=${THRESHOLD_LOG}"
  echo "review_template_log=${REVIEW_TEMPLATE_LOG}"
} >>"${SUMMARY_FILE}"

echo "Dry-run readiness audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Static log: ${STATIC_LOG}"
echo "PX4 isolation log: ${PX4_ISOLATION_LOG}"
echo "Phase B preflight log: ${PHASE_B_LOG}"
echo "Threshold log: ${THRESHOLD_LOG}"
echo "Review template log: ${REVIEW_TEMPLATE_LOG}"
