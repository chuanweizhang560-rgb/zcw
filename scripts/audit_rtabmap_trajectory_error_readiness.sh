#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/rtabmap_trajectory_error_readiness_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/rtabmap_trajectory_error_readiness_${STAMP}.txt"
CSV_FILE="${RESULT_DIR}/rtabmap_trajectory_error_readiness_${STAMP}.csv"

MOTION_DB="${MOTION_DB:-${ROOT_DIR}/data/results/rtabmap_depth_camera_rgbd_motion_rviz_overlay_20260608_104943/rtabmap_depth_camera_rgbd_motion_20260608_104943.db}"
WIND_DB="${WIND_DB:-${ROOT_DIR}/data/results/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260608_105840/rtabmap_depth_camera_rgbd_wind_20260608_105840.db}"
MOTION_REF_LOG="${MOTION_REF_LOG:-${ROOT_DIR}/data/logs/rtabmap_depth_camera_rgbd_motion_rviz_vehicle_local_position_20260608_104943.log}"
WIND_REF_LOG="${WIND_REF_LOG:-${ROOT_DIR}/data/logs/rtabmap_depth_camera_rgbd_wind_rviz_vehicle_local_position_20260608_105840.log}"

mkdir -p "${RESULT_DIR}"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 not found" >&2
  exit 1
fi

db_count_metric() {
  local db="$1"
  local sql="$2"
  sqlite3 "${db}" "${sql}"
}

ref_sample_count() {
  local log="$1"
  if [[ ! -f "${log}" ]]; then
    echo "0"
    return
  fi
  local separators
  separators="$(rg -c '^---$' "${log}" || true)"
  if [[ "${separators}" -gt 0 ]]; then
    echo "${separators}"
  elif rg -q '^timestamp:' "${log}"; then
    echo "1"
  else
    echo "0"
  fi
}

write_row() {
  local scenario="$1"
  local db="$2"
  local ref_log="$3"
  local node_count
  local pose_count
  local ground_truth_count
  local ref_count
  local can_compute_ate

  if [[ ! -f "${db}" ]]; then
    echo "RTAB-Map database missing: ${db}" >&2
    exit 1
  fi

  node_count="$(db_count_metric "${db}" "select count(*) from Node;")"
  pose_count="$(db_count_metric "${db}" "select count(*) from Node where pose is not null and length(pose) > 0;")"
  ground_truth_count="$(db_count_metric "${db}" "select count(*) from Node where ground_truth_pose is not null and length(ground_truth_pose) > 0 and hex(ground_truth_pose) != printf('%0*d', length(ground_truth_pose) * 2, 0);")"
  ref_count="$(ref_sample_count "${ref_log}")"
  can_compute_ate=false
  if [[ "${pose_count}" -ge 2 && "${ref_count}" -ge 2 ]]; then
    can_compute_ate=true
  fi

  printf "%s,%s,%s,%s,%s,%s,%s,%s\n" \
    "${scenario}" \
    "${db}" \
    "${ref_log}" \
    "${node_count}" \
    "${pose_count}" \
    "${ground_truth_count}" \
    "${ref_count}" \
    "${can_compute_ate}" >>"${CSV_FILE}"
}

echo "scenario,db_path,reference_log,node_count,pose_count,ground_truth_pose_count,reference_sample_count,can_compute_ate_from_existing_files" >"${CSV_FILE}"
write_row "cable_motion_rgbd" "${MOTION_DB}" "${MOTION_REF_LOG}"
write_row "wind_motion_rgbd" "${WIND_DB}" "${WIND_REF_LOG}"

db_pose_ready=false
ground_truth_ready=false
reference_ready=false
ate_ready=false

if awk -F, 'NR > 1 { if ($5 < 2) exit 1 }' "${CSV_FILE}"; then
  db_pose_ready=true
fi
if awk -F, 'NR > 1 { if ($6 < 2) exit 1 }' "${CSV_FILE}"; then
  ground_truth_ready=true
fi
if awk -F, 'NR > 1 { if ($7 < 2) exit 1 }' "${CSV_FILE}"; then
  reference_ready=true
fi
if [[ "${db_pose_ready}" == "true" && "${reference_ready}" == "true" ]]; then
  ate_ready=true
fi

accepted=true
reason="existing_files_audited_but_reference_trajectory_is_insufficient_for_ate"
if [[ "${db_pose_ready}" != "true" ]]; then
  accepted=false
  reason="rtabmap_databases_do_not_contain_enough_poses"
fi

{
  echo "scope=rtabmap_trajectory_error_readiness"
  echo "decision=$([[ "${accepted}" == "true" ]] && echo accepted_rtabmap_trajectory_error_readiness || echo rejected_rtabmap_trajectory_error_readiness)"
  echo "reason=${reason}"
  echo "starts_ros=false"
  echo "starts_px4=false"
  echo "starts_gazebo=false"
  echo "starts_rviz=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "claims_trajectory_error=false"
  echo "db_pose_ready=${db_pose_ready}"
  echo "ground_truth_ready=${ground_truth_ready}"
  echo "reference_ready=${reference_ready}"
  echo "ate_ready=${ate_ready}"
  echo "csv_file=${CSV_FILE}"
  echo "motion_db=${MOTION_DB}"
  echo "wind_db=${WIND_DB}"
  echo "motion_reference_log=${MOTION_REF_LOG}"
  echo "wind_reference_log=${WIND_REF_LOG}"
} >"${SUMMARY_FILE}"

if [[ "${accepted}" != "true" ]]; then
  cat "${SUMMARY_FILE}" >&2
  cat "${CSV_FILE}" >&2
  exit 1
fi

echo "RTAB-Map trajectory error readiness audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "CSV: ${CSV_FILE}"
