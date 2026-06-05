#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_OFFSET_PATH="data/results/catenary_offset_yz_zbin2_20260603_135000/depth_camera_motion_catenary_offset_yz_zbin2_offset_path_20260603_125948.csv"
DEFAULT_TARGETS="data/results/lookahead_target_audit_20260603_165600/depth_camera_motion_lookahead_target_audit_targets_20260603_165501.csv"

OFFSET_PATH_CSV="${OFFSET_PATH_CSV:-${DEFAULT_OFFSET_PATH}}"
TARGETS_CSV="${TARGETS_CSV:-${DEFAULT_TARGETS}}"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${RESULT_ROOT}/cable_path_geometry_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_path_geometry_${STAMP}.txt"
GROUP_CSV="${RESULT_DIR}/cable_path_geometry_groups_${STAMP}.csv"

MIN_POINTS_PER_GROUP="${MIN_POINTS_PER_GROUP:-3}"
MIN_TARGETS_PER_GROUP="${MIN_TARGETS_PER_GROUP:-2}"
MIN_EXPECTED_LOOKAHEAD_M="${MIN_EXPECTED_LOOKAHEAD_M:-19.5}"
MAX_EXPECTED_LOOKAHEAD_M="${MAX_EXPECTED_LOOKAHEAD_M:-20.5}"
MAX_STEP_M="${MAX_STEP_M:-10.5}"
MAX_LATERAL_STEP_M="${MAX_LATERAL_STEP_M:-0.5}"

for path in "${OFFSET_PATH_CSV}" "${TARGETS_CSV}"; do
  if [[ ! -f "${path}" ]]; then
    echo "Required input does not exist: ${path}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

python3 - "$OFFSET_PATH_CSV" "$TARGETS_CSV" "$GROUP_CSV" \
  "$MIN_POINTS_PER_GROUP" "$MIN_TARGETS_PER_GROUP" \
  "$MIN_EXPECTED_LOOKAHEAD_M" "$MAX_EXPECTED_LOOKAHEAD_M" \
  "$MAX_STEP_M" "$MAX_LATERAL_STEP_M" >"${SUMMARY_FILE}" <<'PY'
import csv
import math
import sys
from collections import defaultdict

offset_path_csv, targets_csv, group_csv = sys.argv[1:4]
min_points_per_group = int(sys.argv[4])
min_targets_per_group = int(sys.argv[5])
min_expected_lookahead_m = float(sys.argv[6])
max_expected_lookahead_m = float(sys.argv[7])
max_step_m = float(sys.argv[8])
max_lateral_step_m = float(sys.argv[9])

