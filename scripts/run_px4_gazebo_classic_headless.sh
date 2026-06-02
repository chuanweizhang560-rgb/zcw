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
GAZEBO_RESOURCE_PATH_VALUE="${GAZEBO_RESOURCE_PATH:-/usr/share/gazebo-11}"
VERBOSE_SIM_VALUE="${VERBOSE_SIM:-}"

if [[ ! -d "${PX4_DIR}" ]]; then
  echo "PX4 directory not found: ${PX4_DIR}" >&2
  exit 1
fi

if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
  echo "PX4 venv python not found: ${VENV_DIR}/bin/python" >&2
  echo "Run scripts/setup_px4_venv.sh first." >&2
  exit 1
fi

mkdir -p "${LOG_DIR}"

cd "${PX4_DIR}"

set +e
timeout "${TIMEOUT_SEC}s" env -i \
  HOME="${HOME:-/home/travis}" \
  USER="${USER:-travis}" \
  PATH="${VENV_DIR}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  PYTHON_EXECUTABLE="${VENV_DIR}/bin/python" \
  PX4_SITL_WORLD="${PX4_SITL_WORLD_VALUE}" \
  GAZEBO_MODEL_PATH="${GAZEBO_MODEL_PATH_VALUE}" \
  GAZEBO_RESOURCE_PATH="${GAZEBO_RESOURCE_PATH_VALUE}" \
  VERBOSE_SIM="${VERBOSE_SIM_VALUE}" \
  HEADLESS=1 \
  make px4_sitl gazebo-classic >"${LOG_FILE}" 2>&1
status=$?
set -e

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
