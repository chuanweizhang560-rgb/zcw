#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_BIN="${AGENT_BIN:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean/MicroXRCEAgent}"
AGENT_LIB_DIR="${AGENT_LIB_DIR:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean}"
PX4_SCRIPT="${PX4_SCRIPT:-${ROOT_DIR}/scripts/run_px4_aerialcore_world_headless.sh}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-${ROOT_DIR}/data/screenshots}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
STAMP="$(date +%Y%m%d_%H%M%S)"

AGENT_LOG="${LOG_DIR}/depth_camera_motion_agent_${STAMP}.log"
PX4_LOG="${LOG_DIR}/depth_camera_motion_px4_${STAMP}.log"
PX4_WRAPPER_LOG="${PX4_LOG}.wrapper"
OFFBOARD_LOG="${LOG_DIR}/depth_camera_motion_offboard_${STAMP}.log"
TOPICS_LOG="${LOG_DIR}/depth_camera_motion_topics_${STAMP}.log"
TYPES_LOG="${LOG_DIR}/depth_camera_motion_types_${STAMP}.log"
STATUS_LOG="${LOG_DIR}/depth_camera_motion_vehicle_status_${STAMP}.log"
LOCAL_POSITION_LOG="${LOG_DIR}/depth_camera_motion_vehicle_local_position_${STAMP}.log"
NODE_LOG="${LOG_DIR}/depth_camera_motion_ransac_node_${STAMP}.log"
SCREENSHOT_FILE="${SCREENSHOT_DIR}/depth_camera_motion_gui_${STAMP}.png"
RESULT_DIR="${RESULT_ROOT}/depth_camera_motion_ransac_${STAMP}"

POINTS_TOPIC="${DEPTH_CAMERA_POINTS_TOPIC:-/camera/points}"
POSE_TOPIC="${DEPTH_CAMERA_POSE_TOPIC:-/zcw/depth_camera/pose}"
FRAMES="${RANSAC_FRAMES:-5}"
DISTANCE_THRESHOLD="${RANSAC_DISTANCE_THRESHOLD_M:-0.35}"
MIN_INLIERS="${RANSAC_MIN_INLIERS:-50}"
APPLY_SENSOR_POSE="${APPLY_SENSOR_POSE_IN_LINK:-true}"
SENSOR_ROLL_RAD="${SENSOR_ROLL_RAD:--1.57079632679}"
SENSOR_PITCH_RAD="${SENSOR_PITCH_RAD:-0.0}"
SENSOR_YAW_RAD="${SENSOR_YAW_RAD:--1.57079632679}"
CROP_MIN_X="${RANSAC_CROP_MIN_X:--80.0}"
CROP_MAX_X="${RANSAC_CROP_MAX_X:-80.0}"
CROP_MIN_Y="${RANSAC_CROP_MIN_Y:--80.0}"
CROP_MAX_Y="${RANSAC_CROP_MAX_Y:-80.0}"
CROP_MIN_Z="${RANSAC_CROP_MIN_Z:-0.0}"
CROP_MAX_Z="${RANSAC_CROP_MAX_Z:-80.0}"

PX4_TIMEOUT_SEC="${PX4_TIMEOUT_SEC:-190}"
VERIFY_TIMEOUT_SEC="${VERIFY_TIMEOUT_SEC:-95}"
RANSAC_CAPTURE_DELAY_SEC="${RANSAC_CAPTURE_DELAY_SEC:-70}"
RANSAC_TIMEOUT_SEC="${RANSAC_TIMEOUT_SEC:-90}"

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

  pkill -TERM -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
  sleep 2
  pkill -KILL -f "${ROOT_DIR}.*/power_towers_danube_wires_rescaled_autospawn.world" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
}
trap cleanup EXIT

capture_gazebo_screenshot() {
  if [[ -n "${PX4_HEADLESS-}" ]]; then
    return 0
  fi

  local screenshot_ok=0
  local window_id=""
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
}

if [[ ! -x "${AGENT_BIN}" ]]; then
  echo "MicroXRCEAgent not found: ${AGENT_BIN}" >&2
  exit 1
fi

if [[ ! -x "${PX4_SCRIPT}" ]]; then
  echo "PX4 AerialCore script not found: ${PX4_SCRIPT}" >&2
  exit 1
fi

