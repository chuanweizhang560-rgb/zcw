#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_CENTERLINE="data/results/catenary_offset_yz_zbin2_step5_20260608_000000/depth_camera_motion_catenary_offset_yz_zbin2_step5_centerline_20260608_085655.csv"
DEFAULT_OFFSET_PATH="data/results/catenary_offset_yz_zbin2_step5_20260608_000000/depth_camera_motion_catenary_offset_yz_zbin2_step5_offset_path_20260608_085655.csv"
DEFAULT_TARGETS="data/results/lookahead_target_step5_20m_strict_20260608_090000/depth_camera_motion_lookahead_step5_20m_strict_targets_20260608_085945.csv"

CENTERLINE_CSV="${CENTERLINE_CSV:-${DEFAULT_CENTERLINE}}"
OFFSET_PATH_CSV="${OFFSET_PATH_CSV:-${DEFAULT_OFFSET_PATH}}"
TARGETS_CSV="${TARGETS_CSV:-${DEFAULT_TARGETS}}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${RESULT_ROOT}/cable_tracking_envelope_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_tracking_envelope_${STAMP}.txt"
GROUP_CSV="${RESULT_DIR}/cable_tracking_envelope_groups_${STAMP}.csv"

EXPECTED_OFFSET_M="${EXPECTED_OFFSET_M:-5.0}"
MAX_CLEARANCE_ERROR_M="${MAX_CLEARANCE_ERROR_M:-0.05}"
MIN_PATH_LENGTH_M="${MIN_PATH_LENGTH_M:-100.0}"
MIN_GROUPS="${MIN_GROUPS:-5}"
MIN_TARGET_PROGRESS_RATIO="${MIN_TARGET_PROGRESS_RATIO:-0.80}"
MAX_TARGET_DISTANCE_M="${MAX_TARGET_DISTANCE_M:-20.5}"
MIN_TARGET_DISTANCE_M="${MIN_TARGET_DISTANCE_M:-19.5}"
MAX_VERTICAL_SPAN_M="${MAX_VERTICAL_SPAN_M:-3.0}"

for path in "${CENTERLINE_CSV}" "${OFFSET_PATH_CSV}" "${TARGETS_CSV}"; do
  if [[ ! -f "${path}" ]]; then
    echo "Required input does not exist: ${path}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

python3 - "$CENTERLINE_CSV" "$OFFSET_PATH_CSV" "$TARGETS_CSV" "$GROUP_CSV" \
  "$EXPECTED_OFFSET_M" "$MAX_CLEARANCE_ERROR_M" "$MIN_PATH_LENGTH_M" \
  "$MIN_GROUPS" "$MIN_TARGET_PROGRESS_RATIO" \
  "$MIN_TARGET_DISTANCE_M" "$MAX_TARGET_DISTANCE_M" "$MAX_VERTICAL_SPAN_M" >"${SUMMARY_FILE}" <<'PY'
import csv
import math
import sys
from collections import defaultdict

centerline_csv, offset_csv, targets_csv, group_csv = sys.argv[1:5]
expected_offset_m = float(sys.argv[5])
max_clearance_error_m = float(sys.argv[6])
min_path_length_m = float(sys.argv[7])
min_groups = int(sys.argv[8])
min_target_progress_ratio = float(sys.argv[9])
min_target_distance_m = float(sys.argv[10])
max_target_distance_m = float(sys.argv[11])
max_vertical_span_m = float(sys.argv[12])

def load_groups(path):
    groups = defaultdict(list)
    with open(path, "r", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            groups[row["group_id"]].append(row)
    return groups

def xyz(row, prefix=""):
    return (float(row[f"{prefix}x"]), float(row[f"{prefix}y"]), float(row[f"{prefix}z"]))

def dist(a, b):
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(3)))

def path_length(points):
    return sum(dist(a, b) for a, b in zip(points[:-1], points[1:]))

center_groups = load_groups(centerline_csv)
offset_groups = load_groups(offset_csv)
target_groups = load_groups(targets_csv)
group_ids = sorted(set(center_groups) & set(offset_groups) & set(target_groups))

rows = []
accepted_groups = 0
total_center_length = 0.0
total_offset_length = 0.0
total_targets = 0
total_points = 0
global_min_clearance = math.inf
global_max_clearance = 0.0
global_max_clearance_error = 0.0
global_min_target_distance = math.inf
global_max_target_distance = 0.0
global_max_vertical_span = 0.0

