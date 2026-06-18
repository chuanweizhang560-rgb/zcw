#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_FOURVIEW_CSV=""
if [[ -z "${FOURVIEW_CSV:-}" ]]; then
  DEFAULT_FOURVIEW_CSV="$(find data/results -path '*cable_fourview_surface_candidate_offline_*/*.csv' 2>/dev/null | sort | tail -n 1 || true)"
fi
FOURVIEW_CSV="${FOURVIEW_CSV:-${DEFAULT_FOURVIEW_CSV}}"
CABLE_RADIUS_M="${CABLE_RADIUS_M:-0.03}"
SURFACE_SAMPLES_PER_POINT="${SURFACE_SAMPLES_PER_POINT:-32}"
HFOV_DEG="${HFOV_DEG:-87.0}"
VFOV_DEG="${VFOV_DEG:-58.0}"
MIN_DISTANCE_M="${MIN_DISTANCE_M:-1.0}"
MAX_DISTANCE_M="${MAX_DISTANCE_M:-30.0}"
MIN_GROUPS="${MIN_GROUPS:-5}"
MIN_TOTAL_SURFACE_RATIO="${MIN_TOTAL_SURFACE_RATIO:-0.95}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_fourview_surface_union_offline_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_fourview_surface_union_offline_${STAMP}.txt"
GROUP_CSV="${RESULT_DIR}/cable_fourview_surface_union_offline_groups_${STAMP}.csv"

if [[ -z "${FOURVIEW_CSV}" || ! -f "${FOURVIEW_CSV}" ]]; then
  echo "Required input file does not exist: ${FOURVIEW_CSV}" >&2
  exit 1
fi

mkdir -p "${RESULT_DIR}"

python3 - "${FOURVIEW_CSV}" "${GROUP_CSV}" "${CABLE_RADIUS_M}" "${SURFACE_SAMPLES_PER_POINT}" \
  "${HFOV_DEG}" "${VFOV_DEG}" "${MIN_DISTANCE_M}" "${MAX_DISTANCE_M}" "${MIN_GROUPS}" \
  "${MIN_TOTAL_SURFACE_RATIO}" >"${SUMMARY_FILE}" <<'PY'
import csv
import math
import sys
from collections import defaultdict

(
    fourview_csv,
    group_csv,
    cable_radius_m,
    surface_samples_per_point,
    hfov_deg,
    vfov_deg,
    min_distance_m,
    max_distance_m,
    min_groups,
    min_total_surface_ratio,
) = sys.argv[1:11]
cable_radius_m = float(cable_radius_m)
surface_samples_per_point = int(surface_samples_per_point)
hfov_deg = float(hfov_deg)
vfov_deg = float(vfov_deg)
min_distance_m = float(min_distance_m)
max_distance_m = float(max_distance_m)
min_groups = int(min_groups)
min_total_surface_ratio = float(min_total_surface_ratio)


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def mul(a, s):
    return tuple(x * s for x in a)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def norm(a):
    return math.sqrt(dot(a, a))


def unit(a):
    n = norm(a)
    if n <= 1e-12:
        return (0.0, 0.0, 0.0)
    return tuple(x / n for x in a)


def fov_basis(forward):
    world_up = (0.0, 0.0, 1.0)
    right = unit(cross(forward, world_up))
    if norm(right) <= 1e-12:
        right = (1.0, 0.0, 0.0)
    up = unit(cross(right, forward))
    return right, up


groups = defaultdict(list)
with open(fourview_csv, newline="") as f:
    for row in csv.DictReader(f):
        for key in ("camera_x", "camera_y", "camera_z", "target_x", "target_y", "target_z"):
            row[key] = float(row[key])
        row["index"] = int(row["index"])
        groups[row["source_group_id"]].append(row)

hfov = math.radians(hfov_deg)
vfov = math.radians(vfov_deg)
group_rows = []
accepted_group_count = 0

