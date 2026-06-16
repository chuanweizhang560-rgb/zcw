#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_OFFSET_PATH="data/results/catenary_offset_yz_zbin2_step5_20260608_000000/depth_camera_motion_catenary_offset_yz_zbin2_step5_offset_path_20260608_085655.csv"
DEFAULT_TARGETS="data/results/lookahead_target_step5_20m_strict_20260608_090000/depth_camera_motion_lookahead_step5_20m_strict_targets_20260608_085945.csv"
OFFSET_PATH_CSV="${OFFSET_PATH_CSV:-${DEFAULT_OFFSET_PATH}}"
TARGETS_CSV="${TARGETS_CSV:-${DEFAULT_TARGETS}}"
FRAME_ID="${FRAME_ID:-map}"
PUBLISH_HZ="${PUBLISH_HZ:-1.0}"
SETTLE_SEC="${SETTLE_SEC:-10}"
RVIZ_CONFIG="${RVIZ_CONFIG:-ros2_ws/src/zcw_cable_perception/rviz/cable_all_groups_overlay.rviz}"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="${LOG_DIR:-data/logs}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-data/screenshots}"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_all_groups_rviz_overlay_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_all_groups_rviz_overlay_${STAMP}.txt"
MARKER_LOG="${LOG_DIR}/cable_all_groups_marker_publisher_${STAMP}.log"
RVIZ_LOG="${LOG_DIR}/cable_all_groups_rviz_${STAMP}.log"
TF_LOG="${LOG_DIR}/cable_all_groups_static_tf_${STAMP}.log"
TOPIC_LIST_LOG="${LOG_DIR}/cable_all_groups_topic_list_${STAMP}.log"
FORBIDDEN_LOG="${LOG_DIR}/cable_all_groups_forbidden_topics_${STAMP}.log"
SCREENSHOT="${SCREENSHOT_DIR}/cable_all_groups_rviz_overlay_${STAMP}.png"

if [[ -z "${DISPLAY:-}" ]]; then
  echo "DISPLAY is not set; cannot capture RViz screenshot." >&2
  exit 1
fi
for file in "${OFFSET_PATH_CSV}" "${TARGETS_CSV}" "${RVIZ_CONFIG}" "scripts/publish_cable_all_groups_markers.py"; do
  if [[ ! -f "${file}" ]]; then
    echo "Required file does not exist: ${file}" >&2
    exit 1
  fi
done

mkdir -p "${LOG_DIR}" "${SCREENSHOT_DIR}" "${RESULT_DIR}"
export ROS_LOG_DIR="${LOG_DIR}/ros"
mkdir -p "${ROS_LOG_DIR}"

source /opt/ros/humble/setup.bash
set -u

cleanup() {
  for pid in "${RVIZ_PID:-}" "${TF_PID:-}" "${MARKER_PID:-}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done
}
trap cleanup EXIT

ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 world map >"${TF_LOG}" 2>&1 &
TF_PID=$!

/usr/bin/python3 scripts/publish_cable_all_groups_markers.py \
  --ros-args \
  -p "offset_path_csv:=${OFFSET_PATH_CSV}" \
  -p "targets_csv:=${TARGETS_CSV}" \
  -p "frame_id:=${FRAME_ID}" \
  -p "publish_hz:=${PUBLISH_HZ}" \
  >"${MARKER_LOG}" 2>&1 &
MARKER_PID=$!

rviz2 -d "${RVIZ_CONFIG}" >"${RVIZ_LOG}" 2>&1 &
RVIZ_PID=$!

sleep "${SETTLE_SEC}"

marker_alive=true
if ! kill -0 "${MARKER_PID}" >/dev/null 2>&1; then
  marker_alive=false
fi

ros2 topic list --no-daemon | sort >"${TOPIC_LIST_LOG}"
grep '^/fmu/in/' "${TOPIC_LIST_LOG}" >"${FORBIDDEN_LOG}" || true
if [[ -s "${FORBIDDEN_LOG}" ]]; then
  decision="rejected_cable_all_groups_rviz_overlay"
  reason="forbidden_px4_input_topic_present"
elif [[ "${marker_alive}" != "true" ]]; then
  decision="rejected_cable_all_groups_rviz_overlay"
  reason="marker_publisher_exited"
else
  decision="accepted_cable_all_groups_rviz_overlay"
  reason="all_groups_marker_overlay_captured_without_px4_inputs"
fi

set +o pipefail
RVIZ_WINDOW_ID="$(xwininfo -root -tree 2>/dev/null | awk '/RViz/ {print $1; exit}')"
set -o pipefail
if [[ -n "${RVIZ_WINDOW_ID}" ]]; then
  import -window "${RVIZ_WINDOW_ID}" "${SCREENSHOT}"
else
  import -window root "${SCREENSHOT}"
fi

screenshot_ok=false
if [[ -s "${SCREENSHOT}" ]]; then
  screenshot_ok=true
fi

group_count="$(tail -n +2 "${OFFSET_PATH_CSV}" | cut -d, -f1 | sort -u | wc -l | tr -d ' ')"
target_group_count="$(tail -n +2 "${TARGETS_CSV}" | cut -d, -f1 | sort -u | wc -l | tr -d ' ')"
if [[ "${screenshot_ok}" != "true" ]]; then
  decision="rejected_cable_all_groups_rviz_overlay"
  reason="screenshot_missing_or_empty"
fi

{
  echo "scope=cable_all_groups_rviz_overlay"
  echo "decision=${decision}"
  echo "reason=${reason}"
  echo "starts_ros=true"
  echo "starts_px4=false"
  echo "starts_gazebo=false"
  echo "starts_rviz=true"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "offset_path_csv=${OFFSET_PATH_CSV}"
  echo "targets_csv=${TARGETS_CSV}"
  echo "rviz_config=${RVIZ_CONFIG}"
  echo "marker_topic=/zcw/cable/all_groups/markers"
  echo "group_count=${group_count}"
  echo "target_group_count=${target_group_count}"
  echo "marker_alive=${marker_alive}"
  echo "screenshot=${SCREENSHOT}"
  echo "screenshot_ok=${screenshot_ok}"
  echo "marker_log=${MARKER_LOG}"
  echo "rviz_log=${RVIZ_LOG}"
  echo "tf_log=${TF_LOG}"
  echo "topic_list_log=${TOPIC_LIST_LOG}"
  echo "forbidden_log=${FORBIDDEN_LOG}"
} >"${SUMMARY_FILE}"

echo "Cable all-groups RViz overlay capture completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Screenshot: ${SCREENSHOT}"

if [[ "${decision}" != "accepted_cable_all_groups_rviz_overlay" ]]; then
  exit 1
fi
