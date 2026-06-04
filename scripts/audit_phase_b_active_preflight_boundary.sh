#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/phase_b_active_preflight_boundary_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/phase_b_active_preflight_boundary_${STAMP}.txt"
STATIC_LOG="${RESULT_DIR}/static_checks_${STAMP}.log"
EVIDENCE_LOG="${RESULT_DIR}/evidence_checks_${STAMP}.log"

mkdir -p "${RESULT_DIR}"

fail() {
  echo "FAIL: $*" | tee -a "${SUMMARY_FILE}" >&2
  exit 1
}

pass() {
  echo "PASS: $*" | tee -a "${SUMMARY_FILE}"
}

{
  echo "scope=phase_b_active_preflight_boundary"
  echo "publishes_fmu_in=false"
  echo "starts_px4=false"
  echo "starts_offboard=false"
  echo "arms=false"
} >"${SUMMARY_FILE}"

{
  echo "[check] no cable active executable is present before approval"
  if rg -n 'cable_offboard_active_bridge|cable_.*active.*bridge' \
    ros2_ws/src/zcw_px4_baseline/CMakeLists.txt ros2_ws/src/zcw_px4_baseline/src ros2_ws/src/zcw_bringup/launch \
    >"${RESULT_DIR}/active_bridge_references_${STAMP}.log"; then
    cat "${RESULT_DIR}/active_bridge_references_${STAMP}.log"
    fail "active cable bridge reference exists before approval"
  fi
  echo "ok"

  echo "[check] cable-specific C++ sources do not create /fmu/in publishers"
  if rg -n 'create_publisher<[^>]+>\("/fmu/in/' ros2_ws/src/zcw_px4_baseline/src/cable_*.cpp \
    >"${RESULT_DIR}/cable_fmu_publishers_${STAMP}.log"; then
    cat "${RESULT_DIR}/cable_fmu_publishers_${STAMP}.log"
    fail "cable-specific C++ source publishes /fmu/in before approval"
  fi
  echo "ok"

  echo "[check] cable scripts never set phase_b_user_approved true"
  if rg -n 'phase_b_user_approved:=true|phase_b_user_approved:=[Tt]rue' scripts \
    --glob '!audit_phase_b_active_preflight_boundary.sh' \
    >"${RESULT_DIR}/phase_b_true_scripts_${STAMP}.log"; then
    cat "${RESULT_DIR}/phase_b_true_scripts_${STAMP}.log"
    fail "script enables phase_b_user_approved before approval"
  fi
  echo "ok"

  echo "[check] cable scripts do not directly publish PX4 input topics"
  if rg -n 'ros2 topic pub.*/fmu/in|/fmu/in/(trajectory_setpoint|offboard_control_mode|vehicle_command).*pub' scripts \
    --glob '!audit_phase_b_active_preflight_boundary.sh' \
    --glob '!audit_px4_isolation.sh' \
    >"${RESULT_DIR}/script_direct_fmu_publish_${STAMP}.log"; then
    cat "${RESULT_DIR}/script_direct_fmu_publish_${STAMP}.log"
    fail "script directly publishes PX4 input topic before approval"
  fi
  echo "ok"

  echo "[check] zcw_cable_perception remains isolated from px4_msgs and PX4 input APIs"
  scripts/audit_px4_isolation.sh
  echo "ok"
} >"${STATIC_LOG}" 2>&1 || {
  cat "${STATIC_LOG}" >&2
  exit 1
}
pass "static boundary checks accepted"

required_files=(
  "data/logs/px4_bridge_dry_run_state_echo_20260603_190805.log"
  "data/screenshots/px4_bridge_dry_run_rviz_overlay_20260603_191816.png"
  "data/results/px4_gazebo_frame_alignment_20260603_194311/px4_gazebo_frame_alignment_20260603_194311.txt"
  "data/results/cable_offboard_gate_dry_run_20260604_085746/cable_offboard_gate_dry_run_20260604_085746.txt"
  "data/logs/cable_offboard_gate_forbidden_publishers_20260604_085746.log"
  "data/results/cable_offboard_gate_rviz_overlay_20260604_090442/cable_offboard_gate_rviz_overlay_20260604_090442.txt"
  "data/screenshots/cable_offboard_gate_dry_run_rviz_overlay_20260604_090442.png"
)

: >"${EVIDENCE_LOG}"
for path in "${required_files[@]}"; do
  if [[ ! -f "${path}" ]]; then
    echo "missing ${path}" >>"${EVIDENCE_LOG}"
    fail "required local evidence is missing: ${path}"
  fi
  echo "present ${path}" >>"${EVIDENCE_LOG}"
done
pass "required local dry-run evidence files are present"

grep -q 'DRY_RUN_READY' data/logs/px4_bridge_dry_run_state_echo_20260603_190805.log ||
  fail "Phase A bridge state evidence does not contain DRY_RUN_READY"
grep -q 'decision=accepted_readonly_frame_sample_smoke' \
  data/results/px4_gazebo_frame_alignment_20260603_194311/px4_gazebo_frame_alignment_20260603_194311.txt ||
  fail "PX4/Gazebo frame audit evidence is not accepted"
grep -q 'decision=accepted_cable_offboard_gate_dry_run_smoke' \
  data/results/cable_offboard_gate_dry_run_20260604_085746/cable_offboard_gate_dry_run_20260604_085746.txt ||
  fail "Offboard gate dry-run summary is not accepted"
grep -q 'decision=accepted_cable_offboard_gate_rviz_overlay_capture' \
  data/results/cable_offboard_gate_rviz_overlay_20260604_090442/cable_offboard_gate_rviz_overlay_20260604_090442.txt ||
  fail "Offboard gate RViz overlay summary is not accepted"

if rg -n 'Publisher count: [1-9][0-9]*' data/logs/cable_offboard_gate_forbidden_publishers_20260604_085746.log \
  >"${RESULT_DIR}/nonzero_publishers_${STAMP}.log"; then
  cat "${RESULT_DIR}/nonzero_publishers_${STAMP}.log" >&2
  fail "Offboard gate dry-run evidence contains nonzero /fmu/in publisher count"
fi
pass "required dry-run evidence content accepted"

{
  echo "decision=accepted_phase_b_active_preflight_boundary"
  echo "phase_b_approved=false"
  echo "active_bridge_present=false"
  echo "publishes_fmu_in=false"
  echo "static_log=${STATIC_LOG}"
  echo "evidence_log=${EVIDENCE_LOG}"
} >>"${SUMMARY_FILE}"

echo "Phase B active preflight boundary audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Static log: ${STATIC_LOG}"
echo "Evidence log: ${EVIDENCE_LOG}"
