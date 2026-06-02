#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_DIR="${AGENT_DIR:-${ROOT_DIR}/third_party/Micro-XRCE-DDS-Agent-v2.2.1}"
BUILD_DIR="${AGENT_BUILD_DIR:-${AGENT_DIR}/build_clean}"
INSTALL_DIR="${AGENT_INSTALL_DIR:-${AGENT_DIR}/install_clean}"
JOBS="${JOBS:-4}"

if [[ ! -d "${AGENT_DIR}" ]]; then
  echo "Micro-XRCE-DDS-Agent source not found: ${AGENT_DIR}" >&2
  exit 1
fi

env -i \
  HOME="${HOME:-/home/travis}" \
  USER="${USER:-travis}" \
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  AGENT_DIR="${AGENT_DIR}" \
  BUILD_DIR="${BUILD_DIR}" \
  INSTALL_DIR="${INSTALL_DIR}" \
  JOBS="${JOBS}" \
  /bin/bash -c '
    set -eo pipefail
    source /opt/ros/humble/setup.bash
    set -u
    cmake -S "${AGENT_DIR}" -B "${BUILD_DIR}" -G Ninja \
      -DUAGENT_SUPERBUILD=OFF \
      -DUAGENT_USE_SYSTEM_FASTDDS=ON \
      -DUAGENT_USE_SYSTEM_FASTCDR=ON \
      -DUAGENT_USE_SYSTEM_LOGGER=ON \
      -DUAGENT_P2P_PROFILE=OFF \
      -DUAGENT_BUILD_TESTS=OFF \
      -DCMAKE_BUILD_TYPE=Release \
      -Dfmt_DIR=/usr/lib/x86_64-linux-gnu/cmake/fmt \
      -Dspdlog_DIR=/usr/lib/x86_64-linux-gnu/cmake/spdlog \
      -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}"
    cmake --build "${BUILD_DIR}" --target MicroXRCEAgent -j "${JOBS}"
  '

if ldd "${BUILD_DIR}/MicroXRCEAgent" | grep -q "/home/travis/miniconda3"; then
  echo "MicroXRCEAgent is linked against conda libraries; rebuild rejected." >&2
  ldd "${BUILD_DIR}/MicroXRCEAgent" >&2
  exit 1
fi

echo "MicroXRCEAgent ready: ${BUILD_DIR}/MicroXRCEAgent"
