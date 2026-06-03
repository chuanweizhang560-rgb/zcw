#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_INPUT="data/results/catenary_offset_yz_zbin2_20260603_135000/depth_camera_motion_catenary_offset_yz_zbin2_offset_path_20260603_125948.csv"
INPUT_CSV="${INPUT_CSV:-${DEFAULT_INPUT}}"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-${RESULT_ROOT}/lookahead_target_audit_${STAMP}}"
OUTPUT_PREFIX="${OUTPUT_PREFIX:-depth_camera_motion_lookahead_target_audit}"

LOOKAHEAD_M="${LOOKAHEAD_M:-20.0}"
MIN_TARGET_DISTANCE_M="${MIN_TARGET_DISTANCE_M:-15.0}"
MAX_TARGET_DISTANCE_M="${MAX_TARGET_DISTANCE_M:-25.0}"
MIN_TARGETS_PER_GROUP="${MIN_TARGETS_PER_GROUP:-2}"

if [[ ! -f "${INPUT_CSV}" ]]; then
  echo "Input CSV does not exist: ${INPUT_CSV}" >&2
  exit 1
fi

source /opt/ros/humble/setup.bash
source "${ROOT_DIR}/install/setup.bash"
set -u

mkdir -p "${OUTPUT_DIR}"

set +e
ros2 run zcw_cable_perception lookahead_target_audit \
  --input "${INPUT_CSV}" \
  --output-dir "${OUTPUT_DIR}" \
  --output-prefix "${OUTPUT_PREFIX}" \
  --lookahead-m "${LOOKAHEAD_M}" \
  --min-target-distance-m "${MIN_TARGET_DISTANCE_M}" \
  --max-target-distance-m "${MAX_TARGET_DISTANCE_M}" \
  --min-targets-per-group "${MIN_TARGETS_PER_GROUP}"
audit_rc=$?
set -e

SUMMARY_TXT="$(find "${OUTPUT_DIR}" -maxdepth 1 -name "${OUTPUT_PREFIX}_*.txt" | sort | tail -n 1)"
TARGETS_CSV="$(find "${OUTPUT_DIR}" -maxdepth 1 -name "${OUTPUT_PREFIX}_targets_*.csv" | sort | tail -n 1)"
GROUPS_CSV="$(find "${OUTPUT_DIR}" -maxdepth 1 -name "${OUTPUT_PREFIX}_groups_*.csv" | sort | tail -n 1)"

if [[ -z "${SUMMARY_TXT}" || ! -f "${SUMMARY_TXT}" ]]; then
  echo "Lookahead target audit summary was not created." >&2
  exit 1
fi

echo "Lookahead target audit completed."
echo "Audit result code: ${audit_rc}"
echo "Input CSV: ${INPUT_CSV}"
echo "Output dir: ${OUTPUT_DIR}"
echo "Summary txt: ${SUMMARY_TXT}"
echo "Targets csv: ${TARGETS_CSV}"
echo "Groups csv: ${GROUPS_CSV}"

exit "${audit_rc}"
