#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PX4_DIR="${PX4_DIR:-${ROOT_DIR}/third_party/PX4-Autopilot-release-1.14}"
VENV_DIR="${PX4_VENV:-/tmp/codex_zcw_px4_venv}"
TIMEOUT_SEC="${TIMEOUT_SEC:-45}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/px4_gazebo_classic_headless_$(date +%Y%m%d_%H%M%S).log}"
PX4_SITL_WORLD_VALUE="${PX4_SITL_WORLD:-}"
GAZEBO_MODEL_PATH_VALUE="${GAZEBO_MODEL_PATH:-}"
GAZEBO_PLUGIN_PATH_VALUE="${PX4_EXTRA_GAZEBO_PLUGIN_PATH:-}"
GAZEBO_RESOURCE_PATH_VALUE="${GAZEBO_RESOURCE_PATH:-/usr/share/gazebo-11}"
LD_LIBRARY_PATH_VALUE="${PX4_EXTRA_LD_LIBRARY_PATH:-}"
GAZEBO_SYSTEM_PLUGIN_DIR="${GAZEBO_SYSTEM_PLUGIN_DIR:-/usr/lib/x86_64-linux-gnu/gazebo-11/plugins}"
VERBOSE_SIM_VALUE="${VERBOSE_SIM:-}"
ROS_VERSION_VALUE="${ROS_VERSION:-}"
AMENT_PREFIX_PATH_VALUE="${AMENT_PREFIX_PATH:-}"
CMAKE_PREFIX_PATH_VALUE="${CMAKE_PREFIX_PATH:-}"
COLCON_PREFIX_PATH_VALUE="${COLCON_PREFIX_PATH:-}"
ROS_DISTRO_VALUE="${ROS_DISTRO:-}"
ROS_PYTHON_VERSION_VALUE="${ROS_PYTHON_VERSION:-}"
NO_PXH_VALUE="${NO_PXH:-1}"
PX4_MODEL_VALUE="${PX4_MODEL:-}"
PX4_DIRECT_MODEL_VALUE="${PX4_DIRECT_MODEL:-0}"
PX4_SYS_AUTOSTART_VALUE="${PX4_SYS_AUTOSTART:-}"
PX4_HEADLESS_VALUE="${PX4_HEADLESS-1}"
GAZEBO_MAKE_TARGET="${PX4_GAZEBO_TARGET:-gazebo-classic}"

if [[ -z "${PX4_GAZEBO_TARGET:-}" && -n "${PX4_MODEL_VALUE}" ]]; then
  GAZEBO_MAKE_TARGET="gazebo-classic_${PX4_MODEL_VALUE}"
fi

if [[ -d "${GAZEBO_SYSTEM_PLUGIN_DIR}" ]]; then
  GAZEBO_PLUGIN_PATH_VALUE="${GAZEBO_SYSTEM_PLUGIN_DIR}${GAZEBO_PLUGIN_PATH_VALUE:+:${GAZEBO_PLUGIN_PATH_VALUE}}"
  LD_LIBRARY_PATH_VALUE="${GAZEBO_SYSTEM_PLUGIN_DIR}${LD_LIBRARY_PATH_VALUE:+:${LD_LIBRARY_PATH_VALUE}}"
fi

if [[ "${ROS_VERSION_VALUE}" == "2" ]]; then
  GAZEBO_PLUGIN_PATH_VALUE="/opt/ros/humble/lib${GAZEBO_PLUGIN_PATH_VALUE:+:${GAZEBO_PLUGIN_PATH_VALUE}}"
  LD_LIBRARY_PATH_VALUE="/opt/ros/humble/lib${LD_LIBRARY_PATH_VALUE:+:${LD_LIBRARY_PATH_VALUE}}"
  AMENT_PREFIX_PATH_VALUE="${AMENT_PREFIX_PATH_VALUE:-/opt/ros/humble}"
  CMAKE_PREFIX_PATH_VALUE="${CMAKE_PREFIX_PATH_VALUE:-/opt/ros/humble}"
  COLCON_PREFIX_PATH_VALUE="${COLCON_PREFIX_PATH_VALUE:-/opt/ros/humble}"
  ROS_DISTRO_VALUE="${ROS_DISTRO_VALUE:-humble}"
  ROS_PYTHON_VERSION_VALUE="${ROS_PYTHON_VERSION_VALUE:-3}"
fi

if [[ ! -d "${PX4_DIR}" ]]; then
  echo "PX4 directory not found: ${PX4_DIR}" >&2
  exit 1
fi

if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
  echo "PX4 venv python not found: ${VENV_DIR}/bin/python" >&2
  echo "Run scripts/setup_px4_venv.sh first." >&2
  exit 1
fi

cleanup_simulation_processes() {
  pkill -TERM -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
  pkill -TERM -f "${ROOT_DIR}.*/Tools/simulation/gazebo-classic/sitl_run.sh" >/dev/null 2>&1 || true
  pkill -TERM -f "gzserver .*${ROOT_DIR}.*/.*\\.world" >/dev/null 2>&1 || true
  sleep 2
  pkill -KILL -f "${ROOT_DIR}.*/build/px4_sitl_default/bin/px4" >/dev/null 2>&1 || true
  pkill -KILL -f "${ROOT_DIR}.*/Tools/simulation/gazebo-classic/sitl_run.sh" >/dev/null 2>&1 || true
  pkill -KILL -f "gzserver .*${ROOT_DIR}.*/.*\\.world" >/dev/null 2>&1 || true
}
trap cleanup_simulation_processes EXIT

mkdir -p "${LOG_DIR}"

