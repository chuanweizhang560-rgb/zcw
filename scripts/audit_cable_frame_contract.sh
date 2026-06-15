#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_CENTERLINE="data/results/catenary_offset_yz_zbin2_step5_20260608_000000/depth_camera_motion_catenary_offset_yz_zbin2_step5_centerline_20260608_085655.csv"
DEFAULT_OFFSET_PATH="data/results/catenary_offset_yz_zbin2_step5_20260608_000000/depth_camera_motion_catenary_offset_yz_zbin2_step5_offset_path_20260608_085655.csv"
DEFAULT_TARGETS="data/results/lookahead_target_step5_20m_strict_20260608_090000/depth_camera_motion_lookahead_step5_20m_strict_targets_20260608_085945.csv"
CENTERLINE_CSV="${CENTERLINE_CSV:-${DEFAULT_CENTERLINE}}"
OFFSET_PATH_CSV="${OFFSET_PATH_CSV:-${DEFAULT_OFFSET_PATH}}"
TARGETS_CSV="${TARGETS_CSV:-${DEFAULT_TARGETS}}"
EXPECTED_OFFSET_Y_M="${EXPECTED_OFFSET_Y_M:--5.0}"
EXPECTED_OFFSET_Z_M="${EXPECTED_OFFSET_Z_M:-0.0}"
EXPECTED_LOOKAHEAD_M="${EXPECTED_LOOKAHEAD_M:-20.0}"
MAX_SOURCE_ERROR_M="${MAX_SOURCE_ERROR_M:-0.001}"
MAX_OFFSET_ERROR_M="${MAX_OFFSET_ERROR_M:-0.001}"
MAX_TARGET_POINT_ERROR_M="${MAX_TARGET_POINT_ERROR_M:-0.001}"
MAX_LOOKAHEAD_ERROR_M="${MAX_LOOKAHEAD_ERROR_M:-0.01}"
MIN_FORWARD_DOT="${MIN_FORWARD_DOT:-0.0}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_frame_contract_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_frame_contract_${STAMP}.txt"
GROUP_CSV="${RESULT_DIR}/cable_frame_contract_groups_${STAMP}.csv"

for file in "${CENTERLINE_CSV}" "${OFFSET_PATH_CSV}" "${TARGETS_CSV}"; do
  if [[ ! -f "${file}" ]]; then
    echo "Required CSV does not exist: ${file}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

python3 - "${CENTERLINE_CSV}" "${OFFSET_PATH_CSV}" "${TARGETS_CSV}" "${GROUP_CSV}" \
  "${EXPECTED_OFFSET_Y_M}" "${EXPECTED_OFFSET_Z_M}" "${EXPECTED_LOOKAHEAD_M}" \
  "${MAX_SOURCE_ERROR_M}" "${MAX_OFFSET_ERROR_M}" "${MAX_TARGET_POINT_ERROR_M}" \
  "${MAX_LOOKAHEAD_ERROR_M}" "${MIN_FORWARD_DOT}" >"${SUMMARY_FILE}" <<'PY'
import csv
import math
import sys
from collections import defaultdict

(
    centerline_csv,
    offset_csv,
    targets_csv,
    group_csv,
    expected_offset_y,
    expected_offset_z,
    expected_lookahead,
    max_source_error,
    max_offset_error,
    max_target_point_error,
    max_lookahead_error,
    min_forward_dot,
) = sys.argv[1:13]

expected_offset_y = float(expected_offset_y)
expected_offset_z = float(expected_offset_z)
expected_lookahead = float(expected_lookahead)
max_source_error = float(max_source_error)
max_offset_error = float(max_offset_error)
max_target_point_error = float(max_target_point_error)
max_lookahead_error = float(max_lookahead_error)
min_forward_dot = float(min_forward_dot)


def load_groups(path):
    groups = defaultdict(list)
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            groups[row["group_id"]].append(row)
    return groups


def xyz(row, prefix=""):
    return (
        float(row[f"{prefix}x"]),
        float(row[f"{prefix}y"]),
        float(row[f"{prefix}z"]),
    )


def source_xyz(row):
    return (float(row["source_x"]), float(row["source_y"]), float(row["source_z"]))


def target_xyz(row):
    return (float(row["target_x"]), float(row["target_y"]), float(row["target_z"]))


