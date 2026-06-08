#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_OFFSET_PATH="data/results/catenary_offset_yz_zbin2_step5_20260608_000000/depth_camera_motion_catenary_offset_yz_zbin2_step5_offset_path_20260608_085655.csv"
DEFAULT_TARGETS="data/results/lookahead_target_step5_20m_strict_20260608_090000/depth_camera_motion_lookahead_step5_20m_strict_targets_20260608_085945.csv"
OFFSET_PATH_CSV="${OFFSET_PATH_CSV:-${DEFAULT_OFFSET_PATH}}"
TARGETS_CSV="${TARGETS_CSV:-${DEFAULT_TARGETS}}"
GROUP_ID="${GROUP_ID:-y8_z20}"
FRAME_ID="${FRAME_ID:-map}"
PUBLISH_HZ="${PUBLISH_HZ:-2.0}"
SETTLE_SEC="${SETTLE_SEC:-8}"
RVIZ_CONFIG="${RVIZ_CONFIG:-ros2_ws/src/zcw_cable_perception/rviz/lookahead_overlay.rviz}"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="${LOG_DIR:-data/logs}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-data/screenshots}"
NODE_LOG="${LOG_DIR}/lookahead_rviz_publisher_${STAMP}.log"
RVIZ_LOG="${LOG_DIR}/lookahead_rviz_${STAMP}.log"
TF_LOG="${LOG_DIR}/lookahead_rviz_static_tf_${STAMP}.log"
SCREENSHOT="${SCREENSHOT_DIR}/lookahead_rviz_overlay_${STAMP}.png"

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
  if [[ -n "${RVIZ_PID:-}" ]] && kill -0 "${RVIZ_PID}" >/dev/null 2>&1; then
    kill "${RVIZ_PID}" >/dev/null 2>&1 || true
    wait "${RVIZ_PID}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${TF_PID:-}" ]] && kill -0 "${TF_PID}" >/dev/null 2>&1; then
    kill "${TF_PID}" >/dev/null 2>&1 || true
    wait "${TF_PID}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${NODE_PID:-}" ]] && kill -0 "${NODE_PID}" >/dev/null 2>&1; then
    kill "${NODE_PID}" >/dev/null 2>&1 || true
    wait "${NODE_PID}" >/dev/null 2>&1 || true
  fi
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
  >"${NODE_LOG}" 2>&1 &
NODE_PID=$!

rviz2 -d "${RVIZ_CONFIG}" >"${RVIZ_LOG}" 2>&1 &
RVIZ_PID=$!

sleep "${SETTLE_SEC}"
set +o pipefail
RVIZ_WINDOW_ID="$(xwininfo -root -tree 2>/dev/null | awk '/RViz/ {print $1; exit}')"
set -o pipefail
if [[ -n "${RVIZ_WINDOW_ID}" ]]; then
  import -window "${RVIZ_WINDOW_ID}" "${SCREENSHOT}"
else
  import -window root "${SCREENSHOT}"
fi

echo "Lookahead RViz overlay capture completed."
echo "Publisher log: ${NODE_LOG}"
echo "RViz log: ${RVIZ_LOG}"
echo "Static TF log: ${TF_LOG}"
echo "Screenshot: ${SCREENSHOT}"
