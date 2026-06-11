#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/rtabmap_db_info_metrics_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/rtabmap_db_info_metrics_${STAMP}.txt"
CSV_FILE="${RESULT_DIR}/rtabmap_db_info_metrics_${STAMP}.csv"

MOTION_DB="${MOTION_DB:-${ROOT_DIR}/data/results/rtabmap_depth_camera_rgbd_motion_rviz_overlay_20260608_104943/rtabmap_depth_camera_rgbd_motion_20260608_104943.db}"
WIND_DB="${WIND_DB:-${ROOT_DIR}/data/results/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260608_105840/rtabmap_depth_camera_rgbd_wind_20260608_105840.db}"

mkdir -p "${RESULT_DIR}"

if ! command -v rtabmap-info >/dev/null 2>&1; then
  echo "rtabmap-info not found" >&2
  exit 1
fi
for db in "${MOTION_DB}" "${WIND_DB}"; do
  if [[ ! -f "${db}" ]]; then
    echo "RTAB-Map database not found: ${db}" >&2
    exit 1
  fi
done

extract_metric() {
  local label="$1"
  local log_file="$2"
  awk -v label="${label}" '
    index($0, label ":") == 1 {
      value = substr($0, length(label) + 2)
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "${log_file}"
}

extract_link_count() {
  local link_label="$1"
  local log_file="$2"
  awk -v label="${link_label}" '
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
    }
    index(line, label ":") == 1 {
      value = substr(line, length(label) + 2)
      sub(/^[[:space:]]+/, "", value)
      print value + 0
      exit
    }
  ' "${log_file}"
}

extract_first_number() {
  awk '{ print $1 }'
}

extract_nodes_count() {
  awk '{ print $1 }'
}

write_row() {
  local scenario="$1"
  local db_path="$2"
  local info_log="${RESULT_DIR}/rtabmap_info_${scenario}_${STAMP}.log"
  local clean_log="${RESULT_DIR}/rtabmap_info_${scenario}_${STAMP}_clean.log"

  rtabmap-info "${db_path}" >"${info_log}" 2>&1
  sed -r 's/\x1B\[[0-9;]*[mK]//g' "${info_log}" >"${clean_log}"

  local version
  local total_odom_length_m
  local total_time_s
  local ltm_nodes
  local ltm_words
  local wm_nodes
  local global_graph_poses
  local global_graph_links
  local optimized_graph_poses
  local ground_truth_poses
  local gps_poses
  local neighbor_links
  local global_closure_links
  local local_space_closure_links
  local database_size
  version="$(extract_metric "Version" "${clean_log}")"
  total_odom_length_m="$(extract_metric "Total odometry length" "${clean_log}" | awk '{ print $1 }')"
  total_time_s="$(extract_metric "Total time" "${clean_log}" | awk '{ print $1 }' | sed 's/s$//')"
  ltm_nodes="$(extract_metric "LTM" "${clean_log}" | extract_nodes_count)"
  ltm_words="$(extract_metric "LTM" "${clean_log}" | awk '{ print $4 }')"
  wm_nodes="$(extract_metric "WM" "${clean_log}" | extract_nodes_count)"
  global_graph_poses="$(extract_metric "Global graph" "${clean_log}" | awk '{ print $1 }')"
  global_graph_links="$(extract_metric "Global graph" "${clean_log}" | awk '{ print $4 }')"
  optimized_graph_poses="$(extract_metric "Optimized graph" "${clean_log}" | awk '{ print $1 }')"
  ground_truth_poses="$(extract_metric "Ground truth" "${clean_log}" | extract_first_number)"
  gps_poses="$(extract_metric "GPS" "${clean_log}" | extract_first_number)"
  neighbor_links="$(extract_link_count "Neighbor" "${clean_log}")"
  global_closure_links="$(extract_link_count "GlobalClosure" "${clean_log}")"
  local_space_closure_links="$(extract_link_count "LocalSpaceClosure" "${clean_log}")"
  database_size="$(extract_metric "Database size" "${clean_log}")"

  printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
    "${scenario}" \
    "${db_path}" \
    "${version}" \
    "${total_odom_length_m}" \
    "${total_time_s}" \
    "${ltm_nodes}" \
    "${ltm_words}" \
    "${wm_nodes}" \
    "${global_graph_poses}" \
    "${global_graph_links}" \
    "${optimized_graph_poses}" \
    "${ground_truth_poses}" \
    "${gps_poses}" \
    "${neighbor_links}" \
    "${global_closure_links}" \
    "${local_space_closure_links}" \
    "\"${database_size}\"" \
    "${clean_log}" >>"${CSV_FILE}"
}

echo "scenario,db_path,version,total_odom_length_m,total_time_s,ltm_nodes,ltm_words,wm_nodes,global_graph_poses,global_graph_links,optimized_graph_poses,ground_truth_poses,gps_poses,neighbor_links,global_closure_links,local_space_closure_links,database_size,clean_info_log" >"${CSV_FILE}"
write_row "cable_motion_rgbd" "${MOTION_DB}"
write_row "wind_motion_rgbd" "${WIND_DB}"

accepted=true
reason="rtabmap_info_quantified_existing_databases_with_limitations"
if ! awk -F, 'NR > 1 { if ($4 <= 0 || $5 <= 0 || $6 <= 0 || $9 <= 0 || $14 <= 0) exit 1 }' "${CSV_FILE}"; then
  accepted=false
  reason="rtabmap_database_missing_positive_motion_or_graph_metrics"
fi
if ! awk -F, 'NR > 1 { if ($12 != 0) exit 1 }' "${CSV_FILE}"; then
  accepted=false
  reason="unexpected_ground_truth_present"
fi

total_global_closures="$(awk -F, 'NR > 1 { sum += $15 } END { print sum + 0 }' "${CSV_FILE}")"
total_local_space_closures="$(awk -F, 'NR > 1 { sum += $16 } END { print sum + 0 }' "${CSV_FILE}")"
ground_truth_total="$(awk -F, 'NR > 1 { sum += $12 } END { print sum + 0 }' "${CSV_FILE}")"
db_count="$(awk 'END { print NR - 1 }' "${CSV_FILE}")"

{
  echo "scope=rtabmap_db_info_metrics"
  echo "decision=$([[ "${accepted}" == "true" ]] && echo accepted_rtabmap_db_info_metrics || echo rejected_rtabmap_db_info_metrics)"
  echo "reason=${reason}"
  echo "starts_ros=false"
  echo "starts_px4=false"
  echo "starts_gazebo=false"
  echo "starts_rviz=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "uses_rtabmap_info=true"
  echo "claims_slam_accuracy=false"
  echo "claims_loop_closure_quality=false"
  echo "database_count=${db_count}"
  echo "ground_truth_total=${ground_truth_total}"
  echo "total_global_closures=${total_global_closures}"
  echo "total_local_space_closures=${total_local_space_closures}"
  echo "csv_file=${CSV_FILE}"
  echo "motion_db=${MOTION_DB}"
  echo "wind_db=${WIND_DB}"
} >"${SUMMARY_FILE}"

if [[ "${accepted}" != "true" ]]; then
  cat "${SUMMARY_FILE}" >&2
  cat "${CSV_FILE}" >&2
  exit 1
fi

echo "RTAB-Map database info metrics audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "CSV: ${CSV_FILE}"
