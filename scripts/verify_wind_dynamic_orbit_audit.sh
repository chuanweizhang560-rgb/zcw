#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_BIN="${AGENT_BIN:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean/MicroXRCEAgent}"
AGENT_LIB_DIR="${AGENT_LIB_DIR:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1/build_clean}"
PX4_SCRIPT="${PX4_SCRIPT:-${ROOT_DIR}/scripts/run_px4_aerialcore_world_headless.sh}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${RESULT_ROOT}/wind_dynamic_orbit_audit_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/wind_dynamic_orbit_audit_wrapper_${STAMP}.txt"
AGENT_LOG="${LOG_DIR}/wind_dynamic_orbit_agent_${STAMP}.log"
PX4_LOG="${LOG_DIR}/wind_dynamic_orbit_px4_${STAMP}.log"
PX4_WRAPPER_LOG="${PX4_LOG}.wrapper"
OFFBOARD_LOG="${LOG_DIR}/wind_dynamic_orbit_offboard_${STAMP}.log"
AUDIT_LOG="${LOG_DIR}/wind_dynamic_orbit_audit_node_${STAMP}.log"
STATUS_LOG="${LOG_DIR}/wind_dynamic_orbit_vehicle_status_${STAMP}.log"
TOPICS_LOG="${LOG_DIR}/wind_dynamic_orbit_topics_${STAMP}.log"

VERIFY_TIMEOUT_SEC="${VERIFY_TIMEOUT_SEC:-95}"
PX4_TIMEOUT_SEC="${PX4_TIMEOUT_SEC:-180}"
PRE_AUDIT_SETTLE_SEC="${PRE_AUDIT_SETTLE_SEC:-35}"
AUDIT_TIMEOUT_SEC="${AUDIT_TIMEOUT_SEC:-70}"
AUDIT_DURATION_SEC="${AUDIT_DURATION_SEC:-45}"
AUDIT_SAMPLE_RATE_HZ="${AUDIT_SAMPLE_RATE_HZ:-10}"
OFFBOARD_LAUNCH_FILE="${OFFBOARD_LAUNCH_FILE:-single_vehicle_wind_turbine_multilevel_orbit.launch.py}"
EXPECTED_RADIUS_M="${EXPECTED_RADIUS_M:-20.0}"
MIN_WAYPOINT_ADVANCEMENTS="${MIN_WAYPOINT_ADVANCEMENTS:-8}"
CONSERVATIVE_MESH_RADIUS_M="${CONSERVATIVE_MESH_RADIUS_M:-11.880407}"
MIN_CLEARANCE_M="${MIN_CLEARANCE_M:-1.0}"
MAX_RADIUS_ERROR_M="${MAX_RADIUS_ERROR_M:-8.0}"

agent_pid=""
px4_pid=""
offboard_pid=""

source_workspace() {
  set +u
  source /opt/ros/humble/setup.bash
  source "${ROOT_DIR}/install/setup.bash"
  set -u
}

as_ros_double() {
  local value="$1"
  if [[ "${value}" =~ ^-?[0-9]+$ ]]; then
    printf '%s.0' "${value}"
  else
    printf '%s' "${value}"
  fi
}

