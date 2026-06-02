#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
STAMP="$(date +%Y%m%d_%H%M%S)"
PX4_LOG="${LOG_DIR}/foggy_lidar_ransac_px4_${STAMP}.log"
TOPICS_LOG="${LOG_DIR}/foggy_lidar_ransac_topics_${STAMP}.log"
NODE_LOG="${LOG_DIR}/foggy_lidar_ransac_node_${STAMP}.log"
RESULT_DIR="${RESULT_ROOT}/foggy_lidar_ransac_${STAMP}"
TOPIC="${FOGGY_LIDAR_TOPIC:-/zcw/foggy_lidar/points}"
DISTANCE_THRESHOLD="${RANSAC_DISTANCE_THRESHOLD_M:-0.35}"
MIN_INLIERS="${RANSAC_MIN_INLIERS:-8}"
MAX_ITERATIONS="${RANSAC_MAX_ITERATIONS:-200}"
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

(
  cd "${ROOT_DIR}"
  timeout "${RANSAC_TIMEOUT_SEC:-45}s" ros2 run zcw_cable_perception pointcloud_line_ransac_smoke --ros-args \
    -p topic:="${TOPIC}" \
    -p output_dir:="${RESULT_DIR}" \
    -p distance_threshold_m:="${DISTANCE_THRESHOLD}" \
    -p min_inliers:="${MIN_INLIERS}" \
    -p max_iterations:="${MAX_ITERATIONS}"
) >"${NODE_LOG}" 2>&1

RESULT_TXT="$(find "${RESULT_DIR}" -maxdepth 1 -name 'foggy_lidar_line_ransac_*.txt' | sort | tail -n 1)"
if [[ -z "${RESULT_TXT}" || ! -f "${RESULT_TXT}" ]]; then
  echo "RANSAC result file was not created." >&2
  cat "${NODE_LOG}" >&2 || true
  exit 1
fi

if ! grep -q "^ransac_inliers:" "${RESULT_TXT}" ||
   ! grep -q "^coefficients:" "${RESULT_TXT}"; then
  echo "RANSAC result file is missing expected fields: ${RESULT_TXT}" >&2
  cat "${RESULT_TXT}" >&2 || true
  exit 1
fi

cleanup
runner_pid=""

if ps -C gzserver -C gzclient -C px4 -C gazebo -C make -o pid=,comm=,args= | grep -q .; then
  echo "Residual simulation process detected after cleanup:" >&2
  ps -C gzserver -C gzclient -C px4 -C gazebo -C make -o pid,comm,args >&2
  exit 1
fi

echo "Foggy lidar PCL RANSAC smoke verified."
echo "PX4/Gazebo log: ${PX4_LOG}"
echo "Topics log: ${TOPICS_LOG}"
echo "Node log: ${NODE_LOG}"
echo "Result dir: ${RESULT_DIR}"
echo "Result txt: ${RESULT_TXT}"
