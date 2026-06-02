#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-${ROOT_DIR}/data/screenshots}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
STAMP="$(date +%Y%m%d_%H%M%S)"
PX4_LOG="${LOG_DIR}/depth_camera_world_ransac_px4_${STAMP}.log"
TOPICS_LOG="${LOG_DIR}/depth_camera_world_ransac_topics_${STAMP}.log"
TYPES_LOG="${LOG_DIR}/depth_camera_world_ransac_types_${STAMP}.log"
NODE_LOG="${LOG_DIR}/depth_camera_world_ransac_node_${STAMP}.log"
SCREENSHOT_FILE="${SCREENSHOT_DIR}/depth_camera_world_ransac_gui_${STAMP}.png"
RESULT_DIR="${RESULT_ROOT}/depth_camera_world_ransac_${STAMP}"
POINTS_TOPIC="${DEPTH_CAMERA_POINTS_TOPIC:-/camera/points}"
POSE_TOPIC="${DEPTH_CAMERA_POSE_TOPIC:-/zcw/depth_camera/pose}"
FRAMES="${RANSAC_FRAMES:-5}"
DISTANCE_THRESHOLD="${RANSAC_DISTANCE_THRESHOLD_M:-0.35}"
MIN_INLIERS="${RANSAC_MIN_INLIERS:-50}"
APPLY_SENSOR_POSE="${APPLY_SENSOR_POSE_IN_LINK:-false}"
CROP_MIN_X="${RANSAC_CROP_MIN_X:--80.0}"
CROP_MAX_X="${RANSAC_CROP_MAX_X:-80.0}"
CROP_MIN_Y="${RANSAC_CROP_MIN_Y:--80.0}"
CROP_MAX_Y="${RANSAC_CROP_MAX_Y:-80.0}"
CROP_MIN_Z="${RANSAC_CROP_MIN_Z:-0.0}"
CROP_MAX_Z="${RANSAC_CROP_MAX_Z:-80.0}"
runner_pid=""

cleanup() {
  if [[ -n "${runner_pid}" ]]; then
    kill -TERM -- "-${runner_pid}" >/dev/null 2>&1 || true
    sleep 2
    kill -KILL -- "-${runner_pid}" >/dev/null 2>&1 || true
    wait "${runner_pid}" >/dev/null 2>&1 || true
  fi
  pkill -TERM -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
  sleep 2
  pkill -KILL -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ ! -d "${ROOT_DIR}/install/zcw_cable_perception" ]]; then
  echo "zcw_cable_perception is not built. Run:" >&2
  echo "  source /opt/ros/humble/setup.bash && colcon build --symlink-install --base-paths ros2_ws/src --packages-select zcw_cable_perception" >&2
  exit 1
fi

mkdir -p "${LOG_DIR}" "${SCREENSHOT_DIR}" "${RESULT_DIR}"

if [[ -z "${PX4_HEADLESS-}" && -z "${DISPLAY:-}" ]]; then
  echo "DISPLAY is not set; depth camera rendering requires Gazebo GUI mode." >&2
  exit 1
fi

setsid env \
  ROS_VERSION=2 \
  PX4_DIRECT_MODEL=1 \
  PX4_HEADLESS="${PX4_HEADLESS-}" \
  PX4_SYS_AUTOSTART=10015 \
  PX4_MODEL=iris_depth_camera \
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

sleep "${GUI_SETTLE_SEC:-8}"

if [[ -z "${PX4_HEADLESS-}" ]]; then
  screenshot_ok=0
  set +o pipefail
  window_id="$(
    env DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
      xwininfo -root -tree 2>/dev/null | awk '/"Gazebo"/ {print $1; exit}'
  )"
  set -o pipefail
  if [[ -n "${window_id}" ]] &&
     env DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
       import -window "${window_id}" "${SCREENSHOT_FILE}" >/dev/null 2>&1; then
    screenshot_ok=1
  elif env DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
      gnome-screenshot -f "${SCREENSHOT_FILE}" >/dev/null 2>&1; then
    screenshot_ok=1
  elif env DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
      import -window root "${SCREENSHOT_FILE}" >/dev/null 2>&1; then
    screenshot_ok=1
  fi

  if [[ "${screenshot_ok}" != "1" || ! -s "${SCREENSHOT_FILE}" ]]; then
    echo "Screenshot capture failed." >&2
    exit 1
  fi

  if [[ -n "${window_id}" ]]; then
    echo "Gazebo window id: ${window_id}" >"${SCREENSHOT_FILE}.window_id.txt"
  fi
fi

set +u
source /opt/ros/humble/setup.bash
source "${ROOT_DIR}/install/setup.bash"
set -u

