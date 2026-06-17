#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DEFAULT_MULTIVIEW_CSV="data/results/cable_multiview_surface_candidate_offline_20260617_094219/cable_multiview_surface_candidate_offline_20260617_094219.csv"
MULTIVIEW_CSV="${MULTIVIEW_CSV:-${DEFAULT_MULTIVIEW_CSV}}"
CABLE_RADIUS_M="${CABLE_RADIUS_M:-0.03}"
SURFACE_SAMPLES_PER_POINT="${SURFACE_SAMPLES_PER_POINT:-16}"
HFOV_DEG="${HFOV_DEG:-87.0}"
VFOV_DEG="${VFOV_DEG:-58.0}"
MIN_DISTANCE_M="${MIN_DISTANCE_M:-1.0}"
MAX_DISTANCE_M="${MAX_DISTANCE_M:-30.0}"
MIN_GROUPS="${MIN_GROUPS:-5}"
MIN_TOTAL_SURFACE_RATIO="${MIN_TOTAL_SURFACE_RATIO:-0.85}"
MIN_VISIBLE_SIDE_RATIO="${MIN_VISIBLE_SIDE_RATIO:-1.00}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_multiview_surface_union_offline_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_multiview_surface_union_offline_${STAMP}.txt"
GROUP_CSV="${RESULT_DIR}/cable_multiview_surface_union_offline_groups_${STAMP}.csv"

if [[ ! -f "${MULTIVIEW_CSV}" ]]; then
  echo "Required input file does not exist: ${MULTIVIEW_CSV}" >&2
  exit 1
fi

mkdir -p "${RESULT_DIR}"

python3 - "${MULTIVIEW_CSV}" "${GROUP_CSV}" "${CABLE_RADIUS_M}" "${SURFACE_SAMPLES_PER_POINT}" \
  "${HFOV_DEG}" "${VFOV_DEG}" "${MIN_DISTANCE_M}" "${MAX_DISTANCE_M}" "${MIN_GROUPS}" \
  "${MIN_TOTAL_SURFACE_RATIO}" "${MIN_VISIBLE_SIDE_RATIO}" >"${SUMMARY_FILE}" <<'PY'
import csv
import math
import sys
from collections import defaultdict

