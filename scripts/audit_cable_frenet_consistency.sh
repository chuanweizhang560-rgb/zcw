#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_OFFSET_PATH="data/results/catenary_offset_yz_zbin2_step5_20260608_000000/depth_camera_motion_catenary_offset_yz_zbin2_step5_offset_path_20260608_085655.csv"
DEFAULT_TARGETS="data/results/lookahead_target_step5_20m_strict_20260608_090000/depth_camera_motion_lookahead_step5_20m_strict_targets_20260608_085945.csv"

OFFSET_PATH_CSV="${OFFSET_PATH_CSV:-${DEFAULT_OFFSET_PATH}}"
TARGETS_CSV="${TARGETS_CSV:-${DEFAULT_TARGETS}}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${RESULT_ROOT}/cable_frenet_consistency_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_frenet_consistency_${STAMP}.txt"
GROUP_CSV="${RESULT_DIR}/cable_frenet_consistency_groups_${STAMP}.csv"

MIN_POINTS_PER_GROUP="${MIN_POINTS_PER_GROUP:-3}"
MIN_TARGETS_PER_GROUP="${MIN_TARGETS_PER_GROUP:-2}"
EXPECTED_OFFSET_Y_M="${EXPECTED_OFFSET_Y_M:--5.0}"
EXPECTED_OFFSET_Z_M="${EXPECTED_OFFSET_Z_M:-0.0}"
MIN_PATH_TANGENT_DOT="${MIN_PATH_TANGENT_DOT:-0.9995}"
MIN_TARGET_TANGENT_DOT="${MIN_TARGET_TANGENT_DOT:-0.9995}"
MIN_EXPECTED_LOOKAHEAD_M="${MIN_EXPECTED_LOOKAHEAD_M:-19.5}"
MAX_EXPECTED_LOOKAHEAD_M="${MAX_EXPECTED_LOOKAHEAD_M:-20.5}"

for path in "${OFFSET_PATH_CSV}" "${TARGETS_CSV}"; do
  if [[ ! -f "${path}" ]]; then
    echo "Required input does not exist: ${path}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

python3 - "$OFFSET_PATH_CSV" "$TARGETS_CSV" "$GROUP_CSV" \
  "$MIN_POINTS_PER_GROUP" "$MIN_TARGETS_PER_GROUP" \
  "$EXPECTED_OFFSET_Y_M" "$EXPECTED_OFFSET_Z_M" \
  "$MIN_PATH_TANGENT_DOT" "$MIN_TARGET_TANGENT_DOT" \
  "$MIN_EXPECTED_LOOKAHEAD_M" "$MAX_EXPECTED_LOOKAHEAD_M" >"${SUMMARY_FILE}" <<'PY'
import csv
import math
import sys
from collections import defaultdict

offset_path_csv, targets_csv, group_csv = sys.argv[1:4]
min_points_per_group = int(sys.argv[4])
min_targets_per_group = int(sys.argv[5])
expected_offset_y_m = float(sys.argv[6])
expected_offset_z_m = float(sys.argv[7])
min_path_tangent_dot = float(sys.argv[8])
min_target_tangent_dot = float(sys.argv[9])
min_expected_lookahead_m = float(sys.argv[10])
max_expected_lookahead_m = float(sys.argv[11])

def load_rows(path):
    with open(path, "r", encoding="utf-8") as f:
        return list(csv.DictReader(f))

def norm(x, y, z):
    return math.sqrt(x * x + y * y + z * z)

def normalize(x, y, z):
    n = norm(x, y, z)
    if n <= 1e-12:
        return None
    return x / n, y / n, z / n

offset_rows = load_rows(offset_path_csv)
target_rows = load_rows(targets_csv)

offset_groups = defaultdict(list)
target_groups = defaultdict(list)
for row in offset_rows:
    offset_groups[row["group_id"]].append(row)
for row in target_rows:
    target_groups[row["group_id"]].append(row)

group_ids = sorted(set(offset_groups) & set(target_groups))
if not group_ids:
    raise SystemExit("no common groups between offset path and lookahead target CSVs")