if [[ ! -d "${ROOT_DIR}/install/zcw_cable_perception" ||
      ! -d "${ROOT_DIR}/install/zcw_px4_baseline" ||
      ! -d "${ROOT_DIR}/install/zcw_bringup" ]]; then
  echo "Required ROS 2 packages are not built. Run:" >&2
  echo "  source /opt/ros/humble/setup.bash && colcon build --symlink-install --base-paths ros2_ws/src" >&2
  exit 1
fi

if [[ -z "${PX4_HEADLESS-}" && -z "${DISPLAY:-}" ]]; then
  echo "DISPLAY is not set; depth camera rendering requires Gazebo GUI mode." >&2
  exit 1
fi

mkdir -p "${LOG_DIR}" "${SCREENSHOT_DIR}" "${RESULT_DIR}"

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
  ROS_VERSION=2 \
  PX4_DIRECT_MODEL=1 \
  PX4_HEADLESS="${PX4_HEADLESS-}" \
  PX4_SYS_AUTOSTART=10015 \
  PX4_MODEL=iris_depth_camera \
  AERIALCORE_WORLD=danube_wires \
  TIMEOUT_SEC="${PX4_TIMEOUT_SEC}" \
  LOG_FILE="${PX4_LOG}" \
  "${PX4_SCRIPT}" >"${PX4_WRAPPER_LOG}" 2>&1 &
px4_pid=$!

for _ in $(seq 1 "${VERIFY_TIMEOUT_SEC}"); do
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
  tail -n 120 "${PX4_LOG}" >&2 || true
  exit 1
fi

set +u
source /opt/ros/humble/setup.bash
source "${ROOT_DIR}/install/setup.bash"
set -u

for _ in $(seq 1 "${VERIFY_TIMEOUT_SEC}"); do
  if ! kill -0 "${px4_pid}" >/dev/null 2>&1; then
    echo "PX4/Gazebo runner exited before required ROS 2 topics became available." >&2
    tail -n 120 "${PX4_LOG}" >&2 || true
    exit 1
  fi

  ros2 topic list --no-daemon | sort >"${TOPICS_LOG}" || true
  : >"${TYPES_LOG}"
  while IFS= read -r topic; do
    [[ -z "${topic}" ]] && continue
    echo "${topic} $(ros2 topic type "${topic}" 2>/dev/null || true)" >>"${TYPES_LOG}"
  done <"${TOPICS_LOG}"

  if grep -q "^/fmu/out/vehicle_status px4_msgs/msg/VehicleStatus$" "${TYPES_LOG}" &&
     grep -q "^/fmu/out/vehicle_local_position px4_msgs/msg/VehicleLocalPosition$" "${TYPES_LOG}" &&
     grep -q "^${POINTS_TOPIC} sensor_msgs/msg/PointCloud2$" "${TYPES_LOG}" &&
     grep -q "^${POSE_TOPIC} nav_msgs/msg/Odometry$" "${TYPES_LOG}"; then
    break
  fi
  sleep 1
done

if ! grep -q "^/fmu/out/vehicle_local_position px4_msgs/msg/VehicleLocalPosition$" "${TYPES_LOG}" ||
   ! grep -q "^${POINTS_TOPIC} sensor_msgs/msg/PointCloud2$" "${TYPES_LOG}" ||
   ! grep -q "^${POSE_TOPIC} nav_msgs/msg/Odometry$" "${TYPES_LOG}"; then
  echo "Required motion/depth camera topics were not found." >&2
  cat "${TYPES_LOG}" >&2 || true
  exit 1
fi

setsid env -i \
  HOME="${HOME:-/home/travis}" \
  USER="${USER:-travis}" \
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  /bin/bash -c "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && ros2 launch zcw_bringup single_vehicle_cable_inspection.launch.py" >"${OFFBOARD_LOG}" 2>&1 &
offboard_pid=$!

sleep "${RANSAC_CAPTURE_DELAY_SEC}"

timeout 8s ros2 topic echo --once /fmu/out/vehicle_status >"${STATUS_LOG}" 2>&1
timeout 8s ros2 topic echo --once /fmu/out/vehicle_local_position >"${LOCAL_POSITION_LOG}" 2>&1
capture_gazebo_screenshot