for _ in $(seq 1 "${TOPIC_WAIT_SEC:-45}"); do
  if ! kill -0 "${runner_pid}" >/dev/null 2>&1; then
    echo "PX4/Gazebo runner exited before depth camera topics became available." >&2
    tail -n 120 "${PX4_LOG}" >&2 || true
    exit 1
  fi

  ros2 topic list --no-daemon | sort >"${TOPICS_LOG}" || true
  : >"${TYPES_LOG}"
  while IFS= read -r topic; do
    [[ -z "${topic}" ]] && continue
    echo "${topic} $(ros2 topic type "${topic}" 2>/dev/null || true)" >>"${TYPES_LOG}"
  done <"${TOPICS_LOG}"

  if grep -q "^${POINTS_TOPIC} sensor_msgs/msg/PointCloud2$" "${TYPES_LOG}" &&
     grep -q "^${POSE_TOPIC} nav_msgs/msg/Odometry$" "${TYPES_LOG}"; then
    break
  fi
  sleep 1
done

if ! grep -q "^${POINTS_TOPIC} sensor_msgs/msg/PointCloud2$" "${TYPES_LOG}"; then
  echo "Depth camera PointCloud2 topic was not found: ${POINTS_TOPIC}" >&2
  cat "${TYPES_LOG}" >&2 || true
  exit 1
fi

if ! grep -q "^${POSE_TOPIC} nav_msgs/msg/Odometry$" "${TYPES_LOG}"; then
  echo "Depth camera pose topic was not found: ${POSE_TOPIC}" >&2
  cat "${TYPES_LOG}" >&2 || true
  exit 1
fi

set +e
(
  cd "${ROOT_DIR}"
  timeout "${RANSAC_TIMEOUT_SEC:-90}s" ros2 run zcw_cable_perception pointcloud_pose_line_ransac_world_smoke --ros-args \
    -p topic:="${POINTS_TOPIC}" \
    -p pose_topic:="${POSE_TOPIC}" \
    -p output_dir:="${RESULT_DIR}" \
    -p output_prefix:="depth_camera_line_ransac_world" \
    -p frames:="${FRAMES}" \
    -p distance_threshold_m:="${DISTANCE_THRESHOLD}" \
    -p min_inliers:="${MIN_INLIERS}" \
    -p apply_sensor_pose_in_link:="${APPLY_SENSOR_POSE}" \
    -p crop_min_x:="${CROP_MIN_X}" \
    -p crop_max_x:="${CROP_MAX_X}" \
    -p crop_min_y:="${CROP_MIN_Y}" \
    -p crop_max_y:="${CROP_MAX_Y}" \
    -p crop_min_z:="${CROP_MIN_Z}" \
    -p crop_max_z:="${CROP_MAX_Z}"
) >"${NODE_LOG}" 2>&1
node_rc=$?
set -e

SUMMARY_TXT="$(find "${RESULT_DIR}" -maxdepth 1 -name 'depth_camera_line_ransac_world_*.txt' | sort | tail -n 1)"
SUMMARY_CSV="$(find "${RESULT_DIR}" -maxdepth 1 -name 'depth_camera_line_ransac_world_*.csv' | sort | tail -n 1)"
if [[ -z "${SUMMARY_TXT}" || ! -f "${SUMMARY_TXT}" || -z "${SUMMARY_CSV}" || ! -f "${SUMMARY_CSV}" ]]; then
  echo "Depth camera world RANSAC summary files were not created." >&2
  cat "${NODE_LOG}" >&2 || true
  exit 1
fi

if [[ "${node_rc}" != "0" ]]; then
  echo "Depth camera world RANSAC node returned ${node_rc}." >&2
  cat "${SUMMARY_TXT}" >&2 || true
  cat "${NODE_LOG}" >&2 || true
  exit "${node_rc}"
fi

if ! grep -q "^world_inlier_bbox_min:" "${SUMMARY_TXT}" ||
   ! grep -q "^world_inlier_bbox_max:" "${SUMMARY_TXT}" ||
   ! grep -q "^failed_frames: 0" "${SUMMARY_TXT}"; then
  echo "Depth camera world RANSAC summary did not contain expected successful fields." >&2
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

echo "Depth camera world-frame PCL RANSAC smoke verified."
echo "PX4/Gazebo log: ${PX4_LOG}"
echo "Topics log: ${TOPICS_LOG}"
echo "Types log: ${TYPES_LOG}"
echo "Node log: ${NODE_LOG}"
echo "Result dir: ${RESULT_DIR}"
echo "Summary txt: ${SUMMARY_TXT}"
echo "Summary csv: ${SUMMARY_CSV}"
if [[ -s "${SCREENSHOT_FILE}" ]]; then
  echo "Screenshot: ${SCREENSHOT_FILE}"
fi
