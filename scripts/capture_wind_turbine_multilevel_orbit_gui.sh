#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_BIN="${AGENT_BIN:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean/MicroXRCEAgent}"
AGENT_LIB_DIR="${AGENT_LIB_DIR:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean}"
PX4_DIR="${PX4_DIR:-${ROOT_DIR}/third_party/PX4-Autopilot-release-1.14}"
PX4_VENV="${PX4_VENV:-${ROOT_DIR}/.venv/px4_venv}"
AERIALCORE_DIR="${AERIALCORE_DIR:-${ROOT_DIR}/third_party/aerialcore_simulation}"
ZCW_MODEL_PATH="${ZCW_MODEL_PATH:-${ROOT_DIR}/assets/gazebo/models}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-${ROOT_DIR}/data/screenshots}"
STAMP="$(date +%Y%m%d_%H%M%S)"

AGENT_LOG="${LOG_DIR}/wind_multilevel_gui_agent_${STAMP}.log"
PX4_LOG="${LOG_DIR}/wind_multilevel_gui_px4_${STAMP}.log"
PX4_WRAPPER_LOG="${PX4_LOG}.wrapper"
OFFBOARD_LOG="${LOG_DIR}/wind_multilevel_gui_offboard_${STAMP}.log"
STATUS_LOG="${LOG_DIR}/wind_multilevel_gui_vehicle_status_${STAMP}.log"
LOCAL_POSITION_LOG="${LOG_DIR}/wind_multilevel_gui_vehicle_local_position_${STAMP}.log"
TOPIC_LIST_LOG="${LOG_DIR}/wind_multilevel_gui_topics_${STAMP}.log"
SCREENSHOT_FILE="${SCREENSHOT_DIR}/wind_turbine_multilevel_orbit_gui_${STAMP}.png"

VERIFY_TIMEOUT_SEC="${VERIFY_TIMEOUT_SEC:-90}"
CAPTURE_TIMEOUT_SEC="${CAPTURE_TIMEOUT_SEC:-130}"
MIN_ADVANCEMENTS="${MIN_ADVANCEMENTS:-8}"
GUI_WINDOW_WAIT_SEC="${GUI_WINDOW_WAIT_SEC:-30}"

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
}
trap cleanup EXIT

if [[ -z "${DISPLAY:-}" ]]; then
  echo "DISPLAY is not set; cannot capture Gazebo GUI." >&2
  exit 1
fi
if [[ ! -x "${AGENT_BIN}" ]]; then
  echo "MicroXRCEAgent not found: ${AGENT_BIN}" >&2
  exit 1
fi
if [[ ! -d "${PX4_DIR}" ]]; then
  echo "PX4 directory not found: ${PX4_DIR}" >&2
  exit 1
fi
if [[ ! -x "${PX4_VENV}/bin/python" ]]; then
  echo "PX4 venv python not found: ${PX4_VENV}/bin/python" >&2
  exit 1
fi
WORLD_PATH="${AERIALCORE_DIR}/worlds/wind_turbine_autospawn.world"
if [[ ! -f "${WORLD_PATH}" ]]; then
  echo "AerialCore wind turbine world not found: ${WORLD_PATH}" >&2
  exit 1
fi

mkdir -p "${LOG_DIR}" "${SCREENSHOT_DIR}" "${LOG_DIR}/ros2_launch"

setsid env -i \
  HOME="${HOME:-/home/travis}" \
  USER="${USER:-travis}" \
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  LD_LIBRARY_PATH="${AGENT_LIB_DIR}:/opt/ros/humble/lib" \
  "${AGENT_BIN}" udp4 -p 8888 >"${AGENT_LOG}" 2>&1 &
agent_pid=$!

for _ in $(seq 1 12); do
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

model_path="${AERIALCORE_DIR}/models"
if [[ -d "${ZCW_MODEL_PATH}" ]]; then
  model_path="${ZCW_MODEL_PATH}:${model_path}"
fi

setsid env -i \
  HOME="${HOME:-/home/travis}" \
  USER="${USER:-travis}" \
  DISPLAY="${DISPLAY}" \
  XAUTHORITY="${XAUTHORITY:-}" \
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
  PATH="${PX4_VENV}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  PYTHON_EXECUTABLE="${PX4_VENV}/bin/python" \
  PX4_SITL_WORLD="${WORLD_PATH}" \
  GAZEBO_MODEL_PATH="${model_path}" \
  GAZEBO_RESOURCE_PATH="/usr/share/gazebo-11:${AERIALCORE_DIR}" \
  VERBOSE_SIM="${VERBOSE_SIM:-1}" \
  NO_PXH=1 \
  QT_X11_NO_MITSHM=1 \
  LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}" \
  make -C "${PX4_DIR}" px4_sitl gazebo-classic >"${PX4_LOG}" 2>"${PX4_WRAPPER_LOG}" &
px4_pid=$!