def load_rows(path):
    with open(path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        return list(reader)

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

accepted_groups = 0
rows = []
for group_id in group_ids:
    path_rows = sorted(offset_groups[group_id], key=lambda r: int(r["index"]))
    tgt_rows = sorted(target_groups[group_id], key=lambda r: int(r["current_index"]))
    path_points = len(path_rows)
    target_points = len(tgt_rows)

    if path_points < min_points_per_group or target_points < min_targets_per_group:
        rows.append((group_id, path_points, target_points, 0.0, 0.0, 0.0, 0.0, False))
        continue

    path_step_dists = []
    lateral_steps = []
    path_monotonic = True
    target_monotonic = True
    prev_x = prev_y = prev_z = None
    prev_target_index = None
    target_distances = []
    target_x_deltas = []
    target_y_deltas = []
    target_z_deltas = []

    for row in path_rows:
        x = float(row["x"])
        y = float(row["y"])
        z = float(row["z"])
        if prev_x is not None:
            dx = x - prev_x
            dy = y - prev_y
            dz = z - prev_z
            step = math.sqrt(dx * dx + dy * dy + dz * dz)
            path_step_dists.append(step)
            lateral_steps.append(math.sqrt(dy * dy + dz * dz))
            if step > max_step_m or math.sqrt(dy * dy + dz * dz) > max_lateral_step_m:
                path_monotonic = False
        prev_x, prev_y, prev_z = x, y, z

    prev_target_idx = None
    for row in tgt_rows:
        current_x = float(row["current_x"])
        current_y = float(row["current_y"])
        current_z = float(row["current_z"])
        target_x = float(row["target_x"])
        target_y = float(row["target_y"])
        target_z = float(row["target_z"])
        target_distance = float(row["target_distance"])
        target_distances.append(target_distance)
        target_x_deltas.append(target_x - current_x)
        target_y_deltas.append(target_y - current_y)
        target_z_deltas.append(target_z - current_z)
        if not (min_expected_lookahead_m <= target_distance <= max_expected_lookahead_m):
            target_monotonic = False
        if prev_target_idx is not None and int(row["target_index"]) <= prev_target_idx:
            target_monotonic = False
        prev_target_idx = int(row["target_index"])

    mean_step = sum(path_step_dists) / len(path_step_dists) if path_step_dists else 0.0
    max_step = max(path_step_dists) if path_step_dists else 0.0
    max_lateral_step = max(lateral_steps) if lateral_steps else 0.0
    mean_target_distance = sum(target_distances) / len(target_distances) if target_distances else 0.0
    min_target_distance = min(target_distances) if target_distances else 0.0
    max_target_distance = max(target_distances) if target_distances else 0.0
    mean_target_x_delta = sum(target_x_deltas) / len(target_x_deltas) if target_x_deltas else 0.0
    mean_target_y_delta = sum(target_y_deltas) / len(target_y_deltas) if target_y_deltas else 0.0
    mean_target_z_delta = sum(target_z_deltas) / len(target_z_deltas) if target_z_deltas else 0.0

    accepted = path_monotonic and target_monotonic
    if accepted:
        accepted_groups += 1
    rows.append((
        group_id, path_points, target_points,
        mean_step, max_step, max_lateral_step,
        mean_target_distance, min_target_distance, max_target_distance,
        mean_target_x_delta, mean_target_y_delta, mean_target_z_delta,
        accepted,
    ))

with open(group_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow([
        "group_id",
        "path_points",
        "target_points",
        "mean_path_step_m",
        "max_path_step_m",
        "max_lateral_step_m",
        "mean_target_distance_m",
        "min_target_distance_m",
        "max_target_distance_m",
        "mean_target_x_delta_m",
        "mean_target_y_delta_m",
        "mean_target_z_delta_m",
        "accepted",
    ])
    for row in rows:
        writer.writerow([
            row[0], row[1], row[2],
            f"{row[3]:.6f}", f"{row[4]:.6f}", f"{row[5]:.6f}",
            f"{row[6]:.6f}", f"{row[7]:.6f}", f"{row[8]:.6f}",
            f"{row[9]:.6f}", f"{row[10]:.6f}", f"{row[11]:.6f}",
            str(bool(row[12])).lower(),
        ])

all_accepted = accepted_groups == len(rows) and len(rows) > 0
decision = "accepted_cable_path_geometry_audit" if all_accepted else "rejected_cable_path_geometry_audit"
reason = "path_and_lookahead_geometry_are_consistent" if all_accepted else "path_or_lookahead_geometry_exceeds_bounds"

print("scope=cable_path_geometry_audit")
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
print(f"min_points_per_group={min_points_per_group}")
print(f"min_targets_per_group={min_targets_per_group}")
print(f"min_expected_lookahead_m={min_expected_lookahead_m:.6f}")
print(f"max_expected_lookahead_m={max_expected_lookahead_m:.6f}")
print(f"max_step_m={max_step_m:.6f}")
print(f"max_lateral_step_m={max_lateral_step_m:.6f}")
for row in rows:
    print(
        "group={group_id} path_points={path_points} target_points={target_points} "
        "mean_path_step_m={mean_path_step_m:.6f} max_path_step_m={max_path_step_m:.6f} "
        "max_lateral_step_m={max_lateral_step_m:.6f} mean_target_distance_m={mean_target_distance_m:.6f} "
        "accepted={accepted}".format(
            group_id=row[0],
            path_points=row[1],
            target_points=row[2],
            mean_path_step_m=row[3],
            max_path_step_m=row[4],
            max_lateral_step_m=row[5],
            mean_target_distance_m=row[6],
            accepted=str(bool(row[12])).lower(),
        )
    )

if not all_accepted:
    raise SystemExit(2)
PY

echo "Cable path geometry audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Group CSV: ${GROUP_CSV}"
