#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
STAMP="$(date +%Y%m%d_%H%M%S)"
PX4_LOG="${LOG_DIR}/foggy_lidar_px4_${STAMP}.log"
TOPICS_LOG="${LOG_DIR}/foggy_lidar_topics_${STAMP}.log"
TYPE_LOG="${LOG_DIR}/foggy_lidar_type_${STAMP}.log"
INFO_LOG="${LOG_DIR}/foggy_lidar_info_${STAMP}.log"
SAMPLE_LOG="${LOG_DIR}/foggy_lidar_sample_${STAMP}.log"
HZ_LOG="${LOG_DIR}/foggy_lidar_hz_${STAMP}.log"
TOPIC="${FOGGY_LIDAR_TOPIC:-/zcw/foggy_lidar/points}"
runner_pid=""

cleanup() {
  if [[ -n "${runner_pid}" ]]; then
    kill -TERM -- "-${runner_pid}" >/dev/null 2>&1 || true
    sleep 2
    kill -KILL -- "-${runner_pid}" >/dev/null 2>&1 || true
    wait "${runner_pid}" >/dev/null 2>&1 || true
  fi
  pkill -TERM -f "make px4_sitl gazebo-classic_iris_foggy_lidar" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
  sleep 1
  pkill -KILL -f "make px4_sitl gazebo-classic_iris_foggy_lidar" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "${LOG_DIR}"

setsid env \
  ROS_VERSION=2 \
  PX4_MODEL=iris_foggy_lidar \
  AERIALCORE_WORLD=danube_wires \
  TIMEOUT_SEC="${PX4_TIMEOUT_SEC:-180}" \
  LOG_FILE="${PX4_LOG}" \
  "${ROOT_DIR}/scripts/run_px4_aerialcore_world_headless.sh" >/dev/null 2>&1 &
runner_pid=$!

for _ in $(seq 1 "${PX4_WAIT_SEC:-90}"); do
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
  tail -n 80 "${PX4_LOG}" >&2 || true
  exit 1
fi

set +u
source /opt/ros/humble/setup.bash
set -u

for _ in $(seq 1 "${TOPIC_WAIT_SEC:-45}"); do
  ros2 topic list --no-daemon | sort >"${TOPICS_LOG}" || true
  if grep -qx "${TOPIC}" "${TOPICS_LOG}"; then
    break
  fi
  sleep 1
done

if ! grep -qx "${TOPIC}" "${TOPICS_LOG}"; then
  echo "PointCloud2 topic not found: ${TOPIC}" >&2
  cat "${TOPICS_LOG}" >&2 || true
  exit 1
fi

ros2 topic type "${TOPIC}" >"${TYPE_LOG}"
if ! grep -qx "sensor_msgs/msg/PointCloud2" "${TYPE_LOG}"; then
  echo "Unexpected topic type for ${TOPIC}: $(cat "${TYPE_LOG}")" >&2
  exit 1
fi

ros2 topic info "${TOPIC}" --verbose >"${INFO_LOG}"
timeout 20s ros2 topic echo --qos-reliability reliable --qos-durability volatile --once "${TOPIC}" >"${SAMPLE_LOG}"
timeout 12s ros2 topic hz "${TOPIC}" --window 3 >"${HZ_LOG}" || true

if ! grep -q "^width:" "${SAMPLE_LOG}" ||
   ! grep -q "^point_step:" "${SAMPLE_LOG}" ||
   ! grep -q "^data:" "${SAMPLE_LOG}"; then
  echo "PointCloud2 sample did not contain expected fields." >&2
  sed -n '1,120p' "${SAMPLE_LOG}" >&2 || true
  exit 1
fi

if ! grep -q "average rate:" "${HZ_LOG}"; then
  echo "PointCloud2 hz output did not contain an average rate." >&2
  cat "${HZ_LOG}" >&2 || true
  exit 1
fi

cleanup
runner_pid=""

if ps -C gzserver -C gzclient -C px4 -C gazebo -C make -o pid=,comm=,args= | grep -q .; then
  echo "Residual simulation process detected after cleanup:" >&2
  ps -C gzserver -C gzclient -C px4 -C gazebo -C make -o pid,comm,args >&2
  exit 1
fi

echo "Foggy lidar PointCloud2 verified."
echo "PX4/Gazebo log: ${PX4_LOG}"
echo "Topics log: ${TOPICS_LOG}"
echo "Type log: ${TYPE_LOG}"
echo "Info log: ${INFO_LOG}"
echo "Sample log: ${SAMPLE_LOG}"
echo "Hz log: ${HZ_LOG}"
