#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
STAMP="$(date +%Y%m%d_%H%M%S)"
PX4_LOG="${LOG_DIR}/foggy_lidar_pose_px4_${STAMP}.log"
TOPICS_LOG="${LOG_DIR}/foggy_lidar_pose_topics_${STAMP}.log"
POINTS_TYPE_LOG="${LOG_DIR}/foggy_lidar_pose_points_type_${STAMP}.log"
POSE_TYPE_LOG="${LOG_DIR}/foggy_lidar_pose_pose_type_${STAMP}.log"
POINTS_SAMPLE_LOG="${LOG_DIR}/foggy_lidar_pose_points_sample_${STAMP}.log"
POSE_SAMPLE_LOG="${LOG_DIR}/foggy_lidar_pose_pose_sample_${STAMP}.log"
POINTS_TOPIC="${FOGGY_LIDAR_POINTS_TOPIC:-/zcw/foggy_lidar/points}"
POSE_TOPIC="${FOGGY_LIDAR_POSE_TOPIC:-/zcw/foggy_lidar/pose}"
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
  if grep -qx "${POINTS_TOPIC}" "${TOPICS_LOG}" && grep -qx "${POSE_TOPIC}" "${TOPICS_LOG}"; then
    break
  fi
  sleep 1
done

if ! grep -qx "${POINTS_TOPIC}" "${TOPICS_LOG}" || ! grep -qx "${POSE_TOPIC}" "${TOPICS_LOG}"; then
  echo "Expected foggy lidar topics were not found." >&2
  cat "${TOPICS_LOG}" >&2 || true
  exit 1
fi

ros2 topic type "${POINTS_TOPIC}" >"${POINTS_TYPE_LOG}"
ros2 topic type "${POSE_TOPIC}" >"${POSE_TYPE_LOG}"
if ! grep -qx "sensor_msgs/msg/PointCloud2" "${POINTS_TYPE_LOG}"; then
  echo "Unexpected topic type for ${POINTS_TOPIC}: $(cat "${POINTS_TYPE_LOG}")" >&2
  exit 1
fi
if ! grep -qx "nav_msgs/msg/Odometry" "${POSE_TYPE_LOG}"; then
  echo "Unexpected topic type for ${POSE_TOPIC}: $(cat "${POSE_TYPE_LOG}")" >&2
  exit 1
fi

timeout 20s ros2 topic echo --qos-reliability reliable --qos-durability volatile --once "${POINTS_TOPIC}" >"${POINTS_SAMPLE_LOG}"
timeout 20s ros2 topic echo --once "${POSE_TOPIC}" >"${POSE_SAMPLE_LOG}"

if ! grep -q "frame_id: foggy_lidar_link" "${POINTS_SAMPLE_LOG}"; then
  echo "PointCloud2 frame_id did not use foggy_lidar_link." >&2
  sed -n '1,40p' "${POINTS_SAMPLE_LOG}" >&2 || true
  exit 1
fi
if ! grep -q "frame_id: world" "${POSE_SAMPLE_LOG}"; then
  echo "Pose frame_id did not use world." >&2
  sed -n '1,80p' "${POSE_SAMPLE_LOG}" >&2 || true
  exit 1
fi

cleanup
runner_pid=""
sleep 2

if ps -C gzserver -C gzclient -C px4 -C gazebo -C make -o pid=,comm=,args= | grep -q .; then
  echo "Residual simulation process detected after cleanup:" >&2
  ps -C gzserver -C gzclient -C px4 -C gazebo -C make -o pid,comm,args >&2
  exit 1
fi

echo "Foggy lidar PointCloud2 + P3D pose verified."
echo "PX4/Gazebo log: ${PX4_LOG}"
echo "Topics log: ${TOPICS_LOG}"
echo "Points type log: ${POINTS_TYPE_LOG}"
echo "Pose type log: ${POSE_TYPE_LOG}"
echo "Points sample log: ${POINTS_SAMPLE_LOG}"
echo "Pose sample log: ${POSE_SAMPLE_LOG}"
