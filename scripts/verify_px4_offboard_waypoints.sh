#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_BIN="${AGENT_BIN:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean/MicroXRCEAgent}"
AGENT_LIB_DIR="${AGENT_LIB_DIR:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean}"
PX4_SCRIPT="${PX4_SCRIPT:-${ROOT_DIR}/scripts/run_px4_gazebo_classic_headless.sh}"
PX4_TIMEOUT_SEC="${PX4_TIMEOUT_SEC:-90}"
VERIFY_TIMEOUT_SEC="${VERIFY_TIMEOUT_SEC:-55}"
OFFBOARD_RUN_SEC="${OFFBOARD_RUN_SEC:-36}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
STAMP="$(date +%Y%m%d_%H%M%S)"
AGENT_LOG="${AGENT_LOG:-${LOG_DIR}/waypoints_agent_${STAMP}.log}"
PX4_LOG="${PX4_LOG:-${LOG_DIR}/waypoints_px4_${STAMP}.log}"
PX4_WRAPPER_LOG="${PX4_WRAPPER_LOG:-${PX4_LOG}.wrapper}"
OFFBOARD_LOG="${OFFBOARD_LOG:-${LOG_DIR}/waypoints_control_${STAMP}.log}"
STATUS_LOG="${STATUS_LOG:-${LOG_DIR}/waypoints_vehicle_status_${STAMP}.log}"
LOCAL_POSITION_LOG="${LOCAL_POSITION_LOG:-${LOG_DIR}/waypoints_vehicle_local_position_${STAMP}.log}"
OFFBOARD_LAUNCH_PACKAGE="${OFFBOARD_LAUNCH_PACKAGE:-zcw_bringup}"
OFFBOARD_LAUNCH_FILE="${OFFBOARD_LAUNCH_FILE:-single_vehicle_waypoint_sequence.launch.py}"

agent_pid=""
px4_pid=""
offboard_pid=""

cleanup() {
  if [[ -n "${offboard_pid}" ]]; then
    kill -TERM -- "-${offboard_pid}" >/dev/null 2>&1 || true
    wait "${offboard_pid}" >/dev/null 2>&1 || true
  fi

  if [[ -n "${px4_pid}" ]]; then
    kill -TERM -- "-${px4_pid}" >/dev/null 2>&1 || true
    wait "${px4_pid}" >/dev/null 2>&1 || true
  fi

  if [[ -n "${agent_pid}" ]]; then
    kill -TERM -- "-${agent_pid}" >/dev/null 2>&1 || true
    wait "${agent_pid}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ ! -x "${AGENT_BIN}" ]]; then
  echo "MicroXRCEAgent not found: ${AGENT_BIN}" >&2
  exit 1
fi

if [[ ! -x "${PX4_SCRIPT}" ]]; then
  echo "PX4 headless script not found: ${PX4_SCRIPT}" >&2
  exit 1
fi

mkdir -p "${LOG_DIR}"

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

if ! grep -q "running.*port: 8888" "${AGENT_LOG}"; then
  echo "MicroXRCEAgent did not report UDP port 8888 readiness." >&2
  tail -n 80 "${AGENT_LOG}" >&2
  exit 1
fi

setsid env \
  TIMEOUT_SEC="${PX4_TIMEOUT_SEC}" \
  LOG_FILE="${PX4_LOG}" \
  "${PX4_SCRIPT}" >"${PX4_WRAPPER_LOG}" 2>&1 &
px4_pid=$!

for _ in $(seq 1 "${VERIFY_TIMEOUT_SEC}"); do
  if [[ -f "${PX4_LOG}" ]] &&
     grep -q "Startup script returned successfully" "${PX4_LOG}"; then
    set +e
    timeout 6s env -i \
      HOME="${HOME:-/home/travis}" \
      USER="${USER:-travis}" \
      PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
      /bin/bash -c "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && ros2 topic list" >"${STATUS_LOG}.topics" 2>&1
    topic_status=$?
    set -e

    if [[ "${topic_status}" -eq 0 ]] &&
       grep -q "/fmu/out/vehicle_status" "${STATUS_LOG}.topics" &&
       grep -q "/fmu/out/vehicle_local_position" "${STATUS_LOG}.topics"; then
      break
    fi
  fi

  sleep 1
done

if ! [[ -f "${STATUS_LOG}.topics" ]] ||
   ! grep -q "/fmu/out/vehicle_local_position" "${STATUS_LOG}.topics"; then
  echo "PX4 ROS 2 bridge did not expose required waypoint topics." >&2
  tail -n 80 "${AGENT_LOG}" >&2 || true
  tail -n 80 "${PX4_LOG}" >&2 || true
  exit 1
fi

setsid env -i \
  HOME="${HOME:-/home/travis}" \
  USER="${USER:-travis}" \
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  /bin/bash -c "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && ros2 launch '${OFFBOARD_LAUNCH_PACKAGE}' '${OFFBOARD_LAUNCH_FILE}'" >"${OFFBOARD_LOG}" 2>&1 &
offboard_pid=$!

sleep "${OFFBOARD_RUN_SEC}"

timeout 8s env -i \
  HOME="${HOME:-/home/travis}" \
  USER="${USER:-travis}" \
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  /bin/bash -c "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && ros2 topic echo --once /fmu/out/vehicle_status" >"${STATUS_LOG}" 2>&1

timeout 8s env -i \
  HOME="${HOME:-/home/travis}" \
  USER="${USER:-travis}" \
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  /bin/bash -c "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && ros2 topic echo --once /fmu/out/vehicle_local_position" >"${LOCAL_POSITION_LOG}" 2>&1

if ! grep -q "arming_state: 2" "${STATUS_LOG}" ||
   ! grep -q "nav_state: 14" "${STATUS_LOG}"; then
  echo "PX4 did not stay in armed Offboard state." >&2
  tail -n 80 "${OFFBOARD_LOG}" >&2 || true
  tail -n 80 "${STATUS_LOG}" >&2 || true
  exit 1
fi

if ! grep -q "Advancing to waypoint" "${OFFBOARD_LOG}"; then
  echo "Waypoint node did not report waypoint advancement." >&2
  tail -n 120 "${OFFBOARD_LOG}" >&2 || true
  tail -n 80 "${LOCAL_POSITION_LOG}" >&2 || true
  exit 1
fi

echo "PX4 Offboard waypoint baseline verified."
echo "Agent log: ${AGENT_LOG}"
echo "PX4 log: ${PX4_LOG}"
echo "Waypoint log: ${OFFBOARD_LOG}"
echo "Vehicle status log: ${STATUS_LOG}"
echo "Vehicle local position log: ${LOCAL_POSITION_LOG}"
