#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_INPUT="data/results/depth_camera_motion_ransac_20260603_111923/depth_camera_motion_multiline_ransac_world_lines_20260603_112105.csv"
INPUT_CSV="${INPUT_CSV:-${DEFAULT_INPUT}}"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-${RESULT_ROOT}/multiline_consistency_${STAMP}}"
OUTPUT_PREFIX="${OUTPUT_PREFIX:-depth_camera_motion_multiline_consistency}"

MIN_ABS_DIR_X="${MIN_ABS_DIR_X:-0.85}"
MAX_ABS_DIR_Y="${MAX_ABS_DIR_Y:-0.05}"
MAX_ABS_DIR_Z="${MAX_ABS_DIR_Z:-0.18}"
MIN_X_SPAN="${MIN_X_SPAN:-40.0}"
MAX_Y_SPAN="${MAX_Y_SPAN:-5.0}"
MAX_Z_SPAN="${MAX_Z_SPAN:-18.0}"
Y_BIN_SIZE="${Y_BIN_SIZE:-2.0}"
MIN_CANDIDATES_PER_GROUP="${MIN_CANDIDATES_PER_GROUP:-2}"
MIN_FRAMES_PER_GROUP="${MIN_FRAMES_PER_GROUP:-2}"
MIN_ACCEPTED_GROUPS="${MIN_ACCEPTED_GROUPS:-1}"

if [[ ! -f "${INPUT_CSV}" ]]; then
  echo "Input CSV does not exist: ${INPUT_CSV}" >&2
  exit 1
fi

source /opt/ros/humble/setup.bash
source "${ROOT_DIR}/install/setup.bash"
set -u

mkdir -p "${OUTPUT_DIR}"

set +e
ros2 run zcw_cable_perception multiline_candidate_consistency_audit \
  --input "${INPUT_CSV}" \
  --output-dir "${OUTPUT_DIR}" \
  --output-prefix "${OUTPUT_PREFIX}" \
  --min-abs-dir-x "${MIN_ABS_DIR_X}" \
  --max-abs-dir-y "${MAX_ABS_DIR_Y}" \
  --max-abs-dir-z "${MAX_ABS_DIR_Z}" \
  --min-x-span "${MIN_X_SPAN}" \
  --max-y-span "${MAX_Y_SPAN}" \
  --max-z-span "${MAX_Z_SPAN}" \
  --y-bin-size "${Y_BIN_SIZE}" \
  --min-candidates-per-group "${MIN_CANDIDATES_PER_GROUP}" \
  --min-frames-per-group "${MIN_FRAMES_PER_GROUP}" \
  --min-accepted-groups "${MIN_ACCEPTED_GROUPS}"
audit_rc=$?
set -e

SUMMARY_TXT="$(find "${OUTPUT_DIR}" -maxdepth 1 -name "${OUTPUT_PREFIX}_*.txt" | sort | tail -n 1)"
GROUPS_CSV="$(find "${OUTPUT_DIR}" -maxdepth 1 -name "${OUTPUT_PREFIX}_groups_*.csv" | sort | tail -n 1)"
ACCEPTED_CSV="$(find "${OUTPUT_DIR}" -maxdepth 1 -name "${OUTPUT_PREFIX}_accepted_*.csv" | sort | tail -n 1)"

if [[ -z "${SUMMARY_TXT}" || ! -f "${SUMMARY_TXT}" ]]; then
  echo "Consistency audit summary was not created." >&2
  exit 1
fi

echo "Depth camera multiline consistency audit completed."
echo "Audit result code: ${audit_rc}"
echo "Input CSV: ${INPUT_CSV}"
echo "Output dir: ${OUTPUT_DIR}"
echo "Summary txt: ${SUMMARY_TXT}"
echo "Groups csv: ${GROUPS_CSV}"
echo "Accepted csv: ${ACCEPTED_CSV}"

exit "${audit_rc}"