def current_xyz(row):
    return (float(row["current_x"]), float(row["current_y"]), float(row["current_z"]))


def tangent(row):
    return (float(row["tangent_x"]), float(row["tangent_y"]), float(row["tangent_z"]))


def dist(a, b):
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(3)))


def dot(a, b):
    return sum(a[i] * b[i] for i in range(3))


def sub(a, b):
    return tuple(a[i] - b[i] for i in range(3))


def norm(a):
    return math.sqrt(dot(a, a))


center_groups = load_groups(centerline_csv)
offset_groups = load_groups(offset_csv)
target_groups = load_groups(targets_csv)
group_ids = sorted(set(center_groups) | set(offset_groups) | set(target_groups))

rows = []
accepted_count = 0
global_max_source_error = 0.0
global_max_offset_y_error = 0.0
global_max_offset_z_error = 0.0
global_max_target_current_error = 0.0
global_max_target_point_error = 0.0
global_max_lookahead_error = 0.0
global_min_forward_dot = math.inf
global_min_tangent_norm = math.inf
global_max_tangent_norm = 0.0
total_targets = 0

for group_id in group_ids:
    center_rows = sorted(center_groups.get(group_id, []), key=lambda r: int(r["index"]))
    offset_rows = sorted(offset_groups.get(group_id, []), key=lambda r: int(r["index"]))
    target_rows = sorted(target_groups.get(group_id, []), key=lambda r: int(r["current_index"]))
    offset_by_index = {int(r["index"]): r for r in offset_rows}

    group_max_source_error = 0.0
    group_max_offset_y_error = 0.0
    group_max_offset_z_error = 0.0
    group_max_target_current_error = 0.0
    group_max_target_point_error = 0.0
    group_max_lookahead_error = 0.0
    group_min_forward_dot = math.inf
    group_min_tangent_norm = math.inf
    group_max_tangent_norm = 0.0
    monotonic_x = True
    target_index_forward = True
    target_index_exists = True
    source_index_match = len(center_rows) == len(offset_rows)

    previous_x = None
    for center_row, offset_row in zip(center_rows, offset_rows):
        center = xyz(center_row)
        offset = xyz(offset_row)
        source = source_xyz(offset_row)
        if int(center_row["index"]) != int(offset_row["index"]):
            source_index_match = False
        group_max_source_error = max(group_max_source_error, dist(center, source))
        group_max_offset_y_error = max(
            group_max_offset_y_error, abs((offset[1] - center[1]) - expected_offset_y)
        )
        group_max_offset_z_error = max(
            group_max_offset_z_error, abs((offset[2] - center[2]) - expected_offset_z)
        )
        tan = tangent(offset_row)
        tan_norm = norm(tan)
        group_min_tangent_norm = min(group_min_tangent_norm, tan_norm)
        group_max_tangent_norm = max(group_max_tangent_norm, tan_norm)
        if previous_x is not None and offset[0] <= previous_x:
            monotonic_x = False
        previous_x = offset[0]

    for target_row in target_rows:
        current_index = int(target_row["current_index"])
        target_index = int(target_row["target_index"])
        current_offset = offset_by_index.get(current_index)
        target_offset = offset_by_index.get(target_index)
        if target_offset is None or current_offset is None:
            target_index_exists = False
            continue
        if target_index <= current_index:
            target_index_forward = False
        current = current_xyz(target_row)
        target = target_xyz(target_row)
        current_expected = xyz(current_offset)
        target_expected = xyz(target_offset)
        group_max_target_current_error = max(
            group_max_target_current_error, dist(current, current_expected)
        )
        group_max_target_point_error = max(
            group_max_target_point_error, dist(target, target_expected)
        )
        lookahead_error = abs(float(target_row["target_distance"]) - expected_lookahead)
        group_max_lookahead_error = max(group_max_lookahead_error, lookahead_error)
        forward = sub(target, current)
        forward_norm = norm(forward)
        tan = tangent(current_offset)
        forward_dot = dot(forward, tan) / forward_norm if forward_norm > 0.0 else -math.inf
        group_min_forward_dot = min(group_min_forward_dot, forward_dot)

    if not target_rows:
        group_min_forward_dot = -math.inf
    if not offset_rows:
        group_min_tangent_norm = -math.inf

    group_pass = (
        bool(center_rows)
        and bool(offset_rows)
        and bool(target_rows)
        and len(center_rows) == len(offset_rows)
        and source_index_match
        and monotonic_x
        and target_index_exists
        and target_index_forward
        and group_max_source_error <= max_source_error
        and group_max_offset_y_error <= max_offset_error
        and group_max_offset_z_error <= max_offset_error
        and group_max_target_current_error <= max_target_point_error
        and group_max_target_point_error <= max_target_point_error
        and group_max_lookahead_error <= max_lookahead_error
        and group_min_forward_dot > min_forward_dot
        and 0.99 <= group_min_tangent_norm <= group_max_tangent_norm <= 1.01
    )
    if group_pass:
        accepted_count += 1

    global_max_source_error = max(global_max_source_error, group_max_source_error)
    global_max_offset_y_error = max(global_max_offset_y_error, group_max_offset_y_error)
    global_max_offset_z_error = max(global_max_offset_z_error, group_max_offset_z_error)
    global_max_target_current_error = max(
        global_max_target_current_error, group_max_target_current_error
    )
    global_max_target_point_error = max(global_max_target_point_error, group_max_target_point_error)
    global_max_lookahead_error = max(global_max_lookahead_error, group_max_lookahead_error)
    global_min_forward_dot = min(global_min_forward_dot, group_min_forward_dot)
    global_min_tangent_norm = min(global_min_tangent_norm, group_min_tangent_norm)
    global_max_tangent_norm = max(global_max_tangent_norm, group_max_tangent_norm)
    total_targets += len(target_rows)

    rows.append(
        {
            "group_id": group_id,
            "decision": "accepted" if group_pass else "rejected",
            "center_points": len(center_rows),
            "offset_points": len(offset_rows),
            "targets": len(target_rows),
            "max_source_error_m": group_max_source_error,
            "max_offset_y_error_m": group_max_offset_y_error,
            "max_offset_z_error_m": group_max_offset_z_error,
            "max_target_current_error_m": group_max_target_current_error,
            "max_target_point_error_m": group_max_target_point_error,
            "max_lookahead_error_m": group_max_lookahead_error,
            "min_forward_dot": group_min_forward_dot,
            "min_tangent_norm": group_min_tangent_norm,
            "max_tangent_norm": group_max_tangent_norm,
            "monotonic_x": monotonic_x,
            "target_index_forward": target_index_forward,
            "target_index_exists": target_index_exists,
        }
    )

