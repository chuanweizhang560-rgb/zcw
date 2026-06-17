#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_OFFSET_PATH_CSV="data/results/catenary_offset_yz_zbin2_step5_20260608_000000/depth_camera_motion_catenary_offset_yz_zbin2_step5_offset_path_20260608_085655.csv"
DEFAULT_LOOKAHEAD_TARGET_CSV="data/results/lookahead_target_step5_20m_strict_20260608_090000/depth_camera_motion_lookahead_step5_20m_strict_targets_20260608_085945.csv"
OFFSET_PATH_CSV="${OFFSET_PATH_CSV:-${DEFAULT_OFFSET_PATH_CSV}}"
LOOKAHEAD_TARGET_CSV="${LOOKAHEAD_TARGET_CSV:-${DEFAULT_LOOKAHEAD_TARGET_CSV}}"
MIN_GROUPS="${MIN_GROUPS:-5}"
MIN_PATH_POINTS_PER_GROUP="${MIN_PATH_POINTS_PER_GROUP:-25}"
MIN_TARGETS_PER_GROUP="${MIN_TARGETS_PER_GROUP:-21}"
MIN_ARC_COVERAGE_RATIO="${MIN_ARC_COVERAGE_RATIO:-0.99}"
MAX_TARGET_POINT_ERROR_M="${MAX_TARGET_POINT_ERROR_M:-0.001}"
MAX_CURRENT_POINT_ERROR_M="${MAX_CURRENT_POINT_ERROR_M:-0.001}"
MIN_FORWARD_DOT="${MIN_FORWARD_DOT:-0.99}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_line_segment_coverage_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_line_segment_coverage_${STAMP}.txt"
GROUP_CSV="${RESULT_DIR}/cable_line_segment_coverage_groups_${STAMP}.csv"

for file in "${OFFSET_PATH_CSV}" "${LOOKAHEAD_TARGET_CSV}"; do
  if [[ ! -f "${file}" ]]; then
    echo "Required input file does not exist: ${file}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

python3 - "${OFFSET_PATH_CSV}" "${LOOKAHEAD_TARGET_CSV}" "${GROUP_CSV}" \
  "${MIN_GROUPS}" "${MIN_PATH_POINTS_PER_GROUP}" "${MIN_TARGETS_PER_GROUP}" \
  "${MIN_ARC_COVERAGE_RATIO}" "${MAX_TARGET_POINT_ERROR_M}" "${MAX_CURRENT_POINT_ERROR_M}" \
  "${MIN_FORWARD_DOT}" >"${SUMMARY_FILE}" <<'PY'
import csv
import math
import sys
from collections import defaultdict

(
    offset_path_csv,
    lookahead_target_csv,
    group_csv,
    min_groups,
    min_path_points_per_group,
    min_targets_per_group,
    min_arc_coverage_ratio,
    max_target_point_error_m,
    max_current_point_error_m,
    min_forward_dot,
) = sys.argv[1:11]

min_groups = int(min_groups)
min_path_points_per_group = int(min_path_points_per_group)
min_targets_per_group = int(min_targets_per_group)
min_arc_coverage_ratio = float(min_arc_coverage_ratio)
max_target_point_error_m = float(max_target_point_error_m)
max_current_point_error_m = float(max_current_point_error_m)
min_forward_dot = float(min_forward_dot)


def vec(row, prefix=""):
    return (
        float(row[f"{prefix}x"]),
        float(row[f"{prefix}y"]),
        float(row[f"{prefix}z"]),
    )


