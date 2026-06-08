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
SETTLE_SEC="${SETTLE_SEC:-4}"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="${LOG_DIR:-data/logs}"
NODE_LOG="${LOG_DIR}/lookahead_path_publisher_${STAMP}.log"
TOPIC_LIST_LOG="${LOG_DIR}/lookahead_topic_list_${STAMP}.log"
PATH_ECHO_LOG="${LOG_DIR}/lookahead_offset_path_echo_${STAMP}.log"
TARGET_ECHO_LOG="${LOG_DIR}/lookahead_target_echo_${STAMP}.log"

if [[ ! -f "${OFFSET_PATH_CSV}" ]]; then
  echo "Offset path CSV does not exist: ${OFFSET_PATH_CSV}" >&2
  exit 1
fi
if [[ ! -f "${TARGETS_CSV}" ]]; then
  echo "Targets CSV does not exist: ${TARGETS_CSV}" >&2
  exit 1
fi

mkdir -p "${LOG_DIR}"
export ROS_LOG_DIR="${LOG_DIR}/ros"
mkdir -p "${ROS_LOG_DIR}"

source /opt/ros/humble/setup.bash
source "${ROOT_DIR}/install/setup.bash"
set -u

cleanup() {
  if [[ -n "${NODE_PID:-}" ]] && kill -0 "${NODE_PID}" >/dev/null 2>&1; then
    kill "${NODE_PID}" >/dev/null 2>&1 || true
    wait "${NODE_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

ros2 run zcw_cable_perception lookahead_path_publisher \
  --ros-args \
  -p "offset_path_csv:=${OFFSET_PATH_CSV}" \
  -p "targets_csv:=${TARGETS_CSV}" \
  -p "group_id:=${GROUP_ID}" \
  -p "frame_id:=${FRAME_ID}" \
  -p "publish_hz:=${PUBLISH_HZ}" \
  >"${NODE_LOG}" 2>&1 &
NODE_PID=$!

sleep "${SETTLE_SEC}"

ros2 topic list --no-daemon | sort >"${TOPIC_LIST_LOG}"
grep -q '^/zcw/cable/offset_path$' "${TOPIC_LIST_LOG}"
grep -q '^/zcw/cable/lookahead_target$' "${TOPIC_LIST_LOG}"

timeout 8s ros2 topic echo --once /zcw/cable/offset_path >"${PATH_ECHO_LOG}"
timeout 8s ros2 topic echo --once /zcw/cable/lookahead_target >"${TARGET_ECHO_LOG}"

echo "Lookahead topic publish smoke completed."
echo "Node log: ${NODE_LOG}"
echo "Topic list log: ${TOPIC_LIST_LOG}"
echo "Offset path echo log: ${PATH_ECHO_LOG}"
echo "Lookahead target echo log: ${TARGET_ECHO_LOG}"