rows = []
accepted_groups = 0
for group_id in group_ids:
    path_rows = sorted(offset_groups[group_id], key=lambda r: int(r["index"]))
    tgt_rows = sorted(target_groups[group_id], key=lambda r: int(r["current_index"]))
    if len(path_rows) < min_points_per_group or len(tgt_rows) < min_targets_per_group:
        rows.append((group_id, len(path_rows), len(tgt_rows), 0.0, 0.0, 0.0, 0.0, 0.0, False))
        continue

    offset_y_vals = [float(r["offset_y_m"]) for r in path_rows]
    offset_z_vals = [float(r["offset_z_m"]) for r in path_rows]
    offset_y_error = max(abs(v - expected_offset_y_m) for v in offset_y_vals) if offset_y_vals else 0.0
    offset_z_error = max(abs(v - expected_offset_z_m) for v in offset_z_vals) if offset_z_vals else 0.0

    path_tangent_dots = []
    path_steps = []
    prev = None
    for row in path_rows:
        x = float(row["x"])
        y = float(row["y"])
        z = float(row["z"])
        tx = float(row["tangent_x"])
        ty = float(row["tangent_y"])
        tz = float(row["tangent_z"])
        tangent = normalize(tx, ty, tz)
        if prev is not None and tangent is not None:
            dx = x - prev[0]
            dy = y - prev[1]
            dz = z - prev[2]
            direction = normalize(dx, dy, dz)
            if direction is not None:
                dot = direction[0] * tangent[0] + direction[1] * tangent[1] + direction[2] * tangent[2]
                path_tangent_dots.append(dot)
                path_steps.append(norm(dx, dy, dz))
        prev = (x, y, z)

    target_tangent_dots = []
    target_distances = []
    prev_target_index = None
    target_monotonic = True
    for row in tgt_rows:
        current_x = float(row["current_x"])
        current_y = float(row["current_y"])
        current_z = float(row["current_z"])
        target_x = float(row["target_x"])
        target_y = float(row["target_y"])
        target_z = float(row["target_z"])
        target_distance = float(row["target_distance"])
        tx = float(row["tangent_x"])
        ty = float(row["tangent_y"])
        tz = float(row["tangent_z"])
        tangent = normalize(tx, ty, tz)
        direction = normalize(target_x - current_x, target_y - current_y, target_z - current_z)
        if tangent is not None and direction is not None:
            target_tangent_dots.append(direction[0] * tangent[0] + direction[1] * tangent[1] + direction[2] * tangent[2])
        target_distances.append(target_distance)
        if not (min_expected_lookahead_m <= target_distance <= max_expected_lookahead_m):
            target_monotonic = False
        target_index = int(row["target_index"])
        if prev_target_index is not None and target_index <= prev_target_index:
            target_monotonic = False
        prev_target_index = target_index

    mean_path_step = sum(path_steps) / len(path_steps) if path_steps else 0.0
    mean_path_tangent_dot = sum(path_tangent_dots) / len(path_tangent_dots) if path_tangent_dots else 0.0
    min_path_tangent_dot_observed = min(path_tangent_dots) if path_tangent_dots else 0.0
    mean_target_distance = sum(target_distances) / len(target_distances) if target_distances else 0.0
    mean_target_tangent_dot = sum(target_tangent_dots) / len(target_tangent_dots) if target_tangent_dots else 0.0
    min_target_tangent_dot_observed = min(target_tangent_dots) if target_tangent_dots else 0.0

    accepted = (
        abs(offset_y_error) <= 1e-6 and
        abs(offset_z_error) <= 1e-6 and
        mean_path_tangent_dot >= min_path_tangent_dot and
        min_path_tangent_dot_observed >= min_path_tangent_dot and
        mean_target_tangent_dot >= min_target_tangent_dot and
        min_target_tangent_dot_observed >= min_target_tangent_dot and
        target_monotonic
    )
    if accepted:
        accepted_groups += 1
    rows.append((
        group_id, len(path_rows), len(tgt_rows),
        offset_y_error, offset_z_error,
        mean_path_step, mean_path_tangent_dot, min_path_tangent_dot_observed,
        mean_target_distance, mean_target_tangent_dot, min_target_tangent_dot_observed,
        accepted,
    ))

with open(group_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow([
        "group_id",
        "path_points",
        "target_points",
        "offset_y_error_m",
        "offset_z_error_m",
        "mean_path_step_m",
        "mean_path_tangent_dot",
        "min_path_tangent_dot",
        "mean_target_distance_m",
        "mean_target_tangent_dot",
        "min_target_tangent_dot",
        "accepted",
    ])
    for row in rows:
        writer.writerow([
            row[0], row[1], row[2],
            f"{row[3]:.6f}", f"{row[4]:.6f}",
            f"{row[5]:.6f}", f"{row[6]:.6f}", f"{row[7]:.6f}",
            f"{row[8]:.6f}", f"{row[9]:.6f}", f"{row[10]:.6f}",
            str(bool(row[11])).lower(),
        ])

all_accepted = accepted_groups == len(rows) and len(rows) > 0
decision = "accepted_cable_frenet_consistency_audit" if all_accepted else "rejected_cable_frenet_consistency_audit"
reason = "frenet_geometry_is_consistent" if all_accepted else "frenet_geometry_exceeds_bounds"

print("scope=cable_frenet_consistency_audit")
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
print(f"targets_csv={targets_csv}")
print(f"group_csv={group_csv}")
print(f"group_count={len(rows)}")
print(f"accepted_group_count={accepted_groups}")
print(f"expected_offset_y_m={expected_offset_y_m:.6f}")
print(f"expected_offset_z_m={expected_offset_z_m:.6f}")
print(f"min_path_tangent_dot={min_path_tangent_dot:.6f}")
print(f"min_target_tangent_dot={min_target_tangent_dot:.6f}")
for row in rows:
    print(
        "group={group_id} path_points={path_points} target_points={target_points} "
        "offset_y_error_m={offset_y_error_m:.6f} offset_z_error_m={offset_z_error_m:.6f} "
        "mean_path_step_m={mean_path_step_m:.6f} mean_path_tangent_dot={mean_path_tangent_dot:.6f} "
        "min_path_tangent_dot={min_path_tangent_dot:.6f} mean_target_distance_m={mean_target_distance_m:.6f} "
        "mean_target_tangent_dot={mean_target_tangent_dot:.6f} min_target_tangent_dot={min_target_tangent_dot:.6f} "
        "accepted={accepted}".format(
            group_id=row[0],
            path_points=row[1],
            target_points=row[2],
            offset_y_error_m=row[3],
            offset_z_error_m=row[4],
            mean_path_step_m=row[5],
            mean_path_tangent_dot=row[6],
            min_path_tangent_dot=row[7],
            mean_target_distance_m=row[8],
            mean_target_tangent_dot=row[9],
            min_target_tangent_dot=row[10],
            accepted=str(bool(row[11])).lower(),
        )
    )

if not all_accepted:
    raise SystemExit(2)
PY

echo "Cable Frenet consistency audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Group CSV: ${GROUP_CSV}"
