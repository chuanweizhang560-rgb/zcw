#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

AGENT_BIN="${AGENT_BIN:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean/MicroXRCEAgent}"
AGENT_LIB_DIR="${AGENT_LIB_DIR:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean}"
PX4_SCRIPT="${PX4_SCRIPT:-${ROOT_DIR}/scripts/run_px4_aerialcore_world_headless.sh}"
DEFAULT_OFFSET_PATH="data/results/catenary_offset_yz_zbin2_20260603_135000/depth_camera_motion_catenary_offset_yz_zbin2_offset_path_20260603_125948.csv"
DEFAULT_TARGETS="data/results/lookahead_target_audit_20260603_165600/depth_camera_motion_lookahead_target_audit_targets_20260603_165501.csv"
OFFSET_PATH_CSV="${OFFSET_PATH_CSV:-${DEFAULT_OFFSET_PATH}}"
TARGETS_CSV="${TARGETS_CSV:-${DEFAULT_TARGETS}}"
GROUP_ID="${GROUP_ID:-y8_z20}"
FRAME_ID="${FRAME_ID:-map}"
PUBLISH_HZ="${PUBLISH_HZ:-2.0}"
MAX_DATA_AGE_SEC="${MAX_DATA_AGE_SEC:-2.0}"
MAX_DEBUG_XY_ERROR_M="${MAX_DEBUG_XY_ERROR_M:-2.5}"
MAX_DEBUG_Z_ERROR_M="${MAX_DEBUG_Z_ERROR_M:-0.5}"
PX4_TIMEOUT_SEC="${PX4_TIMEOUT_SEC:-120}"
VERIFY_TIMEOUT_SEC="${VERIFY_TIMEOUT_SEC:-80}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${RESULT_ROOT}/px4_gazebo_frame_alignment_${STAMP}"

AGENT_LOG="${LOG_DIR}/px4_gazebo_frame_alignment_agent_${STAMP}.log"
PX4_LOG="${LOG_DIR}/px4_gazebo_frame_alignment_px4_${STAMP}.log"
PX4_WRAPPER_LOG="${PX4_LOG}.wrapper"
PUBLISHER_LOG="${LOG_DIR}/px4_gazebo_frame_alignment_publisher_${STAMP}.log"
SAFETY_LOG="${LOG_DIR}/px4_gazebo_frame_alignment_safety_${STAMP}.log"
DRY_RUN_LOG="${LOG_DIR}/px4_gazebo_frame_alignment_dry_run_${STAMP}.log"
BRIDGE_LOG="${LOG_DIR}/px4_gazebo_frame_alignment_bridge_${STAMP}.log"
AUDIT_LOG="${LOG_DIR}/px4_gazebo_frame_alignment_audit_${STAMP}.log"
TOPIC_LIST_LOG="${LOG_DIR}/px4_gazebo_frame_alignment_topic_list_${STAMP}.log"
TYPES_LOG="${LOG_DIR}/px4_gazebo_frame_alignment_types_${STAMP}.log"
FORBIDDEN_LOG="${LOG_DIR}/px4_gazebo_frame_alignment_forbidden_topics_${STAMP}.log"
FORBIDDEN_PUBLISHERS_LOG="${LOG_DIR}/px4_gazebo_frame_alignment_forbidden_publishers_${STAMP}.log"
SUMMARY_FILE="${RESULT_DIR}/px4_gazebo_frame_alignment_${STAMP}.txt"

agent_pid=""
px4_pid=""
publisher_pid=""
safety_pid=""
dry_run_pid=""
bridge_pid=""

cleanup() {
  local pid=""
  for pid in \
    "${bridge_pid}" \
    "${dry_run_pid}" \
    "${safety_pid}" \
    "${publisher_pid}" \
    "${px4_pid}" \
    "${agent_pid}"
  do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      pkill -TERM -P "${pid}" >/dev/null 2>&1 || true
      kill -TERM "${pid}" >/dev/null 2>&1 || true
    fi
  done

  pkill -TERM -f "${ROOT_DIR}.*/[p]ower_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/[p]x4" >/dev/null 2>&1 || true
  sleep 2
  for pid in \
    "${bridge_pid}" \
    "${dry_run_pid}" \
    "${safety_pid}" \
    "${publisher_pid}" \
    "${px4_pid}" \
    "${agent_pid}"
  do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      pkill -KILL -P "${pid}" >/dev/null 2>&1 || true
      kill -KILL "${pid}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${pid}" ]]; then
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done
  pkill -KILL -f "${ROOT_DIR}.*/[p]ower_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/[p]x4" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ ! -x "${AGENT_BIN}" ]]; then
  echo "MicroXRCEAgent not found: ${AGENT_BIN}" >&2
  exit 1