with open(group_csv, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    writer.writeheader()
    writer.writerows(rows)

decision = "accepted_cable_frame_contract_audit" if accepted_count == len(group_ids) else "rejected_cable_frame_contract_audit"
reason = "centerline_offset_and_lookahead_frames_are_self_consistent" if decision.startswith("accepted") else "frame_contract_error_exceeds_threshold"

def metric(value):
    if math.isinf(value):
        return str(value)
    return f"{value:.9f}"

print("scope=cable_frame_contract")
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
print(f"group_count={len(group_ids)}")
print(f"accepted_group_count={accepted_count}")
print(f"total_targets={total_targets}")
print(f"expected_offset_y_m={expected_offset_y:.9f}")
print(f"expected_offset_z_m={expected_offset_z:.9f}")
print(f"expected_lookahead_m={expected_lookahead:.9f}")
print(f"global_max_source_error_m={metric(global_max_source_error)}")
print(f"global_max_offset_y_error_m={metric(global_max_offset_y_error)}")
print(f"global_max_offset_z_error_m={metric(global_max_offset_z_error)}")
print(f"global_max_target_current_error_m={metric(global_max_target_current_error)}")
print(f"global_max_target_point_error_m={metric(global_max_target_point_error)}")
print(f"global_max_lookahead_error_m={metric(global_max_lookahead_error)}")
print(f"global_min_forward_dot={metric(global_min_forward_dot)}")
print(f"global_min_tangent_norm={metric(global_min_tangent_norm)}")
print(f"global_max_tangent_norm={metric(global_max_tangent_norm)}")
print(f"claims_frame_contract_pass={str(decision.startswith('accepted')).lower()}")
PY

echo "Cable frame contract audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Group CSV: ${GROUP_CSV}"

grep -q "decision=accepted_cable_frame_contract_audit" "${SUMMARY_FILE}"
