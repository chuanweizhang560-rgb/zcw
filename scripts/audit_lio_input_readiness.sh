#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_BIN="${AGENT_BIN:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean/MicroXRCEAgent}"
AGENT_LIB_DIR="${AGENT_LIB_DIR:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${RESULT_ROOT}/lio_input_readiness_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/lio_input_readiness_${STAMP}.txt"
TOPICS_LOG="${LOG_DIR}/lio_input_topics_${STAMP}.log"
POINTS_TYPE_LOG="${LOG_DIR}/lio_input_points_type_${STAMP}.log"
POINTS_SAMPLE_LOG="${LOG_DIR}/lio_input_points_sample_${STAMP}.log"
SENSOR_COMBINED_TYPE_LOG="${LOG_DIR}/lio_input_sensor_combined_type_${STAMP}.log"
SENSOR_COMBINED_SAMPLE_LOG="${LOG_DIR}/lio_input_sensor_combined_sample_${STAMP}.log"
PX4_LOG="${LOG_DIR}/lio_input_px4_${STAMP}.log"
AGENT_LOG="${LOG_DIR}/lio_input_agent_${STAMP}.log"
PX4_WAIT_SEC="${PX4_WAIT_SEC:-90}"
TOPIC_WAIT_SEC="${TOPIC_WAIT_SEC:-45}"
POINTS_TOPIC="${POINTS_TOPIC:-/zcw/foggy_lidar/points}"
IMU_TOPIC="${IMU_TOPIC:-/fmu/out/sensor_combined}"

agent_pid=""
runner_pid=""

cleanup() {
  for pid in "${runner_pid}" "${agent_pid}"; do
    if [[ -n "${pid}" ]]; then
      kill -TERM -- "-${pid}" >/dev/null 2>&1 || true
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done
  pkill -TERM -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
  sleep 2
  pkill -KILL -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "${LOG_DIR}" "${RESULT_DIR}"

if [[ ! -x "${AGENT_BIN}" ]]; then
  echo "MicroXRCEAgent not found: ${AGENT_BIN}" >&2
  exit 1
fi

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
  echo "MicroXRCEAgent did not report UDP readiness." >&2
  tail -n 80 "${AGENT_LOG}" >&2 || true
  exit 1
fi

setsid env \
  ROS_VERSION=2 \
  PX4_MODEL=iris_foggy_lidar \
  AERIALCORE_WORLD=danube_wires \
  TIMEOUT_SEC="${PX4_TIMEOUT_SEC:-180}" \
  LOG_FILE="${PX4_LOG}" \
  "${ROOT_DIR}/scripts/run_px4_aerialcore_world_headless.sh" >/dev/null 2>&1 &
runner_pid=$!

for _ in $(seq 1 "${PX4_WAIT_SEC}"); do
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
  tail -n 100 "${PX4_LOG}" >&2 || true
  exit 1
fi

set +u
source /opt/ros/humble/setup.bash
source "${ROOT_DIR}/install/setup.bash" 2>/dev/null || true
set -u

for _ in $(seq 1 "${TOPIC_WAIT_SEC}"); do
  ros2 topic list --no-daemon | sort >"${TOPICS_LOG}" || true
  if grep -qx "${POINTS_TOPIC}" "${TOPICS_LOG}" &&
     grep -qx "${IMU_TOPIC}" "${TOPICS_LOG}"; then
    break
  fi
  sleep 1
done

if ! grep -qx "${POINTS_TOPIC}" "${TOPICS_LOG}"; then
  echo "PointCloud2 topic not found: ${POINTS_TOPIC}" >&2
  cat "${TOPICS_LOG}" >&2 || true
  exit 1
fi
if ! grep -qx "${IMU_TOPIC}" "${TOPICS_LOG}"; then
  echo "IMU candidate topic not found: ${IMU_TOPIC}" >&2
  cat "${TOPICS_LOG}" >&2 || true
  exit 1
fi

ros2 topic type "${POINTS_TOPIC}" >"${POINTS_TYPE_LOG}"
ros2 topic type "${IMU_TOPIC}" >"${SENSOR_COMBINED_TYPE_LOG}"
timeout 20s ros2 topic echo --qos-reliability reliable --qos-durability volatile --once "${POINTS_TOPIC}" >"${POINTS_SAMPLE_LOG}"
timeout 20s ros2 topic echo --once "${IMU_TOPIC}" >"${SENSOR_COMBINED_SAMPLE_LOG}"

fields_csv="$(
  awk '
    /^fields:/ {in_fields=1; next}
    in_fields && /^- name:/ {print $3}
    in_fields && /^is_bigendian:/ {exit}
  ' "${POINTS_SAMPLE_LOG}" | paste -sd, -
)"

has_ring=false
has_time=false
has_native_ros_imu=false
if grep -q "name: ring" "${POINTS_SAMPLE_LOG}"; then
  has_ring=true
fi
if grep -q "name: time" "${POINTS_SAMPLE_LOG}" ||
   grep -q "name: t" "${POINTS_SAMPLE_LOG}"; then
  has_time=true
fi
if grep -qx "sensor_msgs/msg/Imu" "${SENSOR_COMBINED_TYPE_LOG}"; then
  has_native_ros_imu=true
fi

spark_fast_lio_direct_ready=false
lio_sam_direct_ready=false
decision="rejected_lio_input_readiness"
reason="foggy_lidar_pointcloud_missing_ring_time_and_only_px4_sensor_combined_imu"

if [[ "${has_native_ros_imu}" == "true" && "${has_time}" == "true" ]]; then
  spark_fast_lio_direct_ready=true
fi
if [[ "${has_native_ros_imu}" == "true" && "${has_ring}" == "true" && "${has_time}" == "true" ]]; then
  lio_sam_direct_ready=true
fi

{
  echo "scope=lio_input_readiness"
  echo "decision=${decision}"
  echo "reason=${reason}"
  echo "starts_ros=true"
  echo "starts_px4=true"
  echo "starts_gazebo=true"
  echo "starts_rviz=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "pointcloud_topic=${POINTS_TOPIC}"
  echo "pointcloud_type=$(cat "${POINTS_TYPE_LOG}")"
  echo "pointcloud_fields=${fields_csv}"
  echo "pointcloud_has_ring=${has_ring}"
  echo "pointcloud_has_time=${has_time}"
  echo "imu_topic=${IMU_TOPIC}"
  echo "imu_topic_type=$(cat "${SENSOR_COMBINED_TYPE_LOG}")"
  echo "imu_is_native_ros_imu=${has_native_ros_imu}"
  echo "spark_fast_lio_direct_ready=${spark_fast_lio_direct_ready}"
  echo "lio_sam_direct_ready=${lio_sam_direct_ready}"
  echo "px4_log=${PX4_LOG}"
  echo "agent_log=${AGENT_LOG}"
  echo "topics_log=${TOPICS_LOG}"
  echo "points_sample_log=${POINTS_SAMPLE_LOG}"
  echo "imu_sample_log=${SENSOR_COMBINED_SAMPLE_LOG}"
} >"${SUMMARY_FILE}"

echo "LIO input readiness audit completed."
echo "Summary: ${SUMMARY_FILE}"