fi
if [[ ! -x "${PX4_SCRIPT}" ]]; then
  echo "PX4 AerialCore script not found: ${PX4_SCRIPT}" >&2
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

mkdir -p "${LOG_DIR}" "${RESULT_DIR}" "${LOG_DIR}/ros"
export ROS_LOG_DIR="${LOG_DIR}/ros"

setsid env -i \
  HOME="${HOME:-/home/travis}" \
  USER="${USER:-travis}" \
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  LD_LIBRARY_PATH="${AGENT_LIB_DIR}:/opt/ros/humble/lib" \
  "${AGENT_BIN}" udp4 -p 8888 >"${AGENT_LOG}" 2>&1 &
agent_pid=$!

for _ in $(seq 1 10); do
  if grep -q "running.*port: 8888" "${AGENT_LOG}"; then
    break
  fi
  sleep 1
done
grep -q "running.*port: 8888" "${AGENT_LOG}"

setsid env \
  ROS_VERSION=2 \
  PX4_DIRECT_MODEL=1 \
  PX4_HEADLESS=1 \
  PX4_SYS_AUTOSTART=10015 \
  PX4_MODEL=iris_depth_camera \
  AERIALCORE_WORLD=danube_wires \
  TIMEOUT_SEC="${PX4_TIMEOUT_SEC}" \
  LOG_FILE="${PX4_LOG}" \
  "${PX4_SCRIPT}" >"${PX4_WRAPPER_LOG}" 2>&1 &
px4_pid=$!

for _ in $(seq 1 "${VERIFY_TIMEOUT_SEC}"); do
  if [[ -f "${PX4_LOG}" ]] &&
     grep -q "Simulator connected on TCP port 4560" "${PX4_LOG}" &&
     grep -q "Startup script returned successfully" "${PX4_LOG}"; then
    break
  fi
  sleep 1
done
if ! grep -q "Simulator connected on TCP port 4560" "${PX4_LOG}" ||
   ! grep -q "Startup script returned successfully" "${PX4_LOG}"; then
  echo "PX4/Gazebo did not reach ready state." >&2
  tail -n 120 "${PX4_LOG}" >&2 || true
  exit 1
fi

set +u
source /opt/ros/humble/setup.bash
source "${ROOT_DIR}/install/setup.bash"
set -u

ros2 run zcw_cable_perception lookahead_path_publisher \
  --ros-args \
  -p "offset_path_csv:=${OFFSET_PATH_CSV}" \
  -p "targets_csv:=${TARGETS_CSV}" \
  -p "group_id:=${GROUP_ID}" \
  -p "frame_id:=${FRAME_ID}" \
  -p "publish_hz:=${PUBLISH_HZ}" \
  >"${PUBLISHER_LOG}" 2>&1 &
publisher_pid=$!

ros2 run zcw_cable_perception lookahead_safety_monitor \
  --ros-args \
  -p "max_data_age_sec:=${MAX_DATA_AGE_SEC}" \
  >"${SAFETY_LOG}" 2>&1 &
safety_pid=$!

ros2 run zcw_cable_perception lookahead_dry_run_setpoint \
  --ros-args \
  -p "max_data_age_sec:=${MAX_DATA_AGE_SEC}" \
  >"${DRY_RUN_LOG}" 2>&1 &
dry_run_pid=$!

ros2 run zcw_px4_baseline cable_px4_bridge_dry_run \
  --ros-args \
  -p "max_candidate_age_sec:=${MAX_DATA_AGE_SEC}" \
  -p "max_state_age_sec:=${MAX_DATA_AGE_SEC}" \
  >"${BRIDGE_LOG}" 2>&1 &
bridge_pid=$!

