#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${GEOMETRY_VENV:-${ROOT_DIR}/.venv/geometry}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

"${PYTHON_BIN}" -m venv "${VENV_DIR}"
"${VENV_DIR}/bin/python" -m pip install --upgrade pip
"${VENV_DIR}/bin/python" -m pip install \
  "trimesh==4.12.2" \
  "rtree==1.4.1" \
  "pycollada==0.9.3"

echo "Geometry venv ready: ${VENV_DIR}"
