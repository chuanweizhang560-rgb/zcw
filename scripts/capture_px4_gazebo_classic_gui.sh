#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PX4_DIR="${PX4_DIR:-${ROOT_DIR}/third_party/PX4-Autopilot-release-1.14}"
VENV_DIR="${PX4_VENV:-${ROOT_DIR}/.venv/px4_venv}"
VERIFY_TIMEOUT_SEC="${VERIFY_TIMEOUT_SEC:-70}"
GUI_SETTLE_SEC="${GUI_SETTLE_SEC:-8}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/logs}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-${ROOT_DIR}/data/screenshots}"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/px4_gazebo_classic_gui_${STAMP}.log}"
SCREENSHOT_FILE="${SCREENSHOT_FILE:-${SCREENSHOT_DIR}/px4_gazebo_classic_gui_${STAMP}.png}"
PX4_SITL_WORLD_VALUE="${PX4_SITL_WORLD:-}"
GAZEBO_MODEL_PATH_VALUE="${GAZEBO_MODEL_PATH:-}"
GAZEBO_PLUGIN_PATH_VALUE="${PX4_EXTRA_GAZEBO_PLUGIN_PATH:-}"
GAZEBO_RESOURCE_PATH_VALUE="${GAZEBO_RESOURCE_PATH:-/usr/share/gazebo-11}"
LD_LIBRARY_PATH_VALUE="${PX4_EXTRA_LD_LIBRARY_PATH:-}"
VERBOSE_SIM_VALUE="${VERBOSE_SIM:-}"
ROS_VERSION_VALUE="${ROS_VERSION:-}"
NO_PXH_VALUE="${NO_PXH:-1}"
PX4_MODEL_VALUE="${PX4_MODEL:-}"
GAZEBO_MAKE_TARGET="${PX4_GAZEBO_TARGET:-gazebo-classic}"

if [[ -n "${PX4_MODEL_VALUE}" ]]; then
  GAZEBO_MAKE_TARGET="gazebo-classic_${PX4_MODEL_VALUE}"
fi

if [[ "${ROS_VERSION_VALUE}" == "2" ]]; then
  GAZEBO_PLUGIN_PATH_VALUE="/opt/ros/humble/lib${GAZEBO_PLUGIN_PATH_VALUE:+:${GAZEBO_PLUGIN_PATH_VALUE}}"
  LD_LIBRARY_PATH_VALUE="/opt/ros/humble/lib${LD_LIBRARY_PATH_VALUE:+:${LD_LIBRARY_PATH_VALUE}}"
fi

px4_pid=""

cleanup() {
  if [[ -n "${px4_pid}" ]]; then
    kill -TERM -- "-${px4_pid}" >/dev/null 2>&1 || true
    wait "${px4_pid}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ -z "${DISPLAY:-}" ]]; then
  echo "DISPLAY is not set; cannot capture Gazebo GUI." >&2
  exit 1
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

mkdir -p "${LOG_DIR}" "${SCREENSHOT_DIR}"

cd "${PX4_DIR}"
echo "PX4/Gazebo Classic make target: ${GAZEBO_MAKE_TARGET}" >"${LOG_FILE}"

setsid env -i \
  HOME="${HOME:-/home/travis}" \
  USER="${USER:-travis}" \
  DISPLAY="${DISPLAY}" \
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
  NO_PXH="${NO_PXH_VALUE}" \
  QT_X11_NO_MITSHM=1 \
  LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}" \
  make px4_sitl "${GAZEBO_MAKE_TARGET}" >>"${LOG_FILE}" 2>&1 &
px4_pid=$!

for _ in $(seq 1 "${VERIFY_TIMEOUT_SEC}"); do
  if [[ -f "${LOG_FILE}" ]] &&
     grep -q "Simulator connected on TCP port 4560" "${LOG_FILE}" &&
     grep -q "Startup script returned successfully" "${LOG_FILE}"; then
    sleep "${GUI_SETTLE_SEC}"

    if env DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
      gnome-screenshot -f "${SCREENSHOT_FILE}" >/dev/null 2>&1; then
      :
    elif env DISPLAY="${DISPLAY}" XAUTHORITY="${XAUTHORITY:-}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
      import -window root "${SCREENSHOT_FILE}" >/dev/null 2>&1; then
      :
    else
      echo "Screenshot capture failed." >&2
      exit 1
    fi

    if [[ ! -s "${SCREENSHOT_FILE}" ]]; then
      echo "Screenshot file is empty: ${SCREENSHOT_FILE}" >&2
      exit 1
    fi

    echo "PX4/Gazebo Classic GUI screenshot captured."
    echo "PX4/Gazebo log: ${LOG_FILE}"
    echo "Screenshot: ${SCREENSHOT_FILE}"
    exit 0
  fi

  sleep 1
done

echo "Timed out before expected PX4/Gazebo GUI launch markers appeared." >&2
tail -n 80 "${LOG_FILE}" >&2 || true
exit 124