cd "${PX4_DIR}"
echo "PX4/Gazebo Classic make target: ${GAZEBO_MAKE_TARGET}" >"${LOG_FILE}"
echo "PX4/Gazebo Classic direct model mode: ${PX4_DIRECT_MODEL_VALUE}" >>"${LOG_FILE}"
echo "PX4/Gazebo Classic HEADLESS value: ${PX4_HEADLESS_VALUE}" >>"${LOG_FILE}"

set +e
if [[ "${PX4_DIRECT_MODEL_VALUE}" == "1" ]]; then
  timeout "${TIMEOUT_SEC}s" env -i \
    HOME="${HOME:-/home/travis}" \
    USER="${USER:-travis}" \
    DISPLAY="${DISPLAY:-}" \
    XAUTHORITY="${XAUTHORITY:-}" \
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
    PATH="${VENV_DIR}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    PYTHON_EXECUTABLE="${VENV_DIR}/bin/python" \
    PX4_SITL_WORLD="${PX4_SITL_WORLD_VALUE}" \
    GAZEBO_PLUGIN_PATH="${GAZEBO_PLUGIN_PATH_VALUE}" \
    GAZEBO_MODEL_PATH="${GAZEBO_MODEL_PATH_VALUE}" \
    GAZEBO_RESOURCE_PATH="${GAZEBO_RESOURCE_PATH_VALUE}" \
    LD_LIBRARY_PATH="${LD_LIBRARY_PATH_VALUE}" \
    VERBOSE_SIM="${VERBOSE_SIM_VALUE}" \
    ROS_VERSION="${ROS_VERSION_VALUE}" \
    AMENT_PREFIX_PATH="${AMENT_PREFIX_PATH_VALUE}" \
    CMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH_VALUE}" \
    COLCON_PREFIX_PATH="${COLCON_PREFIX_PATH_VALUE}" \
    ROS_DISTRO="${ROS_DISTRO_VALUE}" \
    ROS_PYTHON_VERSION="${ROS_PYTHON_VERSION_VALUE}" \
    NO_PXH="${NO_PXH_VALUE}" \
    PX4_SYS_AUTOSTART="${PX4_SYS_AUTOSTART_VALUE}" \
    HEADLESS="${PX4_HEADLESS_VALUE}" \
    QT_X11_NO_MITSHM=1 \
    LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}" \
    "${PX4_DIR}/Tools/simulation/gazebo-classic/sitl_run.sh" \
      "${PX4_DIR}/build/px4_sitl_default/bin/px4" \
      none \
      "${PX4_MODEL_VALUE:-iris}" \
      none \
      "${PX4_DIR}" \
      "${PX4_DIR}/build/px4_sitl_default" >>"${LOG_FILE}" 2>&1
else
  timeout "${TIMEOUT_SEC}s" env -i \
    HOME="${HOME:-/home/travis}" \
    USER="${USER:-travis}" \
    DISPLAY="${DISPLAY:-}" \
    XAUTHORITY="${XAUTHORITY:-}" \
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
    PATH="${VENV_DIR}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    PYTHON_EXECUTABLE="${VENV_DIR}/bin/python" \
    PX4_SITL_WORLD="${PX4_SITL_WORLD_VALUE}" \
    GAZEBO_PLUGIN_PATH="${GAZEBO_PLUGIN_PATH_VALUE}" \
    GAZEBO_MODEL_PATH="${GAZEBO_MODEL_PATH_VALUE}" \
    GAZEBO_RESOURCE_PATH="${GAZEBO_RESOURCE_PATH_VALUE}" \
    LD_LIBRARY_PATH="${LD_LIBRARY_PATH_VALUE}" \
    VERBOSE_SIM="${VERBOSE_SIM_VALUE}" \
    ROS_VERSION="${ROS_VERSION_VALUE}" \
    AMENT_PREFIX_PATH="${AMENT_PREFIX_PATH_VALUE}" \
    CMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH_VALUE}" \
    COLCON_PREFIX_PATH="${COLCON_PREFIX_PATH_VALUE}" \
    ROS_DISTRO="${ROS_DISTRO_VALUE}" \
    ROS_PYTHON_VERSION="${ROS_PYTHON_VERSION_VALUE}" \
    NO_PXH="${NO_PXH_VALUE}" \
    PX4_SYS_AUTOSTART="${PX4_SYS_AUTOSTART_VALUE}" \
    HEADLESS="${PX4_HEADLESS_VALUE}" \
    QT_X11_NO_MITSHM=1 \
    LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}" \
    make px4_sitl "${GAZEBO_MAKE_TARGET}" >>"${LOG_FILE}" 2>&1
fi
status=$?
set -e
cleanup_simulation_processes
trap - EXIT

echo "PX4/Gazebo Classic log: ${LOG_FILE}"

if [[ "${status}" -eq 124 ]]; then
  if grep -q "Simulator connected on TCP port 4560" "${LOG_FILE}" &&
     grep -q "Startup script returned successfully" "${LOG_FILE}"; then
    echo "Headless launch verified before timeout (${TIMEOUT_SEC}s)."
    exit 0
  fi

  echo "Timed out before expected launch markers appeared." >&2
  tail -n 80 "${LOG_FILE}" >&2
  exit 124
fi

if [[ "${status}" -ne 0 ]]; then
  echo "PX4/Gazebo Classic launch failed with status ${status}." >&2
  tail -n 80 "${LOG_FILE}" >&2
  exit "${status}"
fi

if grep -q "Simulator connected on TCP port 4560" "${LOG_FILE}" &&
   grep -q "Startup script returned successfully" "${LOG_FILE}"; then
  echo "Headless launch verified."
  exit 0
fi

echo "Launch exited without expected verification markers." >&2
tail -n 80 "${LOG_FILE}" >&2
exit 1