(
    multiview_csv,
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
with open(multiview_csv, newline="") as f:
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
        groups[row["source_group_id"]].append(row)

for rows in groups.values():
    rows.sort(key=lambda r: (r["view_name"], r["index"]))

hfov = math.radians(hfov_deg)
vfov = math.radians(vfov_deg)
world_up = (0.0, 0.0, 1.0)
group_rows = []
accepted_group_count = 0

for group_id in sorted(groups):
    rows = groups[group_id]
    views = defaultdict(list)
    for row in rows:
        views[row["view_name"]].append(row)
    total = 0
    covered_union = 0
    visible_side_union = 0
    side_a_covered = 0
    side_b_covered = 0
    distance_ok_count = 0
    fov_ok_count = 0
    normal_ok_count = 0
    for index in range(len(rows) // 2):
        # side A and side B rows are matched by index after grouping above.
        row_a = views.get("side_a", [])[index]
        row_b = views.get("side_b", [])[index]
        target = (row_a["target_x"], row_a["target_y"], row_a["target_z"])
        cam_a = (row_a["camera_x"], row_a["camera_y"], row_a["camera_z"])
        cam_b = (row_b["camera_x"], row_b["camera_y"], row_b["camera_z"])

        forward_a = unit(sub(target, cam_a))
        forward_b = unit(sub(target, cam_b))
        right_a = unit(cross(forward_a, world_up))
        right_b = unit(cross(forward_b, world_up))
        if norm(right_a) <= 1e-12:
            right_a = (1.0, 0.0, 0.0)
        if norm(right_b) <= 1e-12:
            right_b = (1.0, 0.0, 0.0)
        up_a = unit(cross(right_a, forward_a))
        up_b = unit(cross(right_b, forward_b))

        for sample_idx in range(surface_samples_per_point):
            theta = 2.0 * math.pi * sample_idx / surface_samples_per_point
            normal = (0.0, math.cos(theta), math.sin(theta))
            surfel = add(target, mul(normal, cable_radius_m))

            covered_by_a = False
            covered_by_b = False
            for camera, forward, right, up, flag in (
                (cam_a, forward_a, right_a, up_a, "a"),
                (cam_b, forward_b, right_b, up_b, "b"),
            ):
                camera_to_surfel = sub(surfel, camera)
                surfel_to_camera = sub(camera, surfel)
                distance = norm(camera_to_surfel)
                distance_ok = min_distance_m <= distance <= max_distance_m
                x_angle = angle_rad(dot(camera_to_surfel, right), dot(camera_to_surfel, forward))
                y_angle = angle_rad(dot(camera_to_surfel, up), dot(camera_to_surfel, forward))
                fov_ok = abs(x_angle) <= hfov / 2.0 and abs(y_angle) <= vfov / 2.0
                normal_ok = dot(normal, surfel_to_camera) > 0.0
                if distance_ok:
                    distance_ok_count += 1
                if fov_ok:
                    fov_ok_count += 1
                if normal_ok:
                    normal_ok_count += 1
                covered = distance_ok and fov_ok and normal_ok
                if flag == "a":
                    covered_by_a = covered
                else:
                    covered_by_b = covered
            total += 1
            if covered_by_a:
                side_a_covered += 1
            if covered_by_b:
                side_b_covered += 1
            if covered_by_a or covered_by_b:
                covered_union += 1
            if dot(normal, sub(cam_a, surfel)) > 0.0 or dot(normal, sub(cam_b, surfel)) > 0.0:
                visible_side_union += 1

    total_ratio = covered_union / total if total else 0.0
    visible_side_ratio = covered_union / visible_side_union if visible_side_union else 0.0
    side_a_ratio = side_a_covered / total if total else 0.0
    side_b_ratio = side_b_covered / total if total else 0.0
    distance_ratio = distance_ok_count / (total * 2) if total else 0.0
    fov_ratio = fov_ok_count / (total * 2) if total else 0.0
    normal_ratio = normal_ok_count / (total * 2) if total else 0.0
    group_ok = len(views.get("side_a", [])) > 0 and len(views.get("side_b", [])) > 0
    if group_ok:
        accepted_group_count += 1
    group_rows.append(
        {
            "group_id": group_id,
            "decision": "accepted_multiview_union_group" if group_ok else "rejected_multiview_union_group",
            "view_count": len(views),
            "pose_count": len(rows),
            "surface_samples": total,
            "side_a_covered_samples": side_a_covered,
            "side_b_covered_samples": side_b_covered,
            "union_covered_samples": covered_union,
            "visible_side_union_samples": visible_side_union,
            "distance_ok_ratio": distance_ratio,
            "fov_ok_ratio": fov_ratio,
            "normal_visible_ratio": normal_ratio,
            "total_surface_coverage_upper_bound_ratio": total_ratio,
            "visible_side_coverage_upper_bound_ratio": visible_side_ratio,
            "side_a_coverage_upper_bound_ratio": side_a_ratio,
            "side_b_coverage_upper_bound_ratio": side_b_ratio,
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
            "side_a_covered_samples",
            "side_b_covered_samples",
            "union_covered_samples",
            "visible_side_union_samples",
            "distance_ok_ratio",
            "fov_ok_ratio",
            "normal_visible_ratio",
            "total_surface_coverage_upper_bound_ratio",
            "visible_side_coverage_upper_bound_ratio",
            "side_a_coverage_upper_bound_ratio",
            "side_b_coverage_upper_bound_ratio",
        ],
    )
    writer.writeheader()
    writer.writerows(group_rows)

global_total_surface_ratio = min((r["total_surface_coverage_upper_bound_ratio"] for r in group_rows), default=0.0)
global_visible_side_ratio = min((r["visible_side_coverage_upper_bound_ratio"] for r in group_rows), default=0.0)
global_side_a_ratio = min((r["side_a_coverage_upper_bound_ratio"] for r in group_rows), default=0.0)
global_side_b_ratio = min((r["side_b_coverage_upper_bound_ratio"] for r in group_rows), default=0.0)
accepted = len(group_rows) >= min_groups and accepted_group_count >= min_groups
meets_total_surface_target = global_total_surface_ratio >= min_total_surface_ratio
meets_visible_side_target = global_visible_side_ratio >= min_visible_side_ratio
decision = "accepted_cable_multiview_surface_union_offline" if accepted else "rejected_cable_multiview_surface_union_offline"
reason = "multiview_union_characterized" if accepted else "multiview_union_characterization_failed"

print("scope=cable_multiview_surface_union_offline")
print(f"decision={decision}")
print(f"reason={reason}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print(f"multiview_csv={multiview_csv}")
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
print(f"global_min_side_a_coverage_upper_bound_ratio={global_side_a_ratio:.9f}")
print(f"global_min_side_b_coverage_upper_bound_ratio={global_side_b_ratio:.9f}")
print(f"meets_total_surface_target={str(meets_total_surface_target).lower()}")
print(f"meets_visible_side_target={str(meets_visible_side_target).lower()}")
print("occlusion_gate_implemented=false")
print("uses_real_camera_trajectory=false")
print("claims_active_control_approval=false")
print("claims_final_cable_inspection_coverage=false")
print(f"claims_multiview_surface_union_offline_pass={str(accepted).lower()}")
PY

echo "Cable multiview surface union offline audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Group CSV: ${GROUP_CSV}"

grep -q "decision=accepted_cable_multiview_surface_union_offline" "${SUMMARY_FILE}"
