#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
STAMP="$(date +%Y%m%d_%H%M%S)"
PX4_LOG="${LOG_DIR}/px4vision_ros_contract_px4_${STAMP}.log"
TOPICS_LOG="${LOG_DIR}/px4vision_ros_contract_topics_${STAMP}.log"
FILTERED_TOPICS_LOG="${LOG_DIR}/px4vision_ros_contract_topics_filtered_${STAMP}.log"
TOPIC_TYPES_LOG="${LOG_DIR}/px4vision_ros_contract_topic_types_${STAMP}.log"
SUMMARY_DIR="${ROOT_DIR}/data/results/px4vision_ros_contract_${STAMP}"
SUMMARY_FILE="${SUMMARY_DIR}/px4vision_ros_contract_${STAMP}.txt"
runner_pid=""

cleanup() {
  if [[ -n "${runner_pid}" ]]; then
    kill -TERM -- "-${runner_pid}" >/dev/null 2>&1 || true
    sleep 2
    kill -KILL -- "-${runner_pid}" >/dev/null 2>&1 || true
    wait "${runner_pid}" >/dev/null 2>&1 || true
  fi
  pkill -TERM -f "make px4_sitl gazebo-classic_px4vision" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
  sleep 2
  pkill -KILL -f "make px4_sitl gazebo-classic_px4vision" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "${LOG_DIR}" "${SUMMARY_DIR}"

setsid env \
  ROS_VERSION=2 \
  PX4_MODEL=px4vision \
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
  ros2 topic list -t --no-daemon | sort >"${TOPICS_LOG}" || true
  if grep -q "camera" "${TOPICS_LOG}" || grep -q "depth" "${TOPICS_LOG}" || grep -q "/imu" "${TOPICS_LOG}"; then
    break
  fi
  sleep 1
done

grep -E "(imu|camera|depth|points|image_raw|camera_info)" "${TOPICS_LOG}" >"${FILTERED_TOPICS_LOG}" || true

native_imu_present=false
native_imu_type="missing"
pointcloud_topics_count=0
pointcloud_topics=""

if grep -qE "^/imu " "${TOPICS_LOG}"; then
  native_imu_present=true
  native_imu_type="$(grep -E "^/imu " "${TOPICS_LOG}" | awk '{print $2}')"
fi

while read -r topic type; do
  if [[ "${type}" == "sensor_msgs/msg/PointCloud2" ]]; then
    pointcloud_topics_count=$((pointcloud_topics_count + 1))
    if [[ -z "${pointcloud_topics}" ]]; then
      pointcloud_topics="${topic}"
    else
      pointcloud_topics="${pointcloud_topics},${topic}"
    fi
  fi
done <"${TOPICS_LOG}"

cp "${FILTERED_TOPICS_LOG}" "${TOPIC_TYPES_LOG}"

decision="rejected_px4vision_ros_contract"
reason="native_ros_imu_missing_or_no_pointcloud"
if [[ "${native_imu_present}" == "true" && "${pointcloud_topics_count}" -gt 0 ]]; then
  decision="accepted_px4vision_ros_contract"
  reason="native_ros_imu_and_pointcloud_present"
fi

{
  echo "decision=${decision}"
  echo "reason=${reason}"
  echo "native_imu_present=${native_imu_present}"
  echo "native_imu_type=${native_imu_type}"
  echo "pointcloud_topics_count=${pointcloud_topics_count}"
  echo "pointcloud_topics=${pointcloud_topics}"
  echo "px4_log=${PX4_LOG}"
  echo "topics_log=${TOPICS_LOG}"
  echo "filtered_topics_log=${FILTERED_TOPICS_LOG}"
} >"${SUMMARY_FILE}"

cleanup
runner_pid=""
sleep 2

if ps -C gzserver -C gzclient -C px4 -C gazebo -C make -o pid=,comm=,args= | grep -q .; then
  echo "Residual simulation process detected after cleanup:" >&2
  ps -C gzserver -C gzclient -C px4 -C gazebo -C make -o pid,comm,args >&2
  exit 1
fi

echo "PX4Vision ROS contract verified."
echo "Summary: ${SUMMARY_FILE}"
