#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_OFFSET_PATH="data/results/catenary_offset_yz_zbin2_20260603_135000/depth_camera_motion_catenary_offset_yz_zbin2_offset_path_20260603_125948.csv"
DEFAULT_TARGETS="data/results/lookahead_target_audit_20260603_165600/depth_camera_motion_lookahead_target_audit_targets_20260603_165501.csv"
OFFSET_PATH_CSV="${OFFSET_PATH_CSV:-${DEFAULT_OFFSET_PATH}}"
TARGETS_CSV="${TARGETS_CSV:-${DEFAULT_TARGETS}}"
GROUP_ID="${GROUP_ID:-y8_z20}"
FRAME_ID="${FRAME_ID:-map}"
PUBLISH_HZ="${PUBLISH_HZ:-2.0}"
MAX_CANDIDATE_JUMP_M="${MAX_CANDIDATE_JUMP_M:-5.0}"
MAX_VERTICAL_JUMP_M="${MAX_VERTICAL_JUMP_M:-2.0}"
MAX_CANDIDATE_SPEED_MPS="${MAX_CANDIDATE_SPEED_MPS:-5.0}"
MAX_DATA_AGE_SEC="${MAX_DATA_AGE_SEC:-2.0}"
SETTLE_SEC="${SETTLE_SEC:-10}"
RVIZ_CONFIG="${RVIZ_CONFIG:-ros2_ws/src/zcw_cable_perception/rviz/dry_run_overlay.rviz}"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="${LOG_DIR:-data/logs}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-data/screenshots}"
PUBLISHER_LOG="${LOG_DIR}/lookahead_dry_run_rviz_publisher_${STAMP}.log"
SAFETY_LOG="${LOG_DIR}/lookahead_dry_run_rviz_safety_${STAMP}.log"
DRY_RUN_LOG="${LOG_DIR}/lookahead_dry_run_rviz_node_${STAMP}.log"
RVIZ_LOG="${LOG_DIR}/lookahead_dry_run_rviz_${STAMP}.log"
TF_LOG="${LOG_DIR}/lookahead_dry_run_rviz_static_tf_${STAMP}.log"
TOPIC_LIST_LOG="${LOG_DIR}/lookahead_dry_run_rviz_topic_list_${STAMP}.log"
FORBIDDEN_LOG="${LOG_DIR}/lookahead_dry_run_rviz_forbidden_topics_${STAMP}.log"
SCREENSHOT="${SCREENSHOT_DIR}/lookahead_dry_run_rviz_overlay_${STAMP}.png"

if [[ -z "${DISPLAY:-}" ]]; then
  echo "DISPLAY is not set; cannot capture RViz screenshot." >&2
  exit 1
fi
if [[ ! -f "${OFFSET_PATH_CSV}" ]]; then
  echo "Offset path CSV does not exist: ${OFFSET_PATH_CSV}" >&2
  exit 1
fi
if [[ ! -f "${TARGETS_CSV}" ]]; then
  echo "Targets CSV does not exist: ${TARGETS_CSV}" >&2
  exit 1
fi
if [[ ! -f "${RVIZ_CONFIG}" ]]; then
  echo "RViz config does not exist: ${RVIZ_CONFIG}" >&2
  exit 1
fi

mkdir -p "${LOG_DIR}" "${SCREENSHOT_DIR}"
export ROS_LOG_DIR="${LOG_DIR}/ros"
mkdir -p "${ROS_LOG_DIR}"

source /opt/ros/humble/setup.bash
source "${ROOT_DIR}/install/setup.bash"
set -u

cleanup() {
  for pid in "${RVIZ_PID:-}" "${TF_PID:-}" "${DRY_RUN_PID:-}" "${SAFETY_PID:-}" "${PUBLISHER_PID:-}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done
}
trap cleanup EXIT

ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 world map >"${TF_LOG}" 2>&1 &
TF_PID=$!

ros2 run zcw_cable_perception lookahead_path_publisher \
  --ros-args \
  -p "offset_path_csv:=${OFFSET_PATH_CSV}" \
  -p "targets_csv:=${TARGETS_CSV}" \
  -p "group_id:=${GROUP_ID}" \
  -p "frame_id:=${FRAME_ID}" \
  -p "publish_hz:=${PUBLISH_HZ}" \
  >"${PUBLISHER_LOG}" 2>&1 &
PUBLISHER_PID=$!

ros2 run zcw_cable_perception lookahead_safety_monitor \
  --ros-args \
  -p "max_data_age_sec:=${MAX_DATA_AGE_SEC}" \
  >"${SAFETY_LOG}" 2>&1 &
SAFETY_PID=$!

ros2 run zcw_cable_perception lookahead_dry_run_setpoint \
  --ros-args \
  -p "max_candidate_jump_m:=${MAX_CANDIDATE_JUMP_M}" \
  -p "max_vertical_jump_m:=${MAX_VERTICAL_JUMP_M}" \
  -p "max_candidate_speed_mps:=${MAX_CANDIDATE_SPEED_MPS}" \
  -p "max_data_age_sec:=${MAX_DATA_AGE_SEC}" \
  >"${DRY_RUN_LOG}" 2>&1 &
DRY_RUN_PID=$!

rviz2 -d "${RVIZ_CONFIG}" >"${RVIZ_LOG}" 2>&1 &
RVIZ_PID=$!

sleep "${SETTLE_SEC}"

ros2 topic list --no-daemon | sort >"${TOPIC_LIST_LOG}"
grep '^/fmu/in/' "${TOPIC_LIST_LOG}" >"${FORBIDDEN_LOG}" || true
if [[ -s "${FORBIDDEN_LOG}" ]]; then
  echo "Forbidden PX4 input topics are present:" >&2
  cat "${FORBIDDEN_LOG}" >&2
  exit 1
fi

set +o pipefail
RVIZ_WINDOW_ID="$(xwininfo -root -tree 2>/dev/null | awk '/RViz/ {print $1; exit}')"
set -o pipefail
if [[ -n "${RVIZ_WINDOW_ID}" ]]; then
  import -window "${RVIZ_WINDOW_ID}" "${SCREENSHOT}"
else
  import -window root "${SCREENSHOT}"
fi

echo "Lookahead dry-run RViz overlay capture completed."
echo "Publisher log: ${PUBLISHER_LOG}"
echo "Safety log: ${SAFETY_LOG}"
echo "Dry-run log: ${DRY_RUN_LOG}"
echo "RViz log: ${RVIZ_LOG}"
echo "Static TF log: ${TF_LOG}"
echo "Topic list log: ${TOPIC_LIST_LOG}"
echo "Forbidden topic log: ${FORBIDDEN_LOG}"
echo "Screenshot: ${SCREENSHOT}"
