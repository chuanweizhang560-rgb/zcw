#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PX4_DIR="${PX4_DIR:-${ROOT_DIR}/third_party/PX4-Autopilot-release-1.14}"
VENV_DIR="${PX4_VENV:-${ROOT_DIR}/.venv/px4_venv}"

if [[ ! -d "${PX4_DIR}" ]]; then
  echo "PX4 directory not found: ${PX4_DIR}" >&2
  exit 1
fi

if [[ ! -f "${PX4_DIR}/Tools/setup/requirements.txt" ]]; then
  echo "PX4 requirements file not found under: ${PX4_DIR}" >&2
  exit 1
fi

if ! command -v /usr/bin/python3 >/dev/null 2>&1; then
  echo "/usr/bin/python3 is required for the PX4 venv" >&2
  exit 1
fi

/usr/bin/python3 -m venv "${VENV_DIR}"
# PX4 release/1.14 has legacy requirement specifiers such as
# matplotlib>=3.0.* that modern pip rejects. Keep pip on the 23.x parser.
"${VENV_DIR}/bin/python" -m pip install "pip<24"
"${VENV_DIR}/bin/python" -m pip install -r "${PX4_DIR}/Tools/setup/requirements.txt"

# PX4 release/1.14 expects the empy 3.x API. The requirements file may pull
# empy 4.x on a modern PyPI mirror, which breaks code generation.
"${VENV_DIR}/bin/python" -m pip install "empy==3.3.4" --force-reinstall

echo "PX4 venv ready: ${VENV_DIR}"
