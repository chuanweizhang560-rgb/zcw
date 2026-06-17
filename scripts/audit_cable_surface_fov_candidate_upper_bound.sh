#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_POSE_CSV="data/results/cable_surface_observation_pose_candidate_20260617_091638/cable_surface_observation_pose_candidate_20260617_091638.csv"
POSE_CSV="${POSE_CSV:-${DEFAULT_POSE_CSV}}"
CABLE_RADIUS_M="${CABLE_RADIUS_M:-0.03}"
SURFACE_SAMPLES_PER_POINT="${SURFACE_SAMPLES_PER_POINT:-16}"
HFOV_DEG="${HFOV_DEG:-87.0}"
VFOV_DEG="${VFOV_DEG:-58.0}"
MIN_DISTANCE_M="${MIN_DISTANCE_M:-1.0}"
MAX_DISTANCE_M="${MAX_DISTANCE_M:-30.0}"
MIN_GROUPS="${MIN_GROUPS:-5}"
MIN_TOTAL_SURFACE_RATIO="${MIN_TOTAL_SURFACE_RATIO:-0.90}"
MIN_VISIBLE_SIDE_RATIO="${MIN_VISIBLE_SIDE_RATIO:-0.95}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_surface_fov_candidate_upper_bound_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_surface_fov_candidate_upper_bound_${STAMP}.txt"
GROUP_CSV="${RESULT_DIR}/cable_surface_fov_candidate_upper_bound_groups_${STAMP}.csv"

if [[ ! -f "${POSE_CSV}" ]]; then
  echo "Required input file does not exist: ${POSE_CSV}" >&2
  exit 1
fi

mkdir -p "${RESULT_DIR}"

python3 - "${POSE_CSV}" "${GROUP_CSV}" "${CABLE_RADIUS_M}" "${SURFACE_SAMPLES_PER_POINT}" \
  "${HFOV_DEG}" "${VFOV_DEG}" "${MIN_DISTANCE_M}" "${MAX_DISTANCE_M}" "${MIN_GROUPS}" \
  "${MIN_TOTAL_SURFACE_RATIO}" "${MIN_VISIBLE_SIDE_RATIO}" >"${SUMMARY_FILE}" <<'PY'
import csv
import math
import sys
from collections import defaultdict

(
    pose_csv,
    group_csv,
    cable_radius_m,
    surface_samples_per_point,
    hfov_deg,
    vfov_deg,
    min_distance_m,
    max_distance_m,
    min_groups,
    min_total_surface_ratio,
    min_visible_side_ratio,
) = sys.argv[1:12]
cable_radius_m = float(cable_radius_m)
surface_samples_per_point = int(surface_samples_per_point)
hfov_deg = float(hfov_deg)
vfov_deg = float(vfov_deg)
min_distance_m = float(min_distance_m)
max_distance_m = float(max_distance_m)
min_groups = int(min_groups)
min_total_surface_ratio = float(min_total_surface_ratio)
min_visible_side_ratio = float(min_visible_side_ratio)


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


def angle_rad(num, den):
    return math.atan2(num, den)


groups = defaultdict(list)
with open(pose_csv, newline="") as f:
    for row in csv.DictReader(f):
        for key in (
            "camera_x",
            "camera_y",
            "camera_z",
            "target_x",
            "target_y",
            "target_z",
        ):
            row[key] = float(row[key])
        row["index"] = int(row["index"])
        groups[row["group_id"]].append(row)

for rows in groups.values():
    rows.sort(key=lambda r: r["index"])

hfov = math.radians(hfov_deg)
vfov = math.radians(vfov_deg)
world_up = (0.0, 0.0, 1.0)
group_rows = []
accepted_group_count = 0