def dist(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def norm(a):
    return math.sqrt(dot(a, a))


def unit(a):
    n = norm(a)
    if n <= 1e-12:
        return (0.0, 0.0, 0.0)
    return tuple(x / n for x in a)


path_groups = defaultdict(list)
with open(offset_path_csv, newline="") as f:
    for row in csv.DictReader(f):
        path_groups[row["group_id"]].append(row)

target_groups = defaultdict(list)
with open(lookahead_target_csv, newline="") as f:
    for row in csv.DictReader(f):
        target_groups[row["group_id"]].append(row)

for rows in path_groups.values():
    rows.sort(key=lambda row: int(row["index"]))
for rows in target_groups.values():
    rows.sort(key=lambda row: int(row["current_index"]))

all_group_ids = sorted(set(path_groups) | set(target_groups))
group_summaries = []
fail_reasons = []

for group_id in all_group_ids:
    path_rows = path_groups.get(group_id, [])
    target_rows = target_groups.get(group_id, [])
    path_by_index = {int(row["index"]): row for row in path_rows}

    cumulative = [0.0]
    for prev, cur in zip(path_rows, path_rows[1:]):
        cumulative.append(cumulative[-1] + dist(vec(prev), vec(cur)))
    path_length = cumulative[-1] if cumulative else 0.0

    intervals = []
    max_current_error = 0.0
    max_target_error = 0.0
    min_segment_forward_dot = 1.0
    invalid_index_count = 0

    for row in target_rows:
        current_index = int(row["current_index"])
        target_index = int(row["target_index"])
        current_path = path_by_index.get(current_index)
        target_path = path_by_index.get(target_index)
        if current_path is None or target_path is None:
            invalid_index_count += 1
            continue

        current_point = (float(row["current_x"]), float(row["current_y"]), float(row["current_z"]))
        target_point = (float(row["target_x"]), float(row["target_y"]), float(row["target_z"]))
        max_current_error = max(max_current_error, dist(current_point, vec(current_path)))
        max_target_error = max(max_target_error, dist(target_point, vec(target_path)))

        start_arc = cumulative[current_index]
        end_arc = cumulative[target_index]
        if end_arc < start_arc:
            start_arc, end_arc = end_arc, start_arc
        intervals.append((start_arc, end_arc))

        segment_vec = (
            target_point[0] - current_point[0],
            target_point[1] - current_point[1],
            target_point[2] - current_point[2],
        )
        tangent_vec = (float(row["tangent_x"]), float(row["tangent_y"]), float(row["tangent_z"]))
        min_segment_forward_dot = min(min_segment_forward_dot, dot(unit(segment_vec), unit(tangent_vec)))

    intervals.sort()
    merged = []
    for start, end in intervals:
        if not merged or start > merged[-1][1] + 1e-9:
            merged.append([start, end])
        else:
            merged[-1][1] = max(merged[-1][1], end)
    covered_arc_length = sum(end - start for start, end in merged)
    arc_coverage_ratio = covered_arc_length / path_length if path_length > 1e-12 else 0.0

    accepted = (
        len(path_rows) >= min_path_points_per_group
        and len(target_rows) >= min_targets_per_group
        and invalid_index_count == 0
        and arc_coverage_ratio >= min_arc_coverage_ratio
        and max_current_error <= max_current_point_error_m
        and max_target_error <= max_target_point_error_m
        and min_segment_forward_dot >= min_forward_dot
    )
    if not accepted:
        fail_reasons.append(group_id)

    group_summaries.append(
        {
            "group_id": group_id,
            "decision": "accepted_cable_line_segment_group" if accepted else "rejected_cable_line_segment_group",
            "path_points": len(path_rows),
            "target_count": len(target_rows),
            "path_length_m": path_length,
            "covered_arc_length_m": covered_arc_length,
            "arc_coverage_ratio": arc_coverage_ratio,
            "interval_count": len(intervals),
            "merged_interval_count": len(merged),
            "max_current_point_error_m": max_current_error,
            "max_target_point_error_m": max_target_error,
            "min_segment_forward_dot": min_segment_forward_dot,
            "invalid_index_count": invalid_index_count,
        }
    )

fieldnames = [
    "group_id",
    "decision",
    "path_points",
    "target_count",
    "path_length_m",
    "covered_arc_length_m",
    "arc_coverage_ratio",
    "interval_count",
    "merged_interval_count",
    "max_current_point_error_m",
    "max_target_point_error_m",
    "min_segment_forward_dot",
    "invalid_index_count",
]
with open(group_csv, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    for row in group_summaries:
        writer.writerow(row)

accepted_group_count = sum(1 for row in group_summaries if row["decision"] == "accepted_cable_line_segment_group")
global_min_arc_coverage_ratio = min((row["arc_coverage_ratio"] for row in group_summaries), default=0.0)
global_max_current_error = max((row["max_current_point_error_m"] for row in group_summaries), default=math.inf)
global_max_target_error = max((row["max_target_point_error_m"] for row in group_summaries), default=math.inf)
global_min_forward_dot = min((row["min_segment_forward_dot"] for row in group_summaries), default=0.0)
total_path_length = sum(row["path_length_m"] for row in group_summaries)
total_covered_arc_length = sum(row["covered_arc_length_m"] for row in group_summaries)

accepted = (
    len(group_summaries) >= min_groups
    and accepted_group_count >= min_groups
    and not fail_reasons
)
decision = "accepted_cable_line_segment_coverage" if accepted else "rejected_cable_line_segment_coverage"
reason = "all_groups_have_dense_lookahead_segment_arc_coverage" if accepted else "one_or_more_groups_failed_line_segment_coverage"

print("scope=cable_line_segment_coverage")
print(f"decision={decision}")
print(f"reason={reason}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print(f"offset_path_csv={offset_path_csv}")
print(f"lookahead_target_csv={lookahead_target_csv}")
print(f"group_csv={group_csv}")
print(f"min_groups={min_groups}")
print(f"min_path_points_per_group={min_path_points_per_group}")
print(f"min_targets_per_group={min_targets_per_group}")
print(f"min_arc_coverage_ratio={min_arc_coverage_ratio:.9f}")
print(f"max_target_point_error_m={max_target_point_error_m:.9f}")
print(f"max_current_point_error_m={max_current_point_error_m:.9f}")
print(f"min_forward_dot={min_forward_dot:.9f}")
print(f"group_count={len(group_summaries)}")
print(f"accepted_group_count={accepted_group_count}")
print(f"total_path_length_m={total_path_length:.9f}")
print(f"total_covered_arc_length_m={total_covered_arc_length:.9f}")
print(f"global_min_arc_coverage_ratio={global_min_arc_coverage_ratio:.9f}")
print(f"global_max_current_point_error_m={global_max_current_error:.9f}")
print(f"global_max_target_point_error_m={global_max_target_error:.9f}")
print(f"global_min_segment_forward_dot={global_min_forward_dot:.9f}")
print(f"failed_groups={','.join(fail_reasons)}")
print("claims_final_inspection_coverage=false")
print(f"claims_cable_line_segment_coverage_pass={str(accepted).lower()}")
PY

echo "Cable line-segment coverage audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Group CSV: ${GROUP_CSV}"

grep -q "decision=accepted_cable_line_segment_coverage" "${SUMMARY_FILE}"