set +e
(
  cd "${ROOT_DIR}"
  timeout "${RANSAC_TIMEOUT_SEC}s" ros2 run zcw_cable_perception pointcloud_pose_line_ransac_world_smoke --ros-args \
    -p topic:="${POINTS_TOPIC}" \
    -p pose_topic:="${POSE_TOPIC}" \
    -p output_dir:="${RESULT_DIR}" \
    -p output_prefix:="depth_camera_motion_line_ransac_world" \
    -p frames:="${FRAMES}" \
    -p distance_threshold_m:="${DISTANCE_THRESHOLD}" \
    -p min_inliers:="${MIN_INLIERS}" \
    -p apply_sensor_pose_in_link:="${APPLY_SENSOR_POSE}" \
    -p sensor_roll_rad:="${SENSOR_ROLL_RAD}" \
    -p sensor_pitch_rad:="${SENSOR_PITCH_RAD}" \
    -p sensor_yaw_rad:="${SENSOR_YAW_RAD}" \
    -p crop_min_x:="${CROP_MIN_X}" \
    -p crop_max_x:="${CROP_MAX_X}" \
    -p crop_min_y:="${CROP_MIN_Y}" \
    -p crop_max_y:="${CROP_MAX_Y}" \
    -p crop_min_z:="${CROP_MIN_Z}" \
    -p crop_max_z:="${CROP_MAX_Z}"
) >"${NODE_LOG}" 2>&1
node_rc=$?
set -e

SUMMARY_TXT="$(find "${RESULT_DIR}" -maxdepth 1 -name 'depth_camera_motion_line_ransac_world_*.txt' | sort | tail -n 1)"
SUMMARY_CSV="$(find "${RESULT_DIR}" -maxdepth 1 -name 'depth_camera_motion_line_ransac_world_*.csv' | sort | tail -n 1)"
if [[ -z "${SUMMARY_TXT}" || ! -f "${SUMMARY_TXT}" || -z "${SUMMARY_CSV}" || ! -f "${SUMMARY_CSV}" ]]; then
  echo "Depth camera motion RANSAC summary files were not created." >&2
  cat "${NODE_LOG}" >&2 || true
  exit 1
fi

if ! grep -q "arming_state: 2" "${STATUS_LOG}" ||
   ! grep -q "nav_state: 14" "${STATUS_LOG}"; then
  echo "PX4 was not in armed Offboard state at capture time." >&2
  tail -n 120 "${OFFBOARD_LOG}" >&2 || true
  cat "${STATUS_LOG}" >&2 || true
  exit 1
fi

if ! grep -q "Advancing to waypoint" "${OFFBOARD_LOG}"; then
  echo "Waypoint node did not report waypoint advancement before capture." >&2
  tail -n 160 "${OFFBOARD_LOG}" >&2 || true
  cat "${LOCAL_POSITION_LOG}" >&2 || true
  exit 1
fi

if [[ ! -f "${RESULT_DIR}/frame_0_line_inliers_world.pcd" ]]; then
  echo "World-frame inlier PCD was not created." >&2
  find "${RESULT_DIR}" -maxdepth 1 -type f -printf '%f\n' >&2 | sort
  exit 1
fi

cleanup
agent_pid=""
px4_pid=""
offboard_pid=""
sleep 2

if ps -C gzserver -C gzclient -C px4 -C gazebo -C make -o pid=,comm=,args= | grep -q .; then
  echo "Residual simulation process detected after cleanup:" >&2
  ps -C gzserver -C gzclient -C px4 -C gazebo -C make -o pid,comm,args >&2
  exit 1
fi

echo "Depth camera cable-motion RANSAC audit completed."
echo "Node result code: ${node_rc}"
echo "Agent log: ${AGENT_LOG}"
echo "PX4/Gazebo log: ${PX4_LOG}"
echo "Offboard log: ${OFFBOARD_LOG}"
echo "Vehicle status log: ${STATUS_LOG}"
echo "Vehicle local position log: ${LOCAL_POSITION_LOG}"
echo "Topics log: ${TOPICS_LOG}"
echo "Types log: ${TYPES_LOG}"
echo "Node log: ${NODE_LOG}"
echo "Result dir: ${RESULT_DIR}"
echo "Summary txt: ${SUMMARY_TXT}"
echo "Summary csv: ${SUMMARY_CSV}"
if [[ -s "${SCREENSHOT_FILE}" ]]; then
  echo "Screenshot: ${SCREENSHOT_FILE}"
fi
