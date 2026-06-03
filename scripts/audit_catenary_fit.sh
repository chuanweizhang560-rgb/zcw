#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_INPUT="data/results/depth_camera_motion_ransac_20260603_114139/depth_camera_motion_multiline_ransac_world_lines_20260603_114312.csv"
INPUT_CSV="${INPUT_CSV:-${DEFAULT_INPUT}}"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-${RESULT_ROOT}/catenary_fit_${STAMP}}"
OUTPUT_PREFIX="${OUTPUT_PREFIX:-depth_camera_motion_catenary_fit}"

GROUP_MODE="${GROUP_MODE:-yz}"
Y_BIN_SIZE="${Y_BIN_SIZE:-2.0}"
Z_BIN_SIZE="${Z_BIN_SIZE:-3.0}"
MAX_CATENARY_RMSE="${MAX_CATENARY_RMSE:-1.0}"
MAX_QUADRATIC_RMSE="${MAX_QUADRATIC_RMSE:-1.0}"
PATH_STEP_M="${PATH_STEP_M:-10.0}"
OFFSET_Y_M="${OFFSET_Y_M:--5.0}"
OFFSET_Z_M="${OFFSET_Z_M:-0.0}"

if [[ ! -f "${INPUT_CSV}" ]]; then
  echo "Input CSV does not exist: ${INPUT_CSV}" >&2
  exit 1
fi

source /opt/ros/humble/setup.bash
source "${ROOT_DIR}/install/setup.bash"
set -u

mkdir -p "${OUTPUT_DIR}"

set +e
ros2 run zcw_cable_perception catenary_fit_audit \
  --input "${INPUT_CSV}" \
  --output-dir "${OUTPUT_DIR}" \
  --output-prefix "${OUTPUT_PREFIX}" \
  --group-mode "${GROUP_MODE}" \
  --y-bin-size "${Y_BIN_SIZE}" \
  --z-bin-size "${Z_BIN_SIZE}" \
  --max-catenary-rmse "${MAX_CATENARY_RMSE}" \
  --max-quadratic-rmse "${MAX_QUADRATIC_RMSE}" \
  --path-step-m "${PATH_STEP_M}" \
  --offset-y-m "${OFFSET_Y_M}" \
  --offset-z-m "${OFFSET_Z_M}"
fit_rc=$?
set -e

SUMMARY_TXT="$(find "${OUTPUT_DIR}" -maxdepth 1 -name "${OUTPUT_PREFIX}_*.txt" | sort | tail -n 1)"
FITS_CSV="$(find "${OUTPUT_DIR}" -maxdepth 1 -name "${OUTPUT_PREFIX}_fits_*.csv" | sort | tail -n 1)"
SAMPLES_CSV="$(find "${OUTPUT_DIR}" -maxdepth 1 -name "${OUTPUT_PREFIX}_samples_*.csv" | sort | tail -n 1)"
CENTERLINE_CSV="$(find "${OUTPUT_DIR}" -maxdepth 1 -name "${OUTPUT_PREFIX}_centerline_*.csv" | sort | tail -n 1)"
OFFSET_PATH_CSV="$(find "${OUTPUT_DIR}" -maxdepth 1 -name "${OUTPUT_PREFIX}_offset_path_*.csv" | sort | tail -n 1)"

if [[ -z "${SUMMARY_TXT}" || ! -f "${SUMMARY_TXT}" ]]; then
  echo "Catenary fit summary was not created." >&2
  exit 1
fi

echo "Catenary fit audit completed."
echo "Fit result code: ${fit_rc}"
echo "Input CSV: ${INPUT_CSV}"
echo "Output dir: ${OUTPUT_DIR}"
echo "Summary txt: ${SUMMARY_TXT}"
echo "Fits csv: ${FITS_CSV}"
echo "Samples csv: ${SAMPLES_CSV}"
echo "Centerline csv: ${CENTERLINE_CSV}"
echo "Offset path csv: ${OFFSET_PATH_CSV}"

exit "${fit_rc}"
