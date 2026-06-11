#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PX4_DIR="${PX4_DIR:-${ROOT_DIR}/third_party/PX4-Autopilot-release-1.14}"
VENV_DIR="${PX4_VENV:-${ROOT_DIR}/.venv/px4_venv}"
AGENT_BIN="${AGENT_BIN:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean/MicroXRCEAgent}"
AGENT_LIB_DIR="${AGENT_LIB_DIR:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-${ROOT_DIR}/data/screenshots}"
RVIZ_CONFIG="${RVIZ_CONFIG:-${ROOT_DIR}/ros2_ws/src/zcw_cable_perception/rviz/four_vehicle_dry_run_overlay.rviz}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${RESULT_ROOT}/four_vehicle_dry_run_smoke_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/four_vehicle_dry_run_smoke_${STAMP}.txt"
AGENT_LOG="${LOG_DIR}/four_vehicle_dry_run_agent_${STAMP}.log"
GAZEBO_LOG="${LOG_DIR}/four_vehicle_dry_run_gzserver_${STAMP}.log"
PLANNER_LOG="${LOG_DIR}/four_vehicle_dry_run_planner_${STAMP}.log"
TOPICS_LOG="${LOG_DIR}/four_vehicle_dry_run_topics_${STAMP}.log"
FORBIDDEN_PUBLISHERS_LOG="${LOG_DIR}/four_vehicle_dry_run_forbidden_publishers_${STAMP}.log"
DRY_RUN_SAMPLES_LOG="${LOG_DIR}/four_vehicle_dry_run_samples_${STAMP}.log"
RVIZ_LOG="${LOG_DIR}/four_vehicle_dry_run_rviz_${STAMP}.log"
SCREENSHOT_FILE="${SCREENSHOT_DIR}/four_vehicle_dry_run_overlay_${STAMP}.png"
TIMEOUT_SEC="${TIMEOUT_SEC:-110}"
WORLD_NAME="${WORLD_NAME:-empty}"
MODEL_NAME="${MODEL_NAME:-iris}"
CAPTURE_RVIZ="${CAPTURE_RVIZ:-0}"
RVIZ_SETTLE_SEC="${RVIZ_SETTLE_SEC:-8}"

agent_pid=""
gzserver_pid=""
planner_pid=""
rviz_pid=""
px4_pids=()

cleanup() {
  if [[ -n "${rviz_pid}" ]]; then
    kill -TERM -- "-${rviz_pid}" >/dev/null 2>&1 || true
    wait "${rviz_pid}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${planner_pid}" ]]; then
    kill -TERM -- "-${planner_pid}" >/dev/null 2>&1 || true
    wait "${planner_pid}" >/dev/null 2>&1 || true
  fi
  for pid in "${px4_pids[@]:-}"; do
    kill -TERM -- "-${pid}" >/dev/null 2>&1 || true
    wait "${pid}" >/dev/null 2>&1 || true
  done
  if [[ -n "${gzserver_pid}" ]]; then
    kill -TERM -- "-${gzserver_pid}" >/dev/null 2>&1 || true
    wait "${gzserver_pid}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${agent_pid}" ]]; then
    kill -TERM -- "-${agent_pid}" >/dev/null 2>&1 || true
    wait "${agent_pid}" >/dev/null 2>&1 || true
  fi
  pkill -TERM -f "four_vehicle_dry_run_planner.launch.py" >/dev/null 2>&1 || true
  pkill -TERM -f "rviz2.*four_vehicle_dry_run_overlay.rviz" >/dev/null 2>&1 || true
  pkill -TERM -f "${PX4_DIR}/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
  pkill -TERM -f "gzserver .*sitl_gazebo-classic/worlds/${WORLD_NAME}\\.world" >/dev/null 2>&1 || true
}
trap cleanup EXIT

source_workspace() {
  set +u
  source /opt/ros/humble/setup.bash
  source "${ROOT_DIR}/install/setup.bash"
  set -u
}

PX4_PYTHON="${VENV_DIR}/bin/python3"
if [[ ! -x "${PX4_PYTHON}" ]]; then
  PX4_PYTHON="${VENV_DIR}/bin/python"
