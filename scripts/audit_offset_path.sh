#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_INPUT="data/results/catenary_offset_yz_zbin2_step5_20260608_000000/depth_camera_motion_catenary_offset_yz_zbin2_step5_offset_path_20260608_085655.csv"
INPUT_CSV="${INPUT_CSV:-${DEFAULT_INPUT}}"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-${RESULT_ROOT}/offset_path_audit_${STAMP}}"
OUTPUT_PREFIX="${OUTPUT_PREFIX:-depth_camera_motion_offset_path_audit}"

EXPECTED_STEP_M="${EXPECTED_STEP_M:-10.0}"
MAX_STEP_ERROR_M="${MAX_STEP_ERROR_M:-1.0}"
MAX_CURVATURE="${MAX_CURVATURE:-0.02}"
MAX_OFFSET_ERROR_M="${MAX_OFFSET_ERROR_M:-0.05}"
MIN_POINTS_PER_GROUP="${MIN_POINTS_PER_GROUP:-3}"

if [[ ! -f "${INPUT_CSV}" ]]; then
  echo "Input CSV does not exist: ${INPUT_CSV}" >&2
  exit 1
fi

source /opt/ros/humble/setup.bash
source "${ROOT_DIR}/install/setup.bash"
set -u

mkdir -p "${OUTPUT_DIR}"

set +e
ros2 run zcw_cable_perception offset_path_audit \
  --input "${INPUT_CSV}" \
  --output-dir "${OUTPUT_DIR}" \
  --output-prefix "${OUTPUT_PREFIX}" \
  --expected-step-m "${EXPECTED_STEP_M}" \
  --max-step-error-m "${MAX_STEP_ERROR_M}" \
  --max-curvature "${MAX_CURVATURE}" \
  --max-offset-error-m "${MAX_OFFSET_ERROR_M}" \
  --min-points-per-group "${MIN_POINTS_PER_GROUP}"
audit_rc=$?
set -e

SUMMARY_TXT="$(find "${OUTPUT_DIR}" -maxdepth 1 -name "${OUTPUT_PREFIX}_*.txt" | sort | tail -n 1)"
GROUPS_CSV="$(find "${OUTPUT_DIR}" -maxdepth 1 -name "${OUTPUT_PREFIX}_groups_*.csv" | sort | tail -n 1)"

if [[ -z "${SUMMARY_TXT}" || ! -f "${SUMMARY_TXT}" ]]; then
  echo "Offset path audit summary was not created." >&2
  exit 1
fi

echo "Offset path audit completed."
echo "Audit result code: ${audit_rc}"
echo "Input CSV: ${INPUT_CSV}"
echo "Output dir: ${OUTPUT_DIR}"
echo "Summary txt: ${SUMMARY_TXT}"
echo "Groups csv: ${GROUPS_CSV}"

exit "${audit_rc}"