for group_id in sorted(groups):
    rows = groups[group_id]
    total = 0
    visible_side = 0
    covered = 0
    distance_ok_count = 0
    fov_ok_count = 0
    normal_ok_count = 0
    for row in rows:
        camera = (row["camera_x"], row["camera_y"], row["camera_z"])
        target = (row["target_x"], row["target_y"], row["target_z"])
        forward = unit(sub(target, camera))
        right = unit(cross(forward, world_up))
        if norm(right) <= 1e-12:
            right = (1.0, 0.0, 0.0)
        up = unit(cross(right, forward))

        # Current cable candidates are approximately x-directed; sample cylinder in YZ.
        for sample_idx in range(surface_samples_per_point):
            theta = 2.0 * math.pi * sample_idx / surface_samples_per_point
            normal = (0.0, math.cos(theta), math.sin(theta))
            surfel = add(target, mul(normal, cable_radius_m))
            camera_to_surfel = sub(surfel, camera)
            surfel_to_camera = sub(camera, surfel)
            distance = norm(camera_to_surfel)
            distance_ok = min_distance_m <= distance <= max_distance_m
            x_angle = angle_rad(dot(camera_to_surfel, right), dot(camera_to_surfel, forward))
            y_angle = angle_rad(dot(camera_to_surfel, up), dot(camera_to_surfel, forward))
            fov_ok = abs(x_angle) <= hfov / 2.0 and abs(y_angle) <= vfov / 2.0
            normal_ok = dot(normal, surfel_to_camera) > 0.0
            total += 1
            if normal_ok:
                visible_side += 1
            if distance_ok:
                distance_ok_count += 1
            if fov_ok:
                fov_ok_count += 1
            if normal_ok:
                normal_ok_count += 1
            if distance_ok and fov_ok and normal_ok:
                covered += 1

    total_ratio = covered / total if total else 0.0
    visible_side_ratio = covered / visible_side if visible_side else 0.0
    distance_ratio = distance_ok_count / total if total else 0.0
    fov_ratio = fov_ok_count / total if total else 0.0
    normal_ratio = normal_ok_count / total if total else 0.0
    visible_side_ready = visible_side_ratio >= min_visible_side_ratio
    if visible_side_ready:
        accepted_group_count += 1
    group_rows.append(
        {
            "group_id": group_id,
            "decision": "accepted_visible_side_upper_bound_group" if visible_side_ready else "rejected_visible_side_upper_bound_group",
            "pose_count": len(rows),
            "surface_samples": total,
            "covered_samples": covered,
            "visible_side_samples": visible_side,
            "distance_ok_ratio": distance_ratio,
            "fov_ok_ratio": fov_ratio,
            "normal_visible_ratio": normal_ratio,
            "total_surface_coverage_upper_bound_ratio": total_ratio,
            "visible_side_coverage_upper_bound_ratio": visible_side_ratio,
        }
    )

with open(group_csv, "w", newline="") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "group_id",
            "decision",
            "pose_count",
            "surface_samples",
            "covered_samples",
            "visible_side_samples",
            "distance_ok_ratio",
            "fov_ok_ratio",
            "normal_visible_ratio",
            "total_surface_coverage_upper_bound_ratio",
            "visible_side_coverage_upper_bound_ratio",
        ],
    )
    writer.writeheader()
    writer.writerows(group_rows)

global_total_surface_ratio = min((r["total_surface_coverage_upper_bound_ratio"] for r in group_rows), default=0.0)
global_visible_side_ratio = min((r["visible_side_coverage_upper_bound_ratio"] for r in group_rows), default=0.0)
global_fov_ratio = min((r["fov_ok_ratio"] for r in group_rows), default=0.0)
accepted = len(group_rows) >= min_groups and accepted_group_count >= min_groups
meets_total_surface_target = global_total_surface_ratio >= min_total_surface_ratio
decision = "accepted_cable_surface_fov_candidate_upper_bound_characterization" if accepted else "rejected_cable_surface_fov_candidate_upper_bound_characterization"
reason = "candidate_visible_side_upper_bound_characterized" if accepted else "candidate_visible_side_upper_bound_failed"

print("scope=cable_surface_fov_candidate_upper_bound")
print(f"decision={decision}")
print(f"reason={reason}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print(f"pose_csv={pose_csv}")
print(f"group_csv={group_csv}")
print(f"cable_radius_m={cable_radius_m:.9f}")
print(f"surface_samples_per_point={surface_samples_per_point}")
print(f"hfov_deg={hfov_deg:.9f}")
print(f"vfov_deg={vfov_deg:.9f}")
print(f"min_distance_m={min_distance_m:.9f}")
print(f"max_distance_m={max_distance_m:.9f}")
print(f"min_total_surface_ratio={min_total_surface_ratio:.9f}")
print(f"min_visible_side_ratio={min_visible_side_ratio:.9f}")
print(f"group_count={len(group_rows)}")
print(f"accepted_group_count={accepted_group_count}")
print(f"global_min_total_surface_coverage_upper_bound_ratio={global_total_surface_ratio:.9f}")
print(f"global_min_visible_side_coverage_upper_bound_ratio={global_visible_side_ratio:.9f}")
print(f"global_min_fov_ok_ratio={global_fov_ratio:.9f}")
print(f"visible_side_upper_bound_ready={str(accepted).lower()}")
print(f"meets_total_surface_target={str(meets_total_surface_target).lower()}")
print("occlusion_gate_implemented=false")
print("uses_real_camera_trajectory=false")
print("claims_active_control_approval=false")
print("claims_final_cable_inspection_coverage=false")
print(f"claims_fov_candidate_upper_bound_characterized={str(accepted).lower()}")
PY

echo "Cable surface FOV candidate upper-bound audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Group CSV: ${GROUP_CSV}"

grep -q "decision=accepted_cable_surface_fov_candidate_upper_bound_characterization" "${SUMMARY_FILE}"