fi
if [[ ! -x "${PX4_PYTHON}" ]]; then
  echo "PX4 venv python not found under ${VENV_DIR}" >&2
  exit 1
fi
if [[ ! -x "${AGENT_BIN}" ]]; then
  echo "MicroXRCEAgent not found: ${AGENT_BIN}" >&2
  exit 1
fi
if [[ "${CAPTURE_RVIZ}" == "1" && ! -f "${RVIZ_CONFIG}" ]]; then
  echo "RViz config not found: ${RVIZ_CONFIG}" >&2
  exit 1
fi

BUILD_DIR="${PX4_DIR}/build/px4_sitl_default"
PX4_BIN="${BUILD_DIR}/bin/px4"
JINJA_GEN="${PX4_DIR}/Tools/simulation/gazebo-classic/sitl_gazebo-classic/scripts/jinja_gen.py"
MODEL_JINJA="${PX4_DIR}/Tools/simulation/gazebo-classic/sitl_gazebo-classic/models/${MODEL_NAME}/${MODEL_NAME}.sdf.jinja"
GAZEBO_CLASSIC_DIR="${PX4_DIR}/Tools/simulation/gazebo-classic/sitl_gazebo-classic"
WORLD_PATH="${GAZEBO_CLASSIC_DIR}/worlds/${WORLD_NAME}.world"
for path in "${PX4_BIN}" "${JINJA_GEN}" "${MODEL_JINJA}" "${WORLD_PATH}"; do
  if [[ ! -e "${path}" ]]; then
    echo "Required PX4/Gazebo path missing: ${path}" >&2
    exit 1
  fi
done

mkdir -p "${LOG_DIR}" "${RESULT_DIR}" "${SCREENSHOT_DIR}" "${LOG_DIR}/ros"

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
grep -q "running.*port: 8888" "${AGENT_LOG}"

export GAZEBO_PLUGIN_PATH=""
export GAZEBO_MODEL_PATH=""
export GAZEBO_RESOURCE_PATH="/usr/share/gazebo-11"
export LD_LIBRARY_PATH=""
pushd "${PX4_DIR}" >/dev/null
source "${PX4_DIR}/Tools/simulation/gazebo-classic/setup_gazebo.bash" "${PX4_DIR}" "${BUILD_DIR}"
popd >/dev/null

setsid env -i \
  HOME="${HOME:-/home/travis}" \
  USER="${USER:-travis}" \
  PATH="${VENV_DIR}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  GAZEBO_PLUGIN_PATH="${GAZEBO_PLUGIN_PATH:-}" \
  GAZEBO_MODEL_PATH="${GAZEBO_MODEL_PATH:-}" \
  GAZEBO_RESOURCE_PATH="${GAZEBO_RESOURCE_PATH:-/usr/share/gazebo-11}" \
  LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}" \
  gzserver "${WORLD_PATH}" --verbose >"${GAZEBO_LOG}" 2>&1 &
gzserver_pid=$!

for _ in $(seq 1 15); do
  if gz model --list >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

spawn_vehicle() {
  local instance="$1"
  local x="$2"
  local y="$3"
  local working_dir="${BUILD_DIR}/rootfs/${instance}"
  local sdf_file="/tmp/${MODEL_NAME}_${instance}_four_dry_run.sdf"
  mkdir -p "${working_dir}"
  "${PX4_PYTHON}" "${JINJA_GEN}" "${MODEL_JINJA}" "${GAZEBO_CLASSIC_DIR}" \
    --mavlink_tcp_port "$((4560 + instance))" \
    --mavlink_udp_port "$((14560 + instance))" \
    --mavlink_id "$((1 + instance))" \
    --gst_udp_port "$((5600 + instance))" \
    --video_uri "$((5600 + instance))" \
    --mavlink_cam_udp_port "$((14530 + instance))" \
    --output-file "${sdf_file}"
  pushd "${working_dir}" >/dev/null
  setsid env \
    PX4_SIM_MODEL="gazebo-classic_${MODEL_NAME}" \
    ROS_VERSION=2 \
    ROS_DISTRO=humble \
    ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}" \
    "${PX4_BIN}" -i "${instance}" -d "${BUILD_DIR}/etc" >"out.log" 2>"err.log" &
  px4_pids+=("$!")
  popd >/dev/null
  gz model --spawn-file="${sdf_file}" --model-name="${MODEL_NAME}_${instance}" -x "${x}" -y "${y}" -z 0.83 >/dev/null
}

