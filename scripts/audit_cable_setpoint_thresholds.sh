#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_OFFSET_PATH="data/results/catenary_offset_yz_zbin2_20260603_135000/depth_camera_motion_catenary_offset_yz_zbin2_offset_path_20260603_125948.csv"
DEFAULT_TARGETS="data/results/lookahead_target_audit_20260603_165600/depth_camera_motion_lookahead_target_audit_targets_20260603_165501.csv"
DEFAULT_GATE_STATE="data/logs/cable_offboard_gate_rviz_state_echo_20260604_090442.log"
DEFAULT_APPROVED_NED="data/logs/cable_offboard_gate_rviz_approved_ned_echo_20260604_090442.log"

OFFSET_PATH_CSV="${OFFSET_PATH_CSV:-${DEFAULT_OFFSET_PATH}}"
TARGETS_CSV="${TARGETS_CSV:-${DEFAULT_TARGETS}}"
GATE_STATE_LOG="${GATE_STATE_LOG:-${DEFAULT_GATE_STATE}}"
APPROVED_NED_LOG="${APPROVED_NED_LOG:-${DEFAULT_APPROVED_NED}}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${RESULT_ROOT}/cable_setpoint_thresholds_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_setpoint_thresholds_${STAMP}.txt"
PATH_STATS="${RESULT_DIR}/offset_path_stats_${STAMP}.txt"
TARGET_STATS="${RESULT_DIR}/lookahead_target_stats_${STAMP}.txt"
GATE_STATS="${RESULT_DIR}/gate_state_stats_${STAMP}.txt"
NED_STATS="${RESULT_DIR}/approved_ned_stats_${STAMP}.txt"

MAX_ACTIVE_HORIZONTAL_JUMP_M="${MAX_ACTIVE_HORIZONTAL_JUMP_M:-2.5}"
MAX_ACTIVE_VERTICAL_JUMP_M="${MAX_ACTIVE_VERTICAL_JUMP_M:-0.5}"
MAX_DRY_RUN_HORIZONTAL_JUMP_M="${MAX_DRY_RUN_HORIZONTAL_JUMP_M:-5.0}"
MAX_DRY_RUN_VERTICAL_JUMP_M="${MAX_DRY_RUN_VERTICAL_JUMP_M:-2.0}"
EXPECTED_DRY_RUN_STEP_M="${EXPECTED_DRY_RUN_STEP_M:-1.1}"
MAX_TARGET_SPACING_M="${MAX_TARGET_SPACING_M:-10.5}"
MAX_OFFSET_STEP_M="${MAX_OFFSET_STEP_M:-10.5}"

for path in "${OFFSET_PATH_CSV}" "${TARGETS_CSV}" "${GATE_STATE_LOG}" "${APPROVED_NED_LOG}"; do
  if [[ ! -f "${path}" ]]; then
    echo "Required input does not exist: ${path}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

awk -F, '
NR == 1 {next}
$1 == group {
  x = $3 + 0.0; y = $4 + 0.0; z = $5 + 0.0
  if (seen > 0) {
    dx = x - px; dy = y - py; dz = z - pz
    d = sqrt(dx * dx + dy * dy + dz * dz)
    adz = dz < 0 ? -dz : dz
    if (d > max_step) max_step = d
    if (adz > max_vertical) max_vertical = adz
    sum_step += d
    steps += 1
  }
  px = x; py = y; pz = z; seen += 1
}
END {
  if (seen < 2) {
    printf("decision=rejected_offset_path_stats\nreason=not_enough_points\npoints=%d\n", seen)
    exit 1
  }
  printf("decision=accepted_offset_path_stats\n")
  printf("group_id=%s\n", group)
  printf("points=%d\n", seen)
  printf("steps=%d\n", steps)
  printf("mean_step_m=%.6f\n", sum_step / steps)
  printf("max_step_m=%.6f\n", max_step)
  printf("max_vertical_step_m=%.6f\n", max_vertical)
}
' group="${GROUP_ID:-y8_z20}" "${OFFSET_PATH_CSV}" >"${PATH_STATS}"

awk -F, '
NR == 1 {next}
$1 == group {
  x = $7 + 0.0; y = $8 + 0.0; z = $9 + 0.0
  dist = $10 + 0.0
  if (seen > 0) {
    dx = x - px; dy = y - py; dz = z - pz
    d = sqrt(dx * dx + dy * dy + dz * dz)
    adz = dz < 0 ? -dz : dz
    if (d > max_target_jump) max_target_jump = d
    if (adz > max_vertical_jump) max_vertical_jump = adz
    sum_target_jump += d
    jumps += 1
  }
  if (dist > max_target_distance) max_target_distance = dist
  if (seen == 0 || dist < min_target_distance) min_target_distance = dist
  sum_target_distance += dist
  px = x; py = y; pz = z; seen += 1
}
END {
  if (seen < 2) {
    printf("decision=rejected_lookahead_target_stats\nreason=not_enough_targets\npoints=%d\n", seen)
    exit 1
  }
  printf("decision=accepted_lookahead_target_stats\n")
  printf("group_id=%s\n", group)
  printf("targets=%d\n", seen)
  printf("jumps=%d\n", jumps)
  printf("mean_target_jump_m=%.6f\n", sum_target_jump / jumps)
  printf("max_target_jump_m=%.6f\n", max_target_jump)
  printf("max_target_vertical_jump_m=%.6f\n", max_vertical_jump)
  printf("mean_target_distance_m=%.6f\n", sum_target_distance / seen)
  printf("min_target_distance_m=%.6f\n", min_target_distance)
  printf("max_target_distance_m=%.6f\n", max_target_distance)
}
' group="${GROUP_ID:-y8_z20}" "${TARGETS_CSV}" >"${TARGET_STATS}"

