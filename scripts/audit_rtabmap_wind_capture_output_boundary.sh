#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/rtabmap_wind_capture_output_boundary_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/rtabmap_wind_capture_output_boundary_${STAMP}.txt"

SOURCE_SUMMARY="${SOURCE_SUMMARY:-}"
if [[ -z "${SOURCE_SUMMARY}" ]]; then
  SOURCE_SUMMARY="$(find "${ROOT_DIR}/data/results" -path '*rtabmap_depth_camera_rgbd_wind_rviz_overlay_*/*.txt' | sort | tail -n 1)"
fi

value_for() {
  local key="$1"
  local file="$2"
  awk -F= -v key="${key}" '$1 == key { print substr($0, length(key) + 2); exit }' "${file}"
}

if [[ -z "${SOURCE_SUMMARY}" || ! -f "${SOURCE_SUMMARY}" ]]; then
  echo "RTAB-Map wind capture summary not found. Set SOURCE_SUMMARY." >&2
  exit 1
fi

TOPICS_LOG="$(value_for topics_log "${SOURCE_SUMMARY}")"
RTABMAP_LOG="$(value_for rtabmap_log "${SOURCE_SUMMARY}")"
DB_PATH="$(find "$(dirname "${SOURCE_SUMMARY}")" -maxdepth 1 -type f -name '*.db' | sort | tail -n 1)"

if [[ -z "${TOPICS_LOG}" || ! -f "${TOPICS_LOG}" ]]; then
  echo "topics log not found from summary: ${TOPICS_LOG}" >&2
  exit 1
fi
if [[ -z "${RTABMAP_LOG}" || ! -f "${RTABMAP_LOG}" ]]; then
  echo "rtabmap log not found from summary: ${RTABMAP_LOG}" >&2
  exit 1
fi
if [[ -z "${DB_PATH}" || ! -f "${DB_PATH}" ]]; then
  echo "RTAB-Map DB not found next to summary: ${DB_PATH}" >&2
  exit 1
fi
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 not found" >&2
  exit 1
fi

mkdir -p "${RESULT_DIR}"

summary_decision="$(value_for decision "${SOURCE_SUMMARY}")"
summary_outputs_ok="$(value_for outputs_ok "${SOURCE_SUMMARY}")"
summary_rtabmap_ok="$(value_for rtabmap_ok "${SOURCE_SUMMARY}")"
summary_motion_ok="$(value_for motion_ok "${SOURCE_SUMMARY}")"
summary_screenshot_ok="$(value_for screenshot_ok "${SOURCE_SUMMARY}")"
waypoint_advancements="$(value_for waypoint_advancements "${SOURCE_SUMMARY}")"

topics_have_map=false
topics_have_cloud_map=false
topics_have_octomap=false
rg -q '^/map$' "${TOPICS_LOG}" && topics_have_map=true
rg -q '^/cloud_map$' "${TOPICS_LOG}" && topics_have_cloud_map=true
rg -q '^/octomap_occupied_space$' "${TOPICS_LOG}" && topics_have_octomap=true

count_matches() {
  local pattern="$1"
  local file="$2"
  local count
  count="$(rg -c "${pattern}" "${file}" 2>/dev/null || true)"
  if [[ -z "${count}" ]]; then
    echo "0"
  else
    echo "${count}"
  fi
}

map_update_count="$(count_matches 'Maps update=[0-9.]+s' "${RTABMAP_LOG}")"
positive_map_update_count="$(python3 - "$RTABMAP_LOG" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(errors="replace")
count = 0
for value in re.findall(r"Maps update=([0-9.]+)s", text):
    try:
        if float(value) > 0.0:
            count += 1
    except ValueError:
        pass
print(count)
PY
)"
publish_maps_count="$(count_matches 'publishMaps\\(\\)|Graph has changed|whole cloud is regenerated' "${RTABMAP_LOG}")"
saving_database_count="$(count_matches 'Saving database/long-term memory\\.\\.\\.done' "${RTABMAP_LOG}")"
did_not_receive_count="$(count_matches 'Did not receive data since 5 seconds' "${RTABMAP_LOG}")"