spawn_vehicle 1 0.0 0.0
spawn_vehicle 2 0.0 3.0
spawn_vehicle 3 3.0 0.0
spawn_vehicle 4 3.0 3.0

source_workspace

deadline=$((SECONDS + TIMEOUT_SEC))
topics_ok=false
while (( SECONDS < deadline )); do
  ros2 topic list --no-daemon | sort >"${TOPICS_LOG}" || true
  topics_ok=true
  for instance in 1 2 3 4; do
    if ! grep -q "/px4_${instance}/fmu/out/vehicle_status" "${TOPICS_LOG}" ||
       ! grep -q "/px4_${instance}/fmu/out/vehicle_local_position" "${TOPICS_LOG}"; then
      topics_ok=false
    fi
  done
  if [[ "${topics_ok}" == "true" ]]; then
    break
  fi
  sleep 2
done
if [[ "${topics_ok}" != "true" ]]; then
  echo "Four-vehicle ROS 2 namespaced output topics were not observed." >&2
  cat "${TOPICS_LOG}" >&2 || true
  exit 1
fi

setsid env \
  ROS_LOG_DIR="${LOG_DIR}/ros" \
  RCUTILS_LOGGING_DIRECTORY="${LOG_DIR}/ros" \
  bash -lc "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && ros2 launch zcw_bringup four_vehicle_dry_run_planner.launch.py" >"${PLANNER_LOG}" 2>&1 &
planner_pid=$!

dry_topics_ok=false
while (( SECONDS < deadline )); do
  ros2 topic list --no-daemon | sort >"${TOPICS_LOG}" || true
  dry_topics_ok=true
  for topic in \
    /zcw/multi_vehicle/four_vehicle_dry_run/vehicle_1_goal \
    /zcw/multi_vehicle/four_vehicle_dry_run/vehicle_2_goal \
    /zcw/multi_vehicle/four_vehicle_dry_run/vehicle_3_goal \
    /zcw/multi_vehicle/four_vehicle_dry_run/vehicle_4_goal \
    /zcw/multi_vehicle/four_vehicle_dry_run/topology_state \
    /zcw/multi_vehicle/four_vehicle_dry_run/safety_state \
    /zcw/multi_vehicle/four_vehicle_dry_run/assignment_state \
    /zcw/multi_vehicle/four_vehicle_dry_run/scoring_state; do
    if ! grep -q "${topic}" "${TOPICS_LOG}"; then
      dry_topics_ok=false
    fi
  done
  if [[ "${dry_topics_ok}" == "true" ]]; then
    break
  fi
  sleep 1
done

{
  for instance in 1 2 3 4; do
    echo "--- vehicle_${instance}_goal"
    timeout 10s ros2 topic echo --no-daemon --full-length --once \
      "/zcw/multi_vehicle/four_vehicle_dry_run/vehicle_${instance}_goal" \
      geometry_msgs/msg/PointStamped || true
  done
  echo "--- topology_state"
  timeout 10s ros2 topic echo --no-daemon --full-length --once \
    /zcw/multi_vehicle/four_vehicle_dry_run/topology_state \
    std_msgs/msg/String --filter '"chain_max_distance_m=-1" not in m.data' || true
  echo "--- safety_state"
  timeout 10s ros2 topic echo --no-daemon --full-length --once \
    /zcw/multi_vehicle/four_vehicle_dry_run/safety_state \
    std_msgs/msg/String || true
  echo "--- assignment_state"
  timeout 10s ros2 topic echo --no-daemon --full-length --once \
    /zcw/multi_vehicle/four_vehicle_dry_run/assignment_state \
    std_msgs/msg/String || true
  echo "--- scoring_state"
  timeout 10s ros2 topic echo --no-daemon --full-length --once \
    /zcw/multi_vehicle/four_vehicle_dry_run/scoring_state \
    std_msgs/msg/String || true
} >"${DRY_RUN_SAMPLES_LOG}" 2>&1