awk '
{
  for (i = 1; i <= NF; ++i) {
    if ($i ~ /^horizontal_jump_m=/) {
      split($i, a, "="); h = a[2] + 0.0; seen_h = 1
    }
    if ($i ~ /^vertical_jump_m=/) {
      split($i, a, "="); v = a[2] + 0.0; seen_v = 1
    }
  }
}
END {
  if (!seen_h || !seen_v) {
    printf("decision=rejected_gate_state_stats\nreason=missing_jump_fields\n")
    exit 1
  }
  printf("decision=accepted_gate_state_stats\n")
  printf("observed_horizontal_jump_m=%.6f\n", h)
  printf("observed_vertical_jump_m=%.6f\n", v)
}
' "${GATE_STATE_LOG}" >"${GATE_STATS}"

awk '
/frame_id:/ {frame = $2}
/  x:/ {x = $2 + 0.0; seen_x = 1}
/  y:/ {y = $2 + 0.0; seen_y = 1}
/  z:/ {z = $2 + 0.0; seen_z = 1}
END {
  if (!seen_x || !seen_y || !seen_z) {
    printf("decision=rejected_approved_ned_stats\nreason=missing_point\n")
    exit 1
  }
  printf("decision=accepted_approved_ned_stats\n")
  printf("frame_id=%s\n", frame)
  printf("ned_x=%.6f\n", x)
  printf("ned_y=%.6f\n", y)
  printf("ned_z=%.6f\n", z)
}
' "${APPROVED_NED_LOG}" >"${NED_STATS}"

path_max_step="$(awk -F= '/^max_step_m=/{print $2}' "${PATH_STATS}")"
target_max_jump="$(awk -F= '/^max_target_jump_m=/{print $2}' "${TARGET_STATS}")"
gate_h_jump="$(awk -F= '/^observed_horizontal_jump_m=/{print $2}' "${GATE_STATS}")"
gate_v_jump="$(awk -F= '/^observed_vertical_jump_m=/{print $2}' "${GATE_STATS}")"
ned_frame="$(awk -F= '/^frame_id=/{print $2}' "${NED_STATS}")"

decision="accepted_cable_setpoint_threshold_audit"
reason="all_threshold_inputs_within_expected_bounds"

awk -v value="${path_max_step}" -v limit="${MAX_OFFSET_STEP_M}" 'BEGIN {exit !(value <= limit)}' ||
  { decision="rejected_cable_setpoint_threshold_audit"; reason="offset_path_step_exceeds_limit"; }
awk -v value="${target_max_jump}" -v limit="${MAX_TARGET_SPACING_M}" 'BEGIN {exit !(value <= limit)}' ||
  { decision="rejected_cable_setpoint_threshold_audit"; reason="target_spacing_exceeds_limit"; }
awk -v value="${gate_h_jump}" -v limit="${EXPECTED_DRY_RUN_STEP_M}" 'BEGIN {exit !(value <= limit)}' ||
  { decision="rejected_cable_setpoint_threshold_audit"; reason="dry_run_horizontal_step_exceeds_expected"; }
awk -v value="${gate_v_jump}" -v limit="${MAX_ACTIVE_VERTICAL_JUMP_M}" 'BEGIN {exit !(value <= limit)}' ||
  { decision="rejected_cable_setpoint_threshold_audit"; reason="dry_run_vertical_step_exceeds_active_limit"; }
if [[ "${ned_frame}" != "px4_local_ned_dry_run" ]]; then
  decision="rejected_cable_setpoint_threshold_audit"
  reason="unexpected_ned_frame"
fi

{
  echo "decision=${decision}"
  echo "reason=${reason}"
  echo "publishes_fmu_in=false"
  echo "starts_px4=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "offset_path_csv=${OFFSET_PATH_CSV}"
  echo "targets_csv=${TARGETS_CSV}"
  echo "gate_state_log=${GATE_STATE_LOG}"
  echo "approved_ned_log=${APPROVED_NED_LOG}"
  echo "path_stats=${PATH_STATS}"
  echo "target_stats=${TARGET_STATS}"
  echo "gate_stats=${GATE_STATS}"
  echo "ned_stats=${NED_STATS}"
  echo "max_offset_step_m=${path_max_step}"
  echo "max_target_jump_m=${target_max_jump}"
  echo "observed_gate_horizontal_jump_m=${gate_h_jump}"
  echo "observed_gate_vertical_jump_m=${gate_v_jump}"
  echo "active_horizontal_jump_limit_m=${MAX_ACTIVE_HORIZONTAL_JUMP_M}"
  echo "active_vertical_jump_limit_m=${MAX_ACTIVE_VERTICAL_JUMP_M}"
  echo "dry_run_horizontal_jump_limit_m=${MAX_DRY_RUN_HORIZONTAL_JUMP_M}"
  echo "dry_run_vertical_jump_limit_m=${MAX_DRY_RUN_VERTICAL_JUMP_M}"
  echo "recommendation=keep active horizontal gate at <=2.5m and dry-run smoke compatibility at <=5.0m; require dry-run observed step <=1.1m before active approval."
} >"${SUMMARY_FILE}"

echo "Cable setpoint threshold audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Path stats: ${PATH_STATS}"
echo "Target stats: ${TARGET_STATS}"
echo "Gate stats: ${GATE_STATS}"
echo "NED stats: ${NED_STATS}"

[[ "${decision}" == "accepted_cable_setpoint_threshold_audit" ]]