db_node_count="$(sqlite3 "${DB_PATH}" "select count(*) from Node where pose is not null and length(pose)=48;")"
db_link_count="$(sqlite3 "${DB_PATH}" "select count(*) from Link;")"
db_global_closure_count="$(sqlite3 "${DB_PATH}" "select count(*) from Link where type=1;")"
db_local_space_closure_count="$(sqlite3 "${DB_PATH}" "select count(*) from Link where type=2;")"
db_local_time_closure_count="$(sqlite3 "${DB_PATH}" "select count(*) from Link where type=3;")"

log_has_map_publication=false
if [[ "${positive_map_update_count}" -gt 0 || "${publish_maps_count}" -gt 0 ]]; then
  log_has_map_publication=true
fi

db_has_graph=false
if [[ "${db_node_count}" -gt 0 && "${db_link_count}" -gt 0 ]]; then
  db_has_graph=true
fi

decision="accepted_rtabmap_wind_capture_output_boundary"
reason="summary_topic_gate_failed_but_rtabmap_log_and_db_show_mapping_evidence"
if [[ "${summary_outputs_ok}" == "true" ]]; then
  reason="summary_topic_gate_passed"
elif [[ "${log_has_map_publication}" != "true" || "${db_has_graph}" != "true" ]]; then
  decision="rejected_rtabmap_wind_capture_output_boundary"
  reason="summary_topic_gate_failed_and_log_or_db_mapping_evidence_missing"
fi

{
  echo "scope=rtabmap_wind_capture_output_boundary"
  echo "decision=${decision}"
  echo "reason=${reason}"
  echo "starts_ros=false"
  echo "starts_px4=false"
  echo "starts_gazebo=false"
  echo "starts_rviz=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "source_summary=${SOURCE_SUMMARY}"
  echo "topics_log=${TOPICS_LOG}"
  echo "rtabmap_log=${RTABMAP_LOG}"
  echo "db_path=${DB_PATH}"
  echo "summary_decision=${summary_decision}"
  echo "summary_outputs_ok=${summary_outputs_ok}"
  echo "summary_rtabmap_ok=${summary_rtabmap_ok}"
  echo "summary_motion_ok=${summary_motion_ok}"
  echo "summary_screenshot_ok=${summary_screenshot_ok}"
  echo "waypoint_advancements=${waypoint_advancements}"
  echo "topics_have_map=${topics_have_map}"
  echo "topics_have_cloud_map=${topics_have_cloud_map}"
  echo "topics_have_octomap_occupied_space=${topics_have_octomap}"
  echo "map_update_count=${map_update_count}"
  echo "positive_map_update_count=${positive_map_update_count}"
  echo "publish_maps_count=${publish_maps_count}"
  echo "saving_database_done_count=${saving_database_count}"
  echo "did_not_receive_data_warning_count=${did_not_receive_count}"
  echo "db_node_count=${db_node_count}"
  echo "db_link_count=${db_link_count}"
  echo "db_global_closure_count=${db_global_closure_count}"
  echo "db_local_space_closure_count=${db_local_space_closure_count}"
  echo "db_local_time_closure_count=${db_local_time_closure_count}"
  echo "log_has_map_publication=${log_has_map_publication}"
  echo "db_has_graph=${db_has_graph}"
  echo "claims_topic_output_gate_pass=$([[ "${summary_outputs_ok}" == "true" ]] && echo true || echo false)"
  echo "claims_mapping_evidence_pass=$([[ "${log_has_map_publication}" == "true" && "${db_has_graph}" == "true" ]] && echo true || echo false)"
} >"${SUMMARY_FILE}"

echo "RTAB-Map wind capture output-boundary audit completed."
echo "Summary: ${SUMMARY_FILE}"
