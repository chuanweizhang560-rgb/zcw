#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
SCREENSHOT_DIR="${SCREENSHOT_DIR:-${ROOT_DIR}/data/screenshots}"
FRAME_INDEX="${FRAME_INDEX:-0}"
SETTLE_SEC="${SETTLE_SEC:-6}"
RESULT_DIR="${RESULT_DIR:-}"

if [[ -z "${DISPLAY:-}" ]]; then
  echo "DISPLAY is not set; cannot capture PCL Viewer screenshot." >&2
  exit 1
fi

if ! command -v pcl_viewer >/dev/null 2>&1; then
  echo "pcl_viewer is not available." >&2
  exit 1
fi
if ! command -v import >/dev/null 2>&1; then
  echo "ImageMagick import is not available." >&2
  exit 1
fi
if ! command -v convert >/dev/null 2>&1; then
  echo "ImageMagick convert is not available." >&2
  exit 1
fi
if ! command -v identify >/dev/null 2>&1; then
  echo "ImageMagick identify is not available." >&2
  exit 1
fi

if [[ -z "${RESULT_DIR}" ]]; then
  RESULT_DIR="$(find "${RESULT_ROOT}" -maxdepth 1 -type d -name 'foggy_lidar_ransac_batch_*' | sort | tail -n 1)"
fi
if [[ -z "${RESULT_DIR}" || ! -d "${RESULT_DIR}" ]]; then
  echo "RANSAC batch result directory not found." >&2
  exit 1
fi

FILTERED_PCD="${FILTERED_PCD:-${RESULT_DIR}/frame_${FRAME_INDEX}_filtered.pcd}"
INLIERS_PCD="${INLIERS_PCD:-${RESULT_DIR}/frame_${FRAME_INDEX}_line_inliers.pcd}"
if [[ ! -f "${FILTERED_PCD}" || ! -f "${INLIERS_PCD}" ]]; then
  echo "Expected PCD files not found:" >&2
  echo "  ${FILTERED_PCD}" >&2
  echo "  ${INLIERS_PCD}" >&2
  exit 1
fi

mkdir -p "${SCREENSHOT_DIR}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RAW_SCREENSHOT="${SCREENSHOT_DIR}/pcd_ransac_frame${FRAME_INDEX}_${STAMP}.png"
CROP_SCREENSHOT="${SCREENSHOT_DIR}/pcd_ransac_frame${FRAME_INDEX}_${STAMP}_pcl_viewer_left.png"
PCL_LOG="${SCREENSHOT_DIR}/pcd_ransac_frame${FRAME_INDEX}_${STAMP}_pcl_viewer.log"
viewer_pid=""

cleanup() {
  if [[ -n "${viewer_pid}" ]]; then
    kill -TERM -- "-${viewer_pid}" >/dev/null 2>&1 || true
    sleep 1
    kill -KILL -- "-${viewer_pid}" >/dev/null 2>&1 || true
    wait "${viewer_pid}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

setsid pcl_viewer -ps "${PCL_POINT_SIZE:-4}" "${FILTERED_PCD}" "${INLIERS_PCD}" >"${PCL_LOG}" 2>&1 &
viewer_pid=$!
sleep "${SETTLE_SEC}"

import -window root "${RAW_SCREENSHOT}"
dimensions="$(identify -format '%w %h\n' "${RAW_SCREENSHOT}")"
read -r width height <<< "${dimensions}"
crop_width=$((width / 2))
convert "${RAW_SCREENSHOT}" -crop "${crop_width}x${height}+0+0" "${CROP_SCREENSHOT}"

cleanup
viewer_pid=""

if ps -C pcl_viewer -o pid=,comm=,args= | grep -q .; then
  echo "Residual pcl_viewer process detected after cleanup:" >&2
  ps -C pcl_viewer -o pid,comm,args >&2
  exit 1
fi

echo "PCL RANSAC viewer screenshot captured."
echo "Result dir: ${RESULT_DIR}"
echo "Filtered PCD: ${FILTERED_PCD}"
echo "Inliers PCD: ${INLIERS_PCD}"
echo "PCL viewer log: ${PCL_LOG}"
echo "Raw screenshot: ${RAW_SCREENSHOT}"
echo "Cropped screenshot: ${CROP_SCREENSHOT}"
