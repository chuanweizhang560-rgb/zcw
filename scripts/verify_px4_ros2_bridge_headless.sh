#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_BIN="${AGENT_BIN:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean/MicroXRCEAgent}"
AGENT_LIB_DIR="${AGENT_LIB_DIR:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean}"
PX4_SCRIPT="${PX4_SCRIPT:-${ROOT_DIR}/scripts/run_px4_gazebo_classic_headless.sh}"
PX4_TIMEOUT_SEC="${PX4_TIMEOUT_SEC:-55}"
VERIFY_TIMEOUT_SEC="${VERIFY_TIMEOUT_SEC:-40}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
STAMP="$(date +%Y%m%d_%H%M%S)"
AGENT_LOG="${AGENT_LOG:-${LOG_DIR}/microxrce_agent_${STAMP}.log}"
PX4_LOG="${PX4_LOG:-${LOG_DIR}/px4_ros2_bridge_px4_${STAMP}.log}"
PX4_WRAPPER_LOG="${PX4_WRAPPER_LOG:-${PX4_LOG}.wrapper}"
TOPICS_LOG="${TOPICS_LOG:-${LOG_DIR}/px4_ros2_topics_${STAMP}.log}"

agent_pid=""
px4_pid=""

cleanup() {
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
      /bin/bash -c "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && ros2 topic list" >"${TOPICS_LOG}" 2>&1
    topic_status=$?
    set -e

    if [[ "${topic_status}" -eq 0 ]] &&
       grep -q "/fmu/out/vehicle_status" "${TOPICS_LOG}"; then
      echo "PX4 ROS 2 bridge verified."
      echo "Agent log: ${AGENT_LOG}"
      echo "PX4 log: ${PX4_LOG}"
      echo "Topics log: ${TOPICS_LOG}"
      exit 0
    fi
  fi

  sleep 1
done

echo "PX4 ROS 2 bridge verification failed." >&2
echo "Agent log: ${AGENT_LOG}" >&2
tail -n 80 "${AGENT_LOG}" >&2 || true
echo "PX4 log: ${PX4_LOG}" >&2
tail -n 80 "${PX4_LOG}" >&2 || true
echo "Topics log: ${TOPICS_LOG}" >&2
tail -n 80 "${TOPICS_LOG}" >&2 || true
exit 1
