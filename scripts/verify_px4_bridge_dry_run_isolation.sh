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
MAX_DATA_AGE_SEC="${MAX_DATA_AGE_SEC:-2.0}"
SETTLE_SEC="${SETTLE_SEC:-6}"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="${LOG_DIR:-data/logs}"
PUBLISHER_LOG="${LOG_DIR}/px4_bridge_dry_run_publisher_${STAMP}.log"
SAFETY_LOG="${LOG_DIR}/px4_bridge_dry_run_safety_${STAMP}.log"
DRY_RUN_LOG="${LOG_DIR}/px4_bridge_dry_run_candidate_${STAMP}.log"
BRIDGE_LOG="${LOG_DIR}/px4_bridge_dry_run_node_${STAMP}.log"
TOPIC_LIST_LOG="${LOG_DIR}/px4_bridge_dry_run_topic_list_${STAMP}.log"
FORBIDDEN_LOG="${LOG_DIR}/px4_bridge_dry_run_forbidden_topics_${STAMP}.log"
STATE_ECHO_LOG="${LOG_DIR}/px4_bridge_dry_run_state_echo_${STAMP}.log"
NED_ECHO_LOG="${LOG_DIR}/px4_bridge_dry_run_ned_echo_${STAMP}.log"

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
  for pid in "${BRIDGE_PID:-}" "${DRY_RUN_PID:-}" "${SAFETY_PID:-}" "${PUBLISHER_PID:-}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}" >/dev/null 2>&1 || true
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done
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
  -p "max_data_age_sec:=${MAX_DATA_AGE_SEC}" \
  >"${SAFETY_LOG}" 2>&1 &
SAFETY_PID=$!

ros2 run zcw_cable_perception lookahead_dry_run_setpoint \
  --ros-args \
  -p "max_data_age_sec:=${MAX_DATA_AGE_SEC}" \
  >"${DRY_RUN_LOG}" 2>&1 &
DRY_RUN_PID=$!

ros2 run zcw_px4_baseline cable_px4_bridge_dry_run \
  --ros-args \
  -p "max_candidate_age_sec:=${MAX_DATA_AGE_SEC}" \
  -p "max_state_age_sec:=${MAX_DATA_AGE_SEC}" \
  >"${BRIDGE_LOG}" 2>&1 &
BRIDGE_PID=$!

sleep "${SETTLE_SEC}"

ros2 topic list --no-daemon | sort >"${TOPIC_LIST_LOG}"
grep -q '^/zcw/cable/px4_bridge/state$' "${TOPIC_LIST_LOG}"
grep -q '^/zcw/cable/px4_bridge/ned_setpoint_dry_run$' "${TOPIC_LIST_LOG}"

grep '^/fmu/in/' "${TOPIC_LIST_LOG}" >"${FORBIDDEN_LOG}" || true
if [[ -s "${FORBIDDEN_LOG}" ]]; then
  echo "Forbidden PX4 input topics are present:" >&2
  cat "${FORBIDDEN_LOG}" >&2
  exit 1
fi

state_ok=0
ned_ok=0
for _ in $(seq 1 10); do
  timeout 3s ros2 topic echo --full-length --once /zcw/cable/px4_bridge/state >"${STATE_ECHO_LOG}" || true
  timeout 3s ros2 topic echo --once /zcw/cable/px4_bridge/ned_setpoint_dry_run >"${NED_ECHO_LOG}" || true
  if grep -q 'DRY_RUN_READY' "${STATE_ECHO_LOG}" &&
     grep -q 'publishes_fmu_in=false' "${STATE_ECHO_LOG}"; then
    state_ok=1
  fi
  if grep -q 'frame_id: px4_local_ned_dry_run' "${NED_ECHO_LOG}" &&
     grep -q 'point:' "${NED_ECHO_LOG}"; then
    ned_ok=1
  fi
  if [[ "${state_ok}" -eq 1 && "${ned_ok}" -eq 1 ]]; then
    break
  fi
  sleep 1
done

grep -q 'DRY_RUN_READY' "${STATE_ECHO_LOG}"
grep -q 'publishes_fmu_in=false' "${STATE_ECHO_LOG}"
grep -q 'map_to_ned=debug_x_y_neg_z' "${STATE_ECHO_LOG}"
grep -q 'frame_id: px4_local_ned_dry_run' "${NED_ECHO_LOG}"
grep -q 'point:' "${NED_ECHO_LOG}"

echo "PX4 bridge dry-run isolation smoke completed."
echo "Publisher log: ${PUBLISHER_LOG}"
echo "Safety log: ${SAFETY_LOG}"
echo "Dry-run candidate log: ${DRY_RUN_LOG}"
echo "Bridge log: ${BRIDGE_LOG}"
echo "Topic list log: ${TOPIC_LIST_LOG}"
echo "Forbidden topic log: ${FORBIDDEN_LOG}"
echo "Bridge state echo log: ${STATE_ECHO_LOG}"
echo "NED dry-run echo log: ${NED_ECHO_LOG}"
