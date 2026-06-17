#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_TRACKING_SUMMARY="data/results/cable_tracking_envelope_20260615_093659/cable_tracking_envelope_20260615_093659.txt"
DEFAULT_FRAME_SUMMARY="data/results/cable_frame_contract_20260615_100822/cable_frame_contract_20260615_100822.txt"
DEFAULT_COVERAGE_SUMMARY="data/results/lookahead_coverage_monitor_all_groups_20260615_100351/lookahead_coverage_monitor_all_groups_20260615_100351.txt"
DEFAULT_COVERAGE_CSV="data/results/lookahead_coverage_monitor_all_groups_20260615_100351/lookahead_coverage_monitor_all_groups_20260615_100351.csv"
DEFAULT_LINE_SEGMENT_SUMMARY="data/results/cable_line_segment_coverage_20260617_085604/cable_line_segment_coverage_20260617_085604.txt"
TRACKING_SUMMARY="${TRACKING_SUMMARY:-${DEFAULT_TRACKING_SUMMARY}}"
FRAME_SUMMARY="${FRAME_SUMMARY:-${DEFAULT_FRAME_SUMMARY}}"
COVERAGE_SUMMARY="${COVERAGE_SUMMARY:-${DEFAULT_COVERAGE_SUMMARY}}"
COVERAGE_CSV="${COVERAGE_CSV:-${DEFAULT_COVERAGE_CSV}}"
LINE_SEGMENT_SUMMARY="${LINE_SEGMENT_SUMMARY:-${DEFAULT_LINE_SEGMENT_SUMMARY}}"
MIN_GROUPS="${MIN_GROUPS:-5}"
MIN_COVERAGE_RATIO="${MIN_COVERAGE_RATIO:-0.80}"
MAX_CLEARANCE_ERROR_M="${MAX_CLEARANCE_ERROR_M:-0.001}"
MAX_FRAME_ERROR_M="${MAX_FRAME_ERROR_M:-0.001}"
MAX_LOOKAHEAD_ERROR_M="${MAX_LOOKAHEAD_ERROR_M:-0.01}"
MIN_FORWARD_DOT="${MIN_FORWARD_DOT:-0.99}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_dry_run_acceptance_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_dry_run_acceptance_${STAMP}.txt"

for file in "${TRACKING_SUMMARY}" "${FRAME_SUMMARY}" "${COVERAGE_SUMMARY}" "${COVERAGE_CSV}" "${LINE_SEGMENT_SUMMARY}"; do
  if [[ ! -f "${file}" ]]; then
    echo "Required evidence file does not exist: ${file}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

python3 - "${TRACKING_SUMMARY}" "${FRAME_SUMMARY}" "${COVERAGE_SUMMARY}" "${COVERAGE_CSV}" "${LINE_SEGMENT_SUMMARY}" \
  "${MIN_GROUPS}" "${MIN_COVERAGE_RATIO}" "${MAX_CLEARANCE_ERROR_M}" "${MAX_FRAME_ERROR_M}" \
  "${MAX_LOOKAHEAD_ERROR_M}" "${MIN_FORWARD_DOT}" >"${SUMMARY_FILE}" <<'PY'
import csv
import math
import sys

(
    tracking_summary,
    frame_summary,
    coverage_summary,
    coverage_csv,
    line_segment_summary,
    min_groups,
    min_coverage_ratio,
    max_clearance_error,
    max_frame_error,
    max_lookahead_error,
    min_forward_dot,
) = sys.argv[1:12]

min_groups = int(min_groups)
min_coverage_ratio = float(min_coverage_ratio)
max_clearance_error = float(max_clearance_error)
max_frame_error = float(max_frame_error)
max_lookahead_error = float(max_lookahead_error)
min_forward_dot = float(min_forward_dot)


def load_kv(path):
    out = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or "=" not in line:
                continue
            key, value = line.split("=", 1)
            out[key] = value
    return out


def f(kv, key, default=math.nan):
    try:
        return float(kv.get(key, default))
    except ValueError:
        return default


def i(kv, key, default=0):
    try:
        return int(float(kv.get(key, default)))
    except ValueError:
        return default


tracking = load_kv(tracking_summary)
frame = load_kv(frame_summary)
coverage = load_kv(coverage_summary)
line_segment = load_kv(line_segment_summary)

coverage_rows = []
with open(coverage_csv, newline="") as fcsv:
    for row in csv.DictReader(fcsv):
        coverage_rows.append(row)

coverage_ratios = [float(row["coverage_ratio"]) for row in coverage_rows]
coverage_all_ok = all(
    row["decision"] == "accepted_lookahead_coverage_monitor"
    and row["coverage_ok"] == "true"
    and float(row["coverage_ratio"]) >= min_coverage_ratio
    for row in coverage_rows
)