{
  echo "Forbidden publisher audit"
  for instance in 1 2 3 4; do
    for suffix in offboard_control_mode trajectory_setpoint vehicle_command; do
      topic="/px4_${instance}/fmu/in/${suffix}"
      echo "--- ${topic}"
      ros2 topic info "${topic}" --no-daemon 2>/dev/null || true
    done
  done
} >"${FORBIDDEN_PUBLISHERS_LOG}" 2>&1

forbidden_ok=true
if rg -n "Publisher count: [1-9]" "${FORBIDDEN_PUBLISHERS_LOG}" >/dev/null; then
  forbidden_ok=false
fi

screenshot_ok=not_requested
if [[ "${CAPTURE_RVIZ}" == "1" ]]; then
  screenshot_ok=0
  setsid env \
    ROS_LOG_DIR="${LOG_DIR}/ros" \
    RCUTILS_LOGGING_DIRECTORY="${LOG_DIR}/ros" \
    bash -lc "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && rviz2 -d '${RVIZ_CONFIG}'" >"${RVIZ_LOG}" 2>&1 &
  rviz_pid=$!
  sleep "${RVIZ_SETTLE_SEC}"
  set +o pipefail
  RVIZ_WINDOW_ID="$(env DISPLAY="${DISPLAY:-}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" xwininfo -root -tree 2>/dev/null | awk '/RViz/ {print $1; exit}')"
  set -o pipefail
  if [[ -n "${RVIZ_WINDOW_ID}" ]] &&
     env DISPLAY="${DISPLAY:-}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" import -window "${RVIZ_WINDOW_ID}" "${SCREENSHOT_FILE}" >/dev/null 2>&1; then
    screenshot_ok=1
  elif env DISPLAY="${DISPLAY:-}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" gnome-screenshot -f "${SCREENSHOT_FILE}" >/dev/null 2>&1; then
    screenshot_ok=1
  elif env DISPLAY="${DISPLAY:-}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" import -window root "${SCREENSHOT_FILE}" >/dev/null 2>&1; then
    screenshot_ok=1
  fi
fi

decision="accepted_four_vehicle_dry_run_smoke"
reason="four_vehicle_dry_run_topics_publish_without_px4_input_publishers"
if [[ "${dry_topics_ok}" != "true" || "${forbidden_ok}" != "true" ]]; then
  decision="rejected_four_vehicle_dry_run_smoke"
  reason="dry_run_topics_or_forbidden_publisher_gate_failed"
elif [[ "${CAPTURE_RVIZ}" == "1" && "${screenshot_ok}" != "1" ]]; then
  decision="rejected_four_vehicle_dry_run_smoke"
  reason="rviz_screenshot_failed"
fi

{
  echo "scope=four_vehicle_dry_run_smoke"
  echo "decision=${decision}"
  echo "reason=${reason}"
  echo "starts_ros=true"
  echo "starts_px4=true"
  echo "starts_gazebo=true"
  echo "starts_rviz=$([[ "${CAPTURE_RVIZ}" == "1" ]] && echo true || echo false)"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "num_vehicles=4"
  echo "dry_topics_ok=${dry_topics_ok}"
  echo "forbidden_publishers_zero=${forbidden_ok}"
  echo "capture_rviz=${CAPTURE_RVIZ}"
  echo "screenshot_ok=${screenshot_ok}"
  for instance in 1 2 3 4; do
    echo "observed_px4_${instance}_vehicle_status=true"
  done
  echo "agent_log=${AGENT_LOG}"
  echo "gazebo_log=${GAZEBO_LOG}"
  echo "planner_log=${PLANNER_LOG}"
  echo "topics_log=${TOPICS_LOG}"
  echo "dry_run_samples_log=${DRY_RUN_SAMPLES_LOG}"
  echo "forbidden_publishers_log=${FORBIDDEN_PUBLISHERS_LOG}"
  echo "rviz_config=${RVIZ_CONFIG}"
  echo "rviz_log=${RVIZ_LOG}"
  echo "screenshot=${SCREENSHOT_FILE}"
} >"${SUMMARY_FILE}"

echo "Four-vehicle dry-run smoke completed."
echo "Summary: ${SUMMARY_FILE}"

if [[ "${decision}" != "accepted_four_vehicle_dry_run_smoke" ]]; then
  exit 1
fi