for group_id in sorted(groups):
    by_index = defaultdict(list)
    view_names = set()
    for row in groups[group_id]:
        by_index[row["index"]].append(row)
        view_names.add(row["view_name"])
    total = 0
    covered_union = 0
    for index in sorted(by_index):
        rows = by_index[index]
        target = (rows[0]["target_x"], rows[0]["target_y"], rows[0]["target_z"])
        for sample_idx in range(surface_samples_per_point):
            theta = 2.0 * math.pi * sample_idx / surface_samples_per_point
            normal = (0.0, math.cos(theta), math.sin(theta))
            surfel = add(target, mul(normal, cable_radius_m))
            covered = False
            for row in rows:
                camera = (row["camera_x"], row["camera_y"], row["camera_z"])
                forward = unit(sub(target, camera))
                right, up = fov_basis(forward)
                camera_to_surfel = sub(surfel, camera)
                surfel_to_camera = sub(camera, surfel)
                distance = norm(camera_to_surfel)
                distance_ok = min_distance_m <= distance <= max_distance_m
                x_angle = math.atan2(dot(camera_to_surfel, right), dot(camera_to_surfel, forward))
                y_angle = math.atan2(dot(camera_to_surfel, up), dot(camera_to_surfel, forward))
                fov_ok = abs(x_angle) <= hfov / 2.0 and abs(y_angle) <= vfov / 2.0
                normal_ok = dot(normal, surfel_to_camera) > 0.0
                if distance_ok and fov_ok and normal_ok:
                    covered = True
                    break
            total += 1
            if covered:
                covered_union += 1
    total_ratio = covered_union / total if total else 0.0
    group_ok = len(view_names) >= 4 and total_ratio >= min_total_surface_ratio
    if group_ok:
        accepted_group_count += 1
    group_rows.append(
        {
            "group_id": group_id,
            "decision": "accepted_fourview_union_group" if group_ok else "rejected_fourview_union_group",
            "view_count": len(view_names),
            "pose_count": len(groups[group_id]),
            "surface_samples": total,
            "union_covered_samples": covered_union,
            "total_surface_coverage_upper_bound_ratio": total_ratio,
        }
    )

with open(group_csv, "w", newline="") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "group_id",
            "decision",
            "view_count",
            "pose_count",
            "surface_samples",
            "union_covered_samples",
            "total_surface_coverage_upper_bound_ratio",
        ],
    )
    writer.writeheader()
    writer.writerows(group_rows)

global_min_total = min((r["total_surface_coverage_upper_bound_ratio"] for r in group_rows), default=0.0)
accepted = len(group_rows) >= min_groups and accepted_group_count >= min_groups
decision = "accepted_cable_fourview_surface_union_offline" if accepted else "rejected_cable_fourview_surface_union_offline"
reason = "fourview_surface_union_characterized" if accepted else "fourview_surface_union_failed"

print("scope=cable_fourview_surface_union_offline")
print(f"decision={decision}")
print(f"reason={reason}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print(f"fourview_csv={fourview_csv}")
print(f"group_csv={group_csv}")
print(f"surface_samples_per_point={surface_samples_per_point}")
print(f"hfov_deg={hfov_deg:.9f}")
print(f"vfov_deg={vfov_deg:.9f}")
print(f"min_total_surface_ratio={min_total_surface_ratio:.9f}")
print(f"group_count={len(group_rows)}")
print(f"accepted_group_count={accepted_group_count}")
print(f"global_min_total_surface_coverage_upper_bound_ratio={global_min_total:.9f}")
print(f"meets_total_surface_target={str(global_min_total >= min_total_surface_ratio).lower()}")
print("occlusion_gate_implemented=false")
print("uses_real_camera_trajectory=false")
print("claims_active_control_approval=false")
print("claims_final_cable_inspection_coverage=false")
print(f"claims_fourview_surface_union_offline_pass={str(accepted).lower()}")
PY

echo "Cable four-view surface union offline audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Group CSV: ${GROUP_CSV}"

grep -q "decision=accepted_cable_fourview_surface_union_offline" "${SUMMARY_FILE}"
