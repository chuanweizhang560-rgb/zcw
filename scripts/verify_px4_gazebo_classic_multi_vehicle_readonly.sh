#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PX4_DIR="${PX4_DIR:-${ROOT_DIR}/third_party/PX4-Autopilot-release-1.14}"
VENV_DIR="${PX4_VENV:-${ROOT_DIR}/.venv/px4_venv}"
AGENT_BIN="${AGENT_BIN:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean/MicroXRCEAgent}"
AGENT_LIB_DIR="${AGENT_LIB_DIR:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${RESULT_ROOT}/multi_vehicle_readonly_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/multi_vehicle_readonly_${STAMP}.txt"
AGENT_LOG="${LOG_DIR}/multi_vehicle_agent_${STAMP}.log"
GAZEBO_LOG="${LOG_DIR}/multi_vehicle_gzserver_${STAMP}.log"
TOPICS_LOG="${LOG_DIR}/multi_vehicle_topics_${STAMP}.log"
FORBIDDEN_PUBLISHERS_LOG="${LOG_DIR}/multi_vehicle_forbidden_publishers_${STAMP}.log"
TIMEOUT_SEC="${TIMEOUT_SEC:-75}"
WORLD_NAME="${WORLD_NAME:-empty}"
MODEL_NAME="${MODEL_NAME:-iris}"
NUM_VEHICLES="${NUM_VEHICLES:-2}"

if ! [[ "${NUM_VEHICLES}" =~ ^[0-9]+$ ]] || (( NUM_VEHICLES < 2 || NUM_VEHICLES > 4 )); then
  echo "NUM_VEHICLES must be an integer from 2 to 4 for this read-only smoke." >&2
  exit 1
fi

agent_pid=""
gzserver_pid=""
px4_pids=()

cleanup() {
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
  pkill -TERM -f "${PX4_DIR}/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
  pkill -TERM -f "gzserver .*sitl_gazebo-classic/worlds/${WORLD_NAME}\\.world" >/dev/null 2>&1 || true
}
trap cleanup EXIT

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

mkdir -p "${LOG_DIR}" "${RESULT_DIR}"

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
  tail -n 80 "${AGENT_LOG}" >&2 || true
  exit 1
fi

# Force a clean Gazebo/PX4 environment. Do not inherit old project paths.
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
  local sdf_file="/tmp/${MODEL_NAME}_${instance}_readonly.sdf"
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

vehicle_spawn_xy() {
  local instance="$1"
  case "${instance}" in
    1) echo "0.0 0.0" ;;
    2) echo "0.0 3.0" ;;
    3) echo "3.0 0.0" ;;
    4) echo "3.0 3.0" ;;
    *) return 1 ;;
  esac
}

for instance in $(seq 1 "${NUM_VEHICLES}"); do
  read -r spawn_x spawn_y < <(vehicle_spawn_xy "${instance}")
  spawn_vehicle "${instance}" "${spawn_x}" "${spawn_y}"
done

deadline=$((SECONDS + TIMEOUT_SEC))
topics_ok=false
while (( SECONDS < deadline )); do
  set +e
  timeout 8s env -i \
    HOME="${HOME:-/home/travis}" \
    USER="${USER:-travis}" \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    /bin/bash -c "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && ros2 topic list --no-daemon | sort" >"${TOPICS_LOG}" 2>&1
  topic_status=$?
  set -e

  if [[ "${topic_status}" -eq 0 ]]; then
    topics_ok=true
    for instance in $(seq 1 "${NUM_VEHICLES}"); do
      if ! grep -q "/px4_${instance}/fmu/out/vehicle_status" "${TOPICS_LOG}"; then
        topics_ok=false
      fi
    done
  fi
  if [[ "${topics_ok}" == "true" ]]; then
    break
  fi
  sleep 2
done

if [[ "${topics_ok}" != "true" ]]; then
  echo "${NUM_VEHICLES}-vehicle ROS 2 namespaced output topics were not observed." >&2
  tail -n 120 "${TOPICS_LOG}" >&2 || true
  exit 1
fi

{
  echo "Forbidden publisher audit"
  for topic in /fmu/in/offboard_control_mode /fmu/in/trajectory_setpoint /fmu/in/vehicle_command; do
    echo "--- ${topic}"
    timeout 5s env -i \
      HOME="${HOME:-/home/travis}" \
      USER="${USER:-travis}" \
      PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
      /bin/bash -c "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && ros2 topic info '${topic}' --no-daemon 2>/dev/null || true"
  done
  for instance in $(seq 1 "${NUM_VEHICLES}"); do
    for suffix in offboard_control_mode trajectory_setpoint vehicle_command; do
      topic="/px4_${instance}/fmu/in/${suffix}"
      echo "--- ${topic}"
      timeout 5s env -i \
        HOME="${HOME:-/home/travis}" \
        USER="${USER:-travis}" \
        PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        /bin/bash -c "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && ros2 topic info '${topic}' --no-daemon 2>/dev/null || true"
    done
  done
} >"${FORBIDDEN_PUBLISHERS_LOG}" 2>&1

forbidden_ok=true
if rg -n "Publisher count: [1-9]" "${FORBIDDEN_PUBLISHERS_LOG}" >/dev/null; then
  forbidden_ok=false
fi

{
  echo "scope=multi_vehicle_readonly"
  echo "decision=accepted_multi_vehicle_readonly_smoke"
  echo "reason=${NUM_VEHICLES}_px4_instances_publish_namespaced_ros2_outputs_without_project_fmu_in_publishers"
  echo "starts_ros=true"
  echo "starts_px4=true"
  echo "starts_gazebo=true"
  echo "starts_rviz=false"
  echo "starts_offboard=false"
  echo "arms=false"
  echo "publishes_fmu_in=false"
  echo "num_vehicles=${NUM_VEHICLES}"
  for instance in $(seq 1 "${NUM_VEHICLES}"); do
    echo "observed_px4_${instance}_vehicle_status=true"
  done
  echo "forbidden_publishers_zero=${forbidden_ok}"
  echo "agent_log=${AGENT_LOG}"
  echo "gazebo_log=${GAZEBO_LOG}"
  echo "topics_log=${TOPICS_LOG}"
  echo "forbidden_publishers_log=${FORBIDDEN_PUBLISHERS_LOG}"
  echo "clean_gazebo_env=true"
} >"${SUMMARY_FILE}"

if [[ "${forbidden_ok}" != "true" ]]; then
  sed -i 's/^decision=.*/decision=rejected_multi_vehicle_readonly_smoke/' "${SUMMARY_FILE}"
  sed -i 's/^reason=.*/reason=forbidden_fmu_in_publisher_detected/' "${SUMMARY_FILE}"
  cat "${SUMMARY_FILE}" >&2
  exit 1
fi

echo "PX4 Gazebo Classic multi-vehicle readonly smoke verified."
echo "Summary: ${SUMMARY_FILE}"
