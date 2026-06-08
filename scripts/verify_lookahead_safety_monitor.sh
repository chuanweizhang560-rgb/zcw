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
MIN_PATH_POINTS="${MIN_PATH_POINTS:-3}"
MAX_TARGET_TO_PATH_M="${MAX_TARGET_TO_PATH_M:-2.0}"
MAX_TARGET_JUMP_M="${MAX_TARGET_JUMP_M:-25.0}"
MAX_DATA_AGE_SEC="${MAX_DATA_AGE_SEC:-3.0}"
SETTLE_SEC="${SETTLE_SEC:-4}"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="${LOG_DIR:-data/logs}"
PUBLISHER_LOG="${LOG_DIR}/lookahead_safety_publisher_${STAMP}.log"
MONITOR_LOG="${LOG_DIR}/lookahead_safety_monitor_${STAMP}.log"
STATE_ECHO_LOG="${LOG_DIR}/lookahead_tracking_state_echo_${STAMP}.log"
GATE_ECHO_LOG="${LOG_DIR}/lookahead_safety_gate_echo_${STAMP}.log"
TOPIC_LIST_LOG="${LOG_DIR}/lookahead_safety_topic_list_${STAMP}.log"

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
  if [[ -n "${MONITOR_PID:-}" ]] && kill -0 "${MONITOR_PID}" >/dev/null 2>&1; then
    kill "${MONITOR_PID}" >/dev/null 2>&1 || true
    wait "${MONITOR_PID}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${PUBLISHER_PID:-}" ]] && kill -0 "${PUBLISHER_PID}" >/dev/null 2>&1; then
    kill "${PUBLISHER_PID}" >/dev/null 2>&1 || true
    wait "${PUBLISHER_PID}" >/dev/null 2>&1 || true
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
  >"${PUBLISHER_LOG}" 2>&1 &
PUBLISHER_PID=$!

ros2 run zcw_cable_perception lookahead_safety_monitor \
  --ros-args \
  -p "min_path_points:=${MIN_PATH_POINTS}" \
  -p "max_target_to_path_m:=${MAX_TARGET_TO_PATH_M}" \
  -p "max_target_jump_m:=${MAX_TARGET_JUMP_M}" \
  -p "max_data_age_sec:=${MAX_DATA_AGE_SEC}" \
  >"${MONITOR_LOG}" 2>&1 &
MONITOR_PID=$!

sleep "${SETTLE_SEC}"

ros2 topic list --no-daemon | sort >"${TOPIC_LIST_LOG}"
grep -q '^/zcw/cable/tracking_state$' "${TOPIC_LIST_LOG}"
grep -q '^/zcw/cable/safety_gate$' "${TOPIC_LIST_LOG}"

state_ok=0
gate_ok=0
for _ in $(seq 1 10); do
  timeout 3s ros2 topic echo --once /zcw/cable/tracking_state >"${STATE_ECHO_LOG}" || true
  timeout 3s ros2 topic echo --once /zcw/cable/safety_gate >"${GATE_ECHO_LOG}" || true
  if grep -q 'TRACK_READY' "${STATE_ECHO_LOG}"; then
    state_ok=1
  fi
  if grep -q 'data: true' "${GATE_ECHO_LOG}"; then
    gate_ok=1
  fi
  if [[ "${state_ok}" -eq 1 && "${gate_ok}" -eq 1 ]]; then
    break
  fi
  sleep 1
done

grep -q 'TRACK_READY' "${STATE_ECHO_LOG}"
grep -q 'data: true' "${GATE_ECHO_LOG}"

echo "Lookahead safety monitor smoke completed."
echo "Publisher log: ${PUBLISHER_LOG}"
echo "Monitor log: ${MONITOR_LOG}"
echo "Topic list log: ${TOPIC_LIST_LOG}"
echo "Tracking state echo log: ${STATE_ECHO_LOG}"
echo "Safety gate echo log: ${GATE_ECHO_LOG}"