for _ in $(seq 1 "${VERIFY_TIMEOUT_SEC}"); do
  if [[ -f "${PX4_LOG}" ]] &&
     grep -q "Simulator connected on TCP port 4560" "${PX4_LOG}" &&
     grep -q "Startup script returned successfully" "${PX4_LOG}"; then
    timeout 8s env -i \
      HOME="${HOME:-/home/travis}" \
      USER="${USER:-travis}" \
      PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
      ROS_LOG_DIR="${LOG_DIR}/ros2_launch" \
      /bin/bash -c "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && ros2 topic list" >"${TOPIC_LIST_LOG}" 2>&1 || true
    if grep -q "/fmu/out/vehicle_status" "${TOPIC_LIST_LOG}" &&
       grep -q "/fmu/out/vehicle_local_position" "${TOPIC_LIST_LOG}"; then
      break
    fi
  fi
  sleep 1
done

if ! grep -q "/fmu/out/vehicle_local_position" "${TOPIC_LIST_LOG}"; then
  echo "PX4 ROS 2 bridge did not expose required topics before GUI capture." >&2
  tail -n 80 "${PX4_LOG}" >&2 || true
  exit 1
fi

setsid env -i \
  HOME="${HOME:-/home/travis}" \
  USER="${USER:-travis}" \
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  ROS_LOG_DIR="${LOG_DIR}/ros2_launch" \
  /bin/bash -c "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && ros2 launch zcw_bringup single_vehicle_wind_turbine_multilevel_orbit.launch.py" >"${OFFBOARD_LOG}" 2>&1 &
offboard_pid=$!

for _ in $(seq 1 "${CAPTURE_TIMEOUT_SEC}"); do
  advancements=0
  if [[ -f "${OFFBOARD_LOG}" ]]; then
    advancements="$(grep -c "Advancing to waypoint" "${OFFBOARD_LOG}" || true)"
  fi
  if [[ "${advancements}" -ge "${MIN_ADVANCEMENTS}" ]]; then
    break
  fi
  sleep 1
done

advancements="$(grep -c "Advancing to waypoint" "${OFFBOARD_LOG}" || true)"
if [[ "${advancements}" -lt "${MIN_ADVANCEMENTS}" ]]; then
  echo "Timed out before enough wind turbine orbit waypoint advancements." >&2
  tail -n 120 "${OFFBOARD_LOG}" >&2 || true
  exit 1
fi

timeout 8s env -i \
  HOME="${HOME:-/home/travis}" \
  USER="${USER:-travis}" \
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  ROS_LOG_DIR="${LOG_DIR}/ros2_launch" \
  /bin/bash -c "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && ros2 topic echo --once /fmu/out/vehicle_status" >"${STATUS_LOG}" 2>&1

timeout 8s env -i \
  HOME="${HOME:-/home/travis}" \
  USER="${USER:-travis}" \
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  ROS_LOG_DIR="${LOG_DIR}/ros2_launch" \
  /bin/bash -c "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && ros2 topic echo --once /fmu/out/vehicle_local_position" >"${LOCAL_POSITION_LOG}" 2>&1

if ! grep -q "arming_state: 2" "${STATUS_LOG}" ||
   ! grep -q "nav_state: 14" "${STATUS_LOG}"; then
  echo "PX4 did not report armed Offboard before GUI screenshot." >&2
  tail -n 80 "${STATUS_LOG}" >&2 || true
  exit 1
fi

window_id=""
set +o pipefail
for _ in $(seq 1 "${GUI_WINDOW_WAIT_SEC}"); do
  window_id="$(
    env DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
      xwininfo -root -tree 2>/dev/null | awk '/"Gazebo"/ {print $1; exit}'
  )"
  if [[ -n "${window_id}" ]]; then
    break
  fi
  sleep 1
done
set -o pipefail

if [[ -z "${window_id}" ]]; then
  echo "Gazebo window id was not found; refusing to capture a desktop fallback." >&2
  exit 1
fi

if ! env DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
  import -window "${window_id}" "${SCREENSHOT_FILE}" >/dev/null 2>&1; then
  echo "Gazebo window screenshot capture failed." >&2
  exit 1
fi

if [[ ! -s "${SCREENSHOT_FILE}" ]]; then
  echo "Screenshot file is empty: ${SCREENSHOT_FILE}" >&2
  exit 1
fi
echo "Gazebo window id: ${window_id}" >"${SCREENSHOT_FILE}.window_id.txt"

echo "Wind turbine multilevel orbit GUI screenshot captured."
echo "advancements=${advancements}"
echo "Agent log: ${AGENT_LOG}"
echo "PX4 log: ${PX4_LOG}"
echo "Offboard log: ${OFFBOARD_LOG}"
echo "Vehicle status log: ${STATUS_LOG}"
echo "Vehicle local position log: ${LOCAL_POSITION_LOG}"
echo "Screenshot: ${SCREENSHOT_FILE}"
echo "Gazebo window id: ${window_id}"
