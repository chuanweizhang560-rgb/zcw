#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
STAMP="$(date +%Y%m%d_%H%M%S)"
PX4_LOG="${LOG_DIR}/foggy_lidar_imu_bridge_px4_${STAMP}.log"
TOPICS_LOG="${LOG_DIR}/foggy_lidar_imu_bridge_topics_${STAMP}.log"
IMU_TYPE_LOG="${LOG_DIR}/foggy_lidar_imu_bridge_imu_type_${STAMP}.log"
SENSOR_COMBINED_TYPE_LOG="${LOG_DIR}/foggy_lidar_imu_bridge_sensor_combined_type_${STAMP}.log"
SUMMARY_DIR="${ROOT_DIR}/data/results/foggy_lidar_imu_bridge_${STAMP}"
SUMMARY_FILE="${SUMMARY_DIR}/foggy_lidar_imu_bridge_${STAMP}.txt"
IMU_TOPIC="${IMU_TOPIC:-/imu}"
SENSOR_COMBINED_TOPIC="${SENSOR_COMBINED_TOPIC:-/fmu/out/sensor_combined}"
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
  sleep 2
  pkill -KILL -f "make px4_sitl gazebo-classic_iris_foggy_lidar" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "${LOG_DIR}" "${SUMMARY_DIR}"

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

has_imu_topic=false
has_sensor_combined=false
imu_type="missing"
sensor_combined_type="missing"

for _ in $(seq 1 "${TOPIC_WAIT_SEC:-45}"); do
  ros2 topic list --no-daemon | sort >"${TOPICS_LOG}" || true
  if grep -qx "${SENSOR_COMBINED_TOPIC}" "${TOPICS_LOG}"; then
    has_sensor_combined=true
  fi
  if grep -qx "${IMU_TOPIC}" "${TOPICS_LOG}"; then
    has_imu_topic=true
  fi
  if [[ "${has_sensor_combined}" == "true" ]]; then
    break
  fi
  sleep 1
done

if [[ "${has_imu_topic}" == "true" ]]; then
  ros2 topic type "${IMU_TOPIC}" >"${IMU_TYPE_LOG}"
  imu_type="$(cat "${IMU_TYPE_LOG}")"
else
  : >"${IMU_TYPE_LOG}"
fi

if [[ "${has_sensor_combined}" == "true" ]]; then
  ros2 topic type "${SENSOR_COMBINED_TOPIC}" >"${SENSOR_COMBINED_TYPE_LOG}"
  sensor_combined_type="$(cat "${SENSOR_COMBINED_TYPE_LOG}")"
else
  : >"${SENSOR_COMBINED_TYPE_LOG}"
fi

decision="rejected_foggy_lidar_native_imu_bridge"
reason="native_ros_imu_topic_missing"
if [[ "${has_imu_topic}" == "true" ]]; then
  decision="accepted_foggy_lidar_native_imu_bridge"
  reason="native_ros_imu_topic_present"
fi

{
  echo "decision=${decision}"
  echo "reason=${reason}"
  echo "imu_topic=${IMU_TOPIC}"
  echo "imu_topic_present=${has_imu_topic}"
  echo "imu_topic_type=${imu_type}"
  echo "sensor_combined_topic=${SENSOR_COMBINED_TOPIC}"
  echo "sensor_combined_present=${has_sensor_combined}"
  echo "sensor_combined_topic_type=${sensor_combined_type}"
  echo "px4_log=${PX4_LOG}"
  echo "topics_log=${TOPICS_LOG}"
  echo "imu_type_log=${IMU_TYPE_LOG}"
  echo "sensor_combined_type_log=${SENSOR_COMBINED_TYPE_LOG}"
} >"${SUMMARY_FILE}"

cleanup
runner_pid=""
sleep 2

if ps -C gzserver -C gzclient -C px4 -C gazebo -C make -o pid=,comm=,args= | grep -q .; then
  echo "Residual simulation process detected after cleanup:" >&2
  ps -C gzserver -C gzclient -C px4 -C gazebo -C make -o pid,comm,args >&2
  exit 1
fi

echo "Foggy lidar IMU bridge verified."
echo "Summary: ${SUMMARY_FILE}"