tracking_ok = (
    tracking.get("decision") == "accepted_cable_tracking_envelope_audit"
    and i(tracking, "group_count") >= min_groups
    and i(tracking, "accepted_group_count") >= min_groups
    and f(tracking, "global_max_clearance_error_m") <= max_clearance_error
)
frame_ok = (
    frame.get("decision") == "accepted_cable_frame_contract_audit"
    and i(frame, "group_count") >= min_groups
    and i(frame, "accepted_group_count") >= min_groups
    and f(frame, "global_max_source_error_m") <= max_frame_error
    and f(frame, "global_max_offset_y_error_m") <= max_frame_error
    and f(frame, "global_max_offset_z_error_m") <= max_frame_error
    and f(frame, "global_max_target_current_error_m") <= max_frame_error
    and f(frame, "global_max_target_point_error_m") <= max_frame_error
    and f(frame, "global_max_lookahead_error_m") <= max_lookahead_error
    and f(frame, "global_min_forward_dot") >= min_forward_dot
)
coverage_ok = (
    coverage.get("decision") == "accepted_lookahead_coverage_monitor_all_groups"
    and i(coverage, "group_count") >= min_groups
    and i(coverage, "accepted_group_count") >= min_groups
    and len(coverage_rows) >= min_groups
    and coverage_all_ok
)
line_segment_ok = (
    line_segment.get("decision") == "accepted_cable_line_segment_coverage"
    and i(line_segment, "group_count") >= min_groups
    and i(line_segment, "accepted_group_count") >= min_groups
    and f(line_segment, "global_min_arc_coverage_ratio") >= 0.99
    and f(line_segment, "global_max_current_point_error_m") <= max_frame_error
    and f(line_segment, "global_max_target_point_error_m") <= max_frame_error
    and f(line_segment, "global_min_segment_forward_dot") >= min_forward_dot
    and line_segment.get("claims_final_inspection_coverage") == "false"
)
boundary_ok = all(
    kv.get("starts_px4") == "false"
    and kv.get("starts_gazebo") == "false"
    and kv.get("starts_rviz") == "false"
    and kv.get("starts_offboard") == "false"
    and kv.get("arms") == "false"
    and kv.get("publishes_fmu_in") == "false"
    for kv in (tracking, frame, coverage, line_segment)
)

accepted = tracking_ok and frame_ok and coverage_ok and line_segment_ok and boundary_ok
decision = "accepted_cable_dry_run_acceptance" if accepted else "rejected_cable_dry_run_acceptance"
reason = "tracking_frame_and_coverage_evidence_meets_dry_run_thresholds" if accepted else "one_or_more_dry_run_acceptance_gates_failed"

print("scope=cable_dry_run_acceptance")
print(f"decision={decision}")
print(f"reason={reason}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print(f"tracking_summary={tracking_summary}")
print(f"frame_summary={frame_summary}")
print(f"coverage_summary={coverage_summary}")
print(f"coverage_csv={coverage_csv}")
print(f"line_segment_summary={line_segment_summary}")
print(f"min_groups={min_groups}")
print(f"min_coverage_ratio={min_coverage_ratio:.9f}")
print(f"max_clearance_error_m={max_clearance_error:.9f}")
print(f"max_frame_error_m={max_frame_error:.9f}")
print(f"max_lookahead_error_m={max_lookahead_error:.9f}")
print(f"min_forward_dot={min_forward_dot:.9f}")
print(f"tracking_ok={str(tracking_ok).lower()}")
print(f"frame_ok={str(frame_ok).lower()}")
print(f"coverage_ok={str(coverage_ok).lower()}")
print(f"line_segment_ok={str(line_segment_ok).lower()}")
print(f"boundary_ok={str(boundary_ok).lower()}")
print(f"coverage_group_count={len(coverage_rows)}")
print(f"coverage_min_ratio={min(coverage_ratios):.9f}")
print(f"coverage_max_ratio={max(coverage_ratios):.9f}")
print(f"tracking_global_max_clearance_error_m={f(tracking, 'global_max_clearance_error_m'):.9f}")
print(f"frame_global_max_target_point_error_m={f(frame, 'global_max_target_point_error_m'):.9f}")
print(f"frame_global_max_lookahead_error_m={f(frame, 'global_max_lookahead_error_m'):.9f}")
print(f"frame_global_min_forward_dot={f(frame, 'global_min_forward_dot'):.9f}")
print(f"line_segment_global_min_arc_coverage_ratio={f(line_segment, 'global_min_arc_coverage_ratio'):.9f}")
print(f"line_segment_total_path_length_m={f(line_segment, 'total_path_length_m'):.9f}")
print(f"claims_cable_dry_run_acceptance_pass={str(accepted).lower()}")
PY

echo "Cable dry-run acceptance audit completed."
echo "Summary: ${SUMMARY_FILE}"

grep -q "decision=accepted_cable_dry_run_acceptance" "${SUMMARY_FILE}"