cleanup() {
  for pid in "${offboard_pid}" "${px4_pid}" "${agent_pid}"; do
    if [[ -n "${pid}" ]]; then
      kill -TERM -- "-${pid}" >/dev/null 2>&1 || true
      wait "${pid}" >/dev/null 2>&1 || true
    fi
  done
  pkill -TERM -f "${OFFBOARD_LAUNCH_FILE}" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/wind_turbine_autospawn.world" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
  sleep 2
  pkill -KILL -f "${OFFBOARD_LAUNCH_FILE}" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/wind_turbine_autospawn.world" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "${LOG_DIR}" "${RESULT_DIR}" "${LOG_DIR}/ros"

if [[ ! -x "${AGENT_BIN}" ]]; then
  echo "MicroXRCEAgent not found: ${AGENT_BIN}" >&2
  exit 1
fi
if [[ ! -x "${PX4_SCRIPT}" ]]; then
  echo "PX4 script not found: ${PX4_SCRIPT}" >&2
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
  PX4_DIRECT_MODEL=1 \
  PX4_HEADLESS="${PX4_HEADLESS-}" \
  PX4_SYS_AUTOSTART=10015 \
  PX4_MODEL=iris_depth_camera \
  AERIALCORE_WORLD=wind_turbine \
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
  echo "PX4/Gazebo wind world did not reach ready state." >&2
  tail -n 120 "${PX4_LOG}" >&2 || true
  exit 1
fi

source_workspace

for _ in $(seq 1 "${VERIFY_TIMEOUT_SEC}"); do
  ros2 topic list --no-daemon | sort >"${TOPICS_LOG}" || true
  if grep -q '^/fmu/out/vehicle_status$' "${TOPICS_LOG}" &&
     grep -q '^/fmu/out/vehicle_local_position$' "${TOPICS_LOG}" &&
     grep -q '^/camera/depth/image_raw$' "${TOPICS_LOG}"; then
    break
  fi
  sleep 1
done
for topic in /fmu/out/vehicle_status /fmu/out/vehicle_local_position /camera/depth/image_raw; do
  if ! grep -q "^${topic}$" "${TOPICS_LOG}"; then
    echo "Required wind dynamic audit topic missing: ${topic}" >&2
    cat "${TOPICS_LOG}" >&2 || true
    exit 1
  fi
done

setsid env \
  ROS_LOG_DIR="${LOG_DIR}/ros" \
  RCUTILS_LOGGING_DIRECTORY="${LOG_DIR}/ros" \
  bash -lc "source /opt/ros/humble/setup.bash && source '${ROOT_DIR}/install/setup.bash' && ros2 launch zcw_bringup '${OFFBOARD_LAUNCH_FILE}'" >"${OFFBOARD_LOG}" 2>&1 &
offboard_pid=$!

sleep "${PRE_AUDIT_SETTLE_SEC}"

audit_exit=0
timeout "${AUDIT_TIMEOUT_SEC}s" ros2 run zcw_px4_baseline wind_dynamic_orbit_audit --ros-args \
  -p output_dir:="${RESULT_DIR}" \
  -p duration_sec:="$(as_ros_double "${AUDIT_DURATION_SEC}")" \
  -p sample_rate_hz:="$(as_ros_double "${AUDIT_SAMPLE_RATE_HZ}")" \
  -p expected_radius_m:="$(as_ros_double "${EXPECTED_RADIUS_M}")" \
  -p conservative_mesh_radius_m:="$(as_ros_double "${CONSERVATIVE_MESH_RADIUS_M}")" \
  -p min_clearance_m:="$(as_ros_double "${MIN_CLEARANCE_M}")" \
  -p max_radius_error_m:="$(as_ros_double "${MAX_RADIUS_ERROR_M}")" >"${AUDIT_LOG}" 2>&1 || audit_exit=$?

timeout 8s ros2 topic echo --once /fmu/out/vehicle_status >"${STATUS_LOG}" 2>&1 || true

waypoint_advancements=0
if [[ -f "${OFFBOARD_LOG}" ]]; then
  waypoint_advancements="$(grep -c "Advancing to waypoint" "${OFFBOARD_LOG}" || true)"
fi

audit_summary="$(find "${RESULT_DIR}" -maxdepth 1 -type f -name 'wind_dynamic_orbit_audit_*.txt' ! -name '*wrapper*' | sort | tail -n 1)"
audit_decision="missing_wind_dynamic_orbit_audit"
pose_samples=""
depth_frames=""
min_clearance=""
mean_useful_ratio=""
max_useful_ratio=""
if [[ -n "${audit_summary}" && -s "${audit_summary}" ]]; then
  audit_decision="$(awk -F= '/^decision=/ {print $2; exit}' "${audit_summary}")"
  pose_samples="$(awk -F= '/^pose_samples=/ {print $2; exit}' "${audit_summary}")"
  depth_frames="$(awk -F= '/^depth_frames=/ {print $2; exit}' "${audit_summary}")"
  min_clearance="$(awk -F= '/^min_conservative_clearance_m=/ {print $2; exit}' "${audit_summary}")"
  mean_useful_ratio="$(awk -F= '/^mean_useful_ratio=/ {print $2; exit}' "${audit_summary}")"
  max_useful_ratio="$(awk -F= '/^max_useful_ratio=/ {print $2; exit}' "${audit_summary}")"
fi

motion_ok=false
if grep -q "arming_state: 2" "${STATUS_LOG}" &&
   grep -q "nav_state: 14" "${STATUS_LOG}" &&
   [[ "${waypoint_advancements}" -ge "${MIN_WAYPOINT_ADVANCEMENTS}" ]]; then
  motion_ok=true
fi

decision="accepted_wind_dynamic_orbit_wrapper"
reason="wind_rule_baseline_motion_and_dynamic_audit_passed"
if [[ "${audit_decision}" != "accepted_wind_dynamic_orbit_audit" || "${motion_ok}" != "true" ]]; then
  decision="rejected_wind_dynamic_orbit_wrapper"
  reason="wind_dynamic_audit_or_motion_gate_failed"
fi

{
  echo "scope=wind_dynamic_orbit_wrapper"
  echo "decision=${decision}"
  echo "reason=${reason}"
  echo "world=wind_turbine"
  echo "model=iris_depth_camera"
  echo "launch=${OFFBOARD_LAUNCH_FILE}"
  echo "starts_ros=true"
  echo "starts_px4=true"
  echo "starts_gazebo=true"
  echo "starts_rviz=false"
  echo "starts_offboard=true"
  echo "arms=true"
  echo "publishes_fmu_in=true"
  echo "cable_phase_b_active=false"
  echo "min_waypoint_advancements=${MIN_WAYPOINT_ADVANCEMENTS}"
  echo "waypoint_advancements=${waypoint_advancements}"
  echo "motion_ok=${motion_ok}"
  echo "expected_radius_m=${EXPECTED_RADIUS_M}"
  echo "audit_exit=${audit_exit}"
  echo "audit_decision=${audit_decision}"
  echo "pose_samples=${pose_samples}"
  echo "depth_frames=${depth_frames}"
  echo "min_conservative_clearance_m=${min_clearance}"
  echo "mean_useful_ratio=${mean_useful_ratio}"
  echo "max_useful_ratio=${max_useful_ratio}"
  echo "audit_summary=${audit_summary}"
  echo "agent_log=${AGENT_LOG}"
  echo "px4_log=${PX4_LOG}"
  echo "offboard_log=${OFFBOARD_LOG}"
  echo "audit_log=${AUDIT_LOG}"
  echo "status_log=${STATUS_LOG}"
  echo "topics_log=${TOPICS_LOG}"
} >"${SUMMARY_FILE}"

echo "Wind dynamic orbit audit completed."
echo "Summary: ${SUMMARY_FILE}"

if [[ "${decision}" != "accepted_wind_dynamic_orbit_wrapper" ]]; then
  exit 1
fi