for _ in $(seq 1 "${VERIFY_TIMEOUT_SEC}"); do
  ros2 topic list --no-daemon | sort >"${TOPIC_LIST_LOG}" || true
  : >"${TYPES_LOG}"
  while IFS= read -r topic; do
    [[ -z "${topic}" ]] && continue
    echo "${topic} $(ros2 topic type "${topic}" 2>/dev/null || true)" >>"${TYPES_LOG}"
  done <"${TOPIC_LIST_LOG}"

  if grep -q "^/fmu/out/vehicle_local_position px4_msgs/msg/VehicleLocalPosition$" "${TYPES_LOG}" &&
     grep -q "^/zcw/depth_camera/pose nav_msgs/msg/Odometry$" "${TYPES_LOG}" &&
     grep -q "^/zcw/cable/dry_run/candidate_setpoint geometry_msgs/msg/PointStamped$" "${TYPES_LOG}" &&
     grep -q "^/zcw/cable/px4_bridge/ned_setpoint_dry_run geometry_msgs/msg/PointStamped$" "${TYPES_LOG}"; then
    break
  fi
  sleep 1
done

grep -q "^/fmu/out/vehicle_local_position px4_msgs/msg/VehicleLocalPosition$" "${TYPES_LOG}"
grep -q "^/zcw/depth_camera/pose nav_msgs/msg/Odometry$" "${TYPES_LOG}"
grep -q "^/zcw/cable/dry_run/candidate_setpoint geometry_msgs/msg/PointStamped$" "${TYPES_LOG}"
grep -q "^/zcw/cable/px4_bridge/ned_setpoint_dry_run geometry_msgs/msg/PointStamped$" "${TYPES_LOG}"

grep '^/fmu/in/' "${TOPIC_LIST_LOG}" >"${FORBIDDEN_LOG}" || true
: >"${FORBIDDEN_PUBLISHERS_LOG}"
while IFS= read -r topic; do
  [[ -z "${topic}" ]] && continue
  info="$(ros2 topic info "${topic}" --verbose 2>/dev/null || true)"
  echo "### ${topic}" >>"${FORBIDDEN_PUBLISHERS_LOG}"
  echo "${info}" >>"${FORBIDDEN_PUBLISHERS_LOG}"
  if ! grep -q "Publisher count: 0" <<<"${info}"; then
    echo "Forbidden PX4 input topic has a local publisher: ${topic}" >&2
    echo "${info}" >&2
    exit 1
  fi
done <"${FORBIDDEN_LOG}"

ros2 run zcw_px4_baseline px4_gazebo_frame_alignment_audit \
  --ros-args \
  -p "output_file:=${SUMMARY_FILE}" \
  -p "max_age_sec:=${MAX_DATA_AGE_SEC}" \
  -p "max_debug_xy_error_m:=${MAX_DEBUG_XY_ERROR_M}" \
  -p "max_debug_z_error_m:=${MAX_DEBUG_Z_ERROR_M}" \
  >"${AUDIT_LOG}" 2>&1

grep -q "decision=accepted_readonly_frame_sample_smoke" "${SUMMARY_FILE}"
grep -q "publishes_fmu_in=false" "${SUMMARY_FILE}"
grep -q "debug_transform_smoke_ok=true" "${SUMMARY_FILE}"
grep -q "bridge_ready=true" "${SUMMARY_FILE}"

cleanup
agent_pid=""
px4_pid=""
publisher_pid=""
safety_pid=""
dry_run_pid=""
bridge_pid=""
sleep 2

if ps -C gzserver -C gzclient -C px4 -C gazebo -C MicroXRCEAgent -o pid=,comm=,args= | grep -q .; then
  echo "Residual simulation process detected after cleanup:" >&2
  ps -C gzserver -C gzclient -C px4 -C gazebo -C MicroXRCEAgent -o pid,comm,args >&2
  exit 1
fi

echo "PX4/Gazebo read-only frame alignment smoke completed."
echo "Agent log: ${AGENT_LOG}"
echo "PX4/Gazebo log: ${PX4_LOG}"
echo "Publisher log: ${PUBLISHER_LOG}"
echo "Safety log: ${SAFETY_LOG}"
echo "Dry-run log: ${DRY_RUN_LOG}"
echo "Bridge log: ${BRIDGE_LOG}"
echo "Audit log: ${AUDIT_LOG}"
echo "Topic list log: ${TOPIC_LIST_LOG}"
echo "Types log: ${TYPES_LOG}"
echo "Forbidden topic log: ${FORBIDDEN_LOG}"
echo "Forbidden publisher log: ${FORBIDDEN_PUBLISHERS_LOG}"
echo "Summary: ${SUMMARY_FILE}"
