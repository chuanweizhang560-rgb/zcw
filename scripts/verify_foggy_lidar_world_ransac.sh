#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
STAMP="$(date +%Y%m%d_%H%M%S)"
PX4_LOG="${LOG_DIR}/foggy_lidar_world_ransac_px4_${STAMP}.log"
TOPICS_LOG="${LOG_DIR}/foggy_lidar_world_ransac_topics_${STAMP}.log"
NODE_LOG="${LOG_DIR}/foggy_lidar_world_ransac_node_${STAMP}.log"
RESULT_DIR="${RESULT_ROOT}/foggy_lidar_world_ransac_${STAMP}"
POINTS_TOPIC="${FOGGY_LIDAR_POINTS_TOPIC:-/zcw/foggy_lidar/points}"
POSE_TOPIC="${FOGGY_LIDAR_POSE_TOPIC:-/zcw/foggy_lidar/pose}"
FRAMES="${RANSAC_FRAMES:-5}"
DISTANCE_THRESHOLD="${RANSAC_DISTANCE_THRESHOLD_M:-0.35}"
MIN_INLIERS="${RANSAC_MIN_INLIERS:-8}"
APPLY_SENSOR_POSE="${APPLY_SENSOR_POSE_IN_LINK:-true}"
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

if [[ ! -d "${ROOT_DIR}/install/zcw_cable_perception" ]]; then
  echo "zcw_cable_perception is not built. Run:" >&2
  echo "  source /opt/ros/humble/setup.bash && colcon build --symlink-install --base-paths ros2_ws/src --packages-select zcw_cable_perception" >&2
  exit 1
fi

mkdir -p "${LOG_DIR}" "${RESULT_DIR}"

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
source "${ROOT_DIR}/install/setup.bash"
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

(
  cd "${ROOT_DIR}"
  timeout "${RANSAC_TIMEOUT_SEC:-90}s" ros2 run zcw_cable_perception pointcloud_pose_line_ransac_world_smoke --ros-args \
    -p topic:="${POINTS_TOPIC}" \
    -p pose_topic:="${POSE_TOPIC}" \
    -p output_dir:="${RESULT_DIR}" \
    -p frames:="${FRAMES}" \
    -p distance_threshold_m:="${DISTANCE_THRESHOLD}" \
    -p min_inliers:="${MIN_INLIERS}" \
    -p apply_sensor_pose_in_link:="${APPLY_SENSOR_POSE}"
) >"${NODE_LOG}" 2>&1

SUMMARY_TXT="$(find "${RESULT_DIR}" -maxdepth 1 -name 'foggy_lidar_line_ransac_world_*.txt' | sort | tail -n 1)"
SUMMARY_CSV="$(find "${RESULT_DIR}" -maxdepth 1 -name 'foggy_lidar_line_ransac_world_*.csv' | sort | tail -n 1)"
if [[ -z "${SUMMARY_TXT}" || ! -f "${SUMMARY_TXT}" || -z "${SUMMARY_CSV}" || ! -f "${SUMMARY_CSV}" ]]; then
  echo "World RANSAC summary files were not created." >&2
  cat "${NODE_LOG}" >&2 || true
  exit 1
fi

if ! grep -q "^world_inlier_bbox_min:" "${SUMMARY_TXT}" ||
   ! grep -q "^world_inlier_bbox_max:" "${SUMMARY_TXT}" ||
   ! grep -q "^failed_frames: 0" "${SUMMARY_TXT}"; then
  echo "World RANSAC summary did not contain expected successful fields." >&2
  cat "${SUMMARY_TXT}" >&2 || true
  exit 1
fi

if [[ ! -f "${RESULT_DIR}/frame_0_line_inliers_world.pcd" ]]; then
  echo "World-frame inlier PCD was not created." >&2
  find "${RESULT_DIR}" -maxdepth 1 -type f -printf '%f\n' >&2 | sort
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

echo "Foggy lidar world-frame PCL RANSAC smoke verified."
echo "PX4/Gazebo log: ${PX4_LOG}"
echo "Topics log: ${TOPICS_LOG}"
echo "Node log: ${NODE_LOG}"
echo "Result dir: ${RESULT_DIR}"
echo "Summary txt: ${SUMMARY_TXT}"
echo "Summary csv: ${SUMMARY_CSV}"