for group_id in group_ids:
    center_rows = sorted(center_groups[group_id], key=lambda r: int(r["index"]))
    offset_rows = sorted(offset_groups[group_id], key=lambda r: int(r["index"]))
    target_rows = sorted(target_groups[group_id], key=lambda r: int(r["current_index"]))

    center_points = [xyz(row) for row in center_rows]
    offset_points = [xyz(row) for row in offset_rows]
    center_len = path_length(center_points)
    offset_len = path_length(offset_points)
    total_center_length += center_len
    total_offset_length += offset_len
    total_points += len(offset_points)
    total_targets += len(target_rows)

    clearance_values = []
    source_clearance_values = []
    source_match_ok = True
    for center_row, offset_row in zip(center_rows, offset_rows):
        center = xyz(center_row)
        offset = xyz(offset_row)
        source = (float(offset_row["source_x"]), float(offset_row["source_y"]), float(offset_row["source_z"]))
        clearance_values.append(dist(center, offset))
        source_clearance_values.append(dist(source, offset))
        if dist(center, source) > 1e-4:
            source_match_ok = False

    vertical_values = [p[2] for p in center_points]
    vertical_span = max(vertical_values) - min(vertical_values) if vertical_values else 0.0
    min_clearance = min(clearance_values) if clearance_values else math.inf
    max_clearance = max(clearance_values) if clearance_values else 0.0
    mean_clearance = sum(clearance_values) / len(clearance_values) if clearance_values else math.nan
    max_clearance_error = max(abs(value - expected_offset_m) for value in clearance_values) if clearance_values else math.inf
    max_source_clearance_error = max(abs(value - expected_offset_m) for value in source_clearance_values) if source_clearance_values else math.inf

    target_distances = [float(row["target_distance"]) for row in target_rows]
    target_indices = [int(row["target_index"]) for row in target_rows]
    current_indices = [int(row["current_index"]) for row in target_rows]
    target_monotonic = all(b > a for a, b in zip(target_indices[:-1], target_indices[1:]))
    current_monotonic = all(b > a for a, b in zip(current_indices[:-1], current_indices[1:]))
    min_target_distance = min(target_distances) if target_distances else math.inf
    max_target_distance = max(target_distances) if target_distances else 0.0
    mean_target_distance = sum(target_distances) / len(target_distances) if target_distances else math.nan
    progress_ratio = len(target_rows) / len(offset_rows) if offset_rows else 0.0

    global_min_clearance = min(global_min_clearance, min_clearance)
    global_max_clearance = max(global_max_clearance, max_clearance)
    global_max_clearance_error = max(global_max_clearance_error, max_clearance_error, max_source_clearance_error)
    global_min_target_distance = min(global_min_target_distance, min_target_distance)
    global_max_target_distance = max(global_max_target_distance, max_target_distance)
    global_max_vertical_span = max(global_max_vertical_span, vertical_span)

    accepted = (
        len(center_rows) == len(offset_rows)
        and len(offset_rows) > 0
        and source_match_ok
        and center_len >= min_path_length_m
        and offset_len >= min_path_length_m
        and max_clearance_error <= max_clearance_error_m
        and max_source_clearance_error <= max_clearance_error_m
        and progress_ratio >= min_target_progress_ratio
        and target_monotonic
        and current_monotonic
        and min_target_distance >= min_target_distance_m
        and max_target_distance <= max_target_distance_m
        and vertical_span <= max_vertical_span_m
    )
    if accepted:
        accepted_groups += 1
    rows.append({
        "group_id": group_id,
        "center_points": len(center_rows),
        "offset_points": len(offset_rows),
        "target_points": len(target_rows),
        "center_length_m": center_len,
        "offset_length_m": offset_len,
        "min_clearance_m": min_clearance,
        "max_clearance_m": max_clearance,
        "mean_clearance_m": mean_clearance,
        "max_clearance_error_m": max_clearance_error,
        "vertical_span_m": vertical_span,
        "target_progress_ratio": progress_ratio,
        "min_target_distance_m": min_target_distance,
        "max_target_distance_m": max_target_distance,
        "mean_target_distance_m": mean_target_distance,
        "source_match_ok": source_match_ok,
        "target_monotonic": target_monotonic,
        "current_monotonic": current_monotonic,
        "accepted": accepted,
    })

with open(group_csv, "w", newline="", encoding="utf-8") as f:
    fieldnames = list(rows[0].keys()) if rows else ["group_id"]
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    for row in rows:
        writer.writerow({
            key: (f"{value:.9f}" if isinstance(value, float) else ("true" if value is True else "false" if value is False else value))
            for key, value in row.items()
        })

coverage_ready = len(rows) >= min_groups and accepted_groups == len(rows)
decision = "accepted_cable_tracking_envelope_audit" if coverage_ready else "rejected_cable_tracking_envelope_audit"
reason = "offset_tracking_envelope_and_lookahead_progress_are_consistent" if coverage_ready else "offset_tracking_envelope_or_lookahead_progress_exceeds_bounds"

def metric(value):
    return "nan" if not math.isfinite(value) else f"{value:.9f}"

print("scope=cable_tracking_envelope_audit")
print(f"decision={decision}")
print(f"reason={reason}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print(f"centerline_csv={centerline_csv}")
print(f"offset_path_csv={offset_csv}")
print(f"targets_csv={targets_csv}")
print(f"group_csv={group_csv}")
print(f"group_count={len(rows)}")
print(f"accepted_group_count={accepted_groups}")
print(f"total_center_length_m={metric(total_center_length)}")
print(f"total_offset_length_m={metric(total_offset_length)}")
print(f"total_offset_points={total_points}")
print(f"total_lookahead_targets={total_targets}")
print(f"expected_offset_m={expected_offset_m:.9f}")
print(f"global_min_clearance_m={metric(global_min_clearance)}")
print(f"global_max_clearance_m={metric(global_max_clearance)}")
print(f"global_max_clearance_error_m={metric(global_max_clearance_error)}")
print(f"global_min_target_distance_m={metric(global_min_target_distance)}")
print(f"global_max_target_distance_m={metric(global_max_target_distance)}")
print(f"global_max_vertical_span_m={metric(global_max_vertical_span)}")
print(f"min_groups={min_groups}")
print(f"min_path_length_m={min_path_length_m:.9f}")
print(f"min_target_progress_ratio={min_target_progress_ratio:.9f}")
print(f"min_target_distance_m={min_target_distance_m:.9f}")
print(f"max_target_distance_m={max_target_distance_m:.9f}")
print(f"max_vertical_span_m={max_vertical_span_m:.9f}")
print("claims_tracking_envelope_pass=" + ("true" if coverage_ready else "false"))

if not coverage_ready:
    raise SystemExit(2)
PY

echo "Cable tracking envelope audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Group CSV: ${GROUP_CSV}"
