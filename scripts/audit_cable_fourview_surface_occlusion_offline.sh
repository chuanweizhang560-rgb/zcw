#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

GEOMETRY_PYTHON="${GEOMETRY_PYTHON:-${ROOT_DIR}/.venv/geometry/bin/python}"
DEFAULT_FOURVIEW_CSV="$(find data/results -path '*cable_fourview_surface_candidate_offline_*/*.csv' 2>/dev/null | sort | tail -n 1 || true)"
DEFAULT_WORLD_PATH="third_party/aerialcore_simulation/worlds/power_towers_danube_wires_rescaled_autospawn.world"
DEFAULT_MESH_PATH="third_party/aerialcore_simulation/models/power_tower_danube_2towers_wires/meshes/power_tower_danube_2tower_and_wires.dae"
FOURVIEW_CSV="${FOURVIEW_CSV:-${DEFAULT_FOURVIEW_CSV}}"
WORLD_PATH="${WORLD_PATH:-${DEFAULT_WORLD_PATH}}"
MESH_PATH="${MESH_PATH:-${DEFAULT_MESH_PATH}}"
CABLE_RADIUS_M="${CABLE_RADIUS_M:-0.03}"
SURFACE_SAMPLES_PER_POINT="${SURFACE_SAMPLES_PER_POINT:-32}"
HFOV_DEG="${HFOV_DEG:-87.0}"
VFOV_DEG="${VFOV_DEG:-58.0}"
MIN_DISTANCE_M="${MIN_DISTANCE_M:-1.0}"
MAX_DISTANCE_M="${MAX_DISTANCE_M:-30.0}"
MIN_GROUPS="${MIN_GROUPS:-5}"
MIN_OCCLUSION_CLEAR_TOTAL_RATIO="${MIN_OCCLUSION_CLEAR_TOTAL_RATIO:-0.95}"
OCCLUSION_EPS_M="${OCCLUSION_EPS_M:-0.02}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-data/results}"
RESULT_DIR="${RESULT_ROOT}/cable_fourview_surface_occlusion_offline_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/cable_fourview_surface_occlusion_offline_${STAMP}.txt"
GROUP_CSV="${RESULT_DIR}/cable_fourview_surface_occlusion_offline_groups_${STAMP}.csv"

for file in "${GEOMETRY_PYTHON}" "${FOURVIEW_CSV}" "${WORLD_PATH}" "${MESH_PATH}"; do
  if [[ ! -e "${file}" ]]; then
    echo "Required input file does not exist: ${file}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

"${GEOMETRY_PYTHON}" - "${FOURVIEW_CSV}" "${WORLD_PATH}" "${MESH_PATH}" "${GROUP_CSV}" \
  "${CABLE_RADIUS_M}" "${SURFACE_SAMPLES_PER_POINT}" "${HFOV_DEG}" "${VFOV_DEG}" \
  "${MIN_DISTANCE_M}" "${MAX_DISTANCE_M}" "${MIN_GROUPS}" "${MIN_OCCLUSION_CLEAR_TOTAL_RATIO}" \
  "${OCCLUSION_EPS_M}" >"${SUMMARY_FILE}" <<'PY'
import csv
import math
import re
import sys
from collections import defaultdict

import numpy as np
import trimesh

(
    fourview_csv,
    world_path,
    mesh_path,
    group_csv,
    cable_radius_m,
    surface_samples_per_point,
    hfov_deg,
    vfov_deg,
    min_distance_m,
    max_distance_m,
    min_groups,
    min_occlusion_clear_total_ratio,
    occlusion_eps_m,
) = sys.argv[1:14]
cable_radius_m = float(cable_radius_m)
surface_samples_per_point = int(surface_samples_per_point)
hfov_deg = float(hfov_deg)
vfov_deg = float(vfov_deg)
min_distance_m = float(min_distance_m)
max_distance_m = float(max_distance_m)
min_groups = int(min_groups)
min_occlusion_clear_total_ratio = float(min_occlusion_clear_total_ratio)
occlusion_eps_m = float(occlusion_eps_m)


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


def load_world_model_pose(path):
    text = open(path, "r", encoding="utf-8").read()
    match = re.search(r"<model name='power_tower_danube'>.*?<pose>([^<]+)</pose>", text, re.S)
    if not match:
        raise SystemExit("power_tower_danube pose not found in world")
    values = [float(v) for v in match.group(1).split()]
    if len(values) != 6:
        raise SystemExit("power_tower_danube pose must contain 6 values")
    return values


def load_occlusion_mesh(path, world_pose):
    mesh = trimesh.load(path, force="mesh")
    if mesh.is_empty or len(mesh.faces) == 0:
        raise SystemExit("occlusion mesh is empty")
    yaw = world_pose[5]
    transform = np.eye(4)
    transform[:3, :3] = trimesh.transformations.rotation_matrix(yaw, [0, 0, 1])[:3, :3]
    transform[:3, 3] = [world_pose[0], world_pose[1], world_pose[2]]
    scale = np.eye(4)
    scale[2, 2] = 0.5
    mesh.apply_transform(transform @ scale)
    mesh.remove_unreferenced_vertices()
    return mesh


world_pose = load_world_model_pose(world_path)
mesh = load_occlusion_mesh(mesh_path, world_pose)

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
ray_tests = 0
ray_clear = 0

for group_id in sorted(groups):
    by_index = defaultdict(list)
    view_names = set()
    for row in groups[group_id]:
        by_index[row["index"]].append(row)
        view_names.add(row["view_name"])
    total = 0
    union_covered = 0
    occlusion_clear_union = 0
    blocked_union = 0
    for index in sorted(by_index):
        rows = by_index[index]
        target = (rows[0]["target_x"], rows[0]["target_y"], rows[0]["target_z"])
        for sample_idx in range(surface_samples_per_point):
            theta = 2.0 * math.pi * sample_idx / surface_samples_per_point
            normal = (0.0, math.cos(theta), math.sin(theta))
            surfel = add(target, mul(normal, cable_radius_m))
            covered_any = False
            clear_any = False
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
                if not (distance_ok and fov_ok and normal_ok):
                    continue
                covered_any = True
                origin = np.array(camera, dtype=float)
                target_np = np.array(surfel, dtype=float)
                ray_vec = target_np - origin
                target_distance = float(np.linalg.norm(ray_vec))
                if target_distance <= 1e-12:
                    continue
                direction = ray_vec / target_distance
                loc, ray_idx, _tri_idx = mesh.ray.intersects_location(
                    origin.reshape(1, 3),
                    direction.reshape(1, 3),
                    multiple_hits=False,
                )
                ray_tests += 1
                clear = True
                if len(ray_idx) > 0:
                    hit_distance = float(np.linalg.norm(loc[0] - origin))
                    if hit_distance < target_distance - occlusion_eps_m:
                        clear = False
                if clear:
                    clear_any = True
                    ray_clear += 1
            total += 1
            if covered_any:
                union_covered += 1
            if clear_any:
                occlusion_clear_union += 1
            elif covered_any:
                blocked_union += 1
    total_ratio = union_covered / total if total else 0.0
    occlusion_ratio = occlusion_clear_union / total if total else 0.0
    blocked_ratio = blocked_union / total if total else 0.0
    group_ok = len(view_names) >= 4 and occlusion_ratio >= min_occlusion_clear_total_ratio
    if group_ok:
        accepted_group_count += 1
    group_rows.append(
        {
            "group_id": group_id,
            "decision": "accepted_fourview_occlusion_group" if group_ok else "rejected_fourview_occlusion_group",
            "view_count": len(view_names),
            "surface_samples": total,
            "union_covered_samples": union_covered,
            "occlusion_clear_union_samples": occlusion_clear_union,
            "blocked_union_samples": blocked_union,
            "total_surface_coverage_upper_bound_ratio": total_ratio,
            "occlusion_clear_total_surface_ratio": occlusion_ratio,
            "blocked_union_ratio": blocked_ratio,
        }
    )

with open(group_csv, "w", newline="") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=[
            "group_id",
            "decision",
            "view_count",
            "surface_samples",
            "union_covered_samples",
            "occlusion_clear_union_samples",
            "blocked_union_samples",
            "total_surface_coverage_upper_bound_ratio",
            "occlusion_clear_total_surface_ratio",
            "blocked_union_ratio",
        ],
    )
    writer.writeheader()
    writer.writerows(group_rows)

global_min_occlusion = min((r["occlusion_clear_total_surface_ratio"] for r in group_rows), default=0.0)
global_max_blocked = max((r["blocked_union_ratio"] for r in group_rows), default=0.0)
accepted = len(group_rows) >= min_groups and accepted_group_count >= min_groups
decision = "accepted_cable_fourview_surface_occlusion_offline" if accepted else "rejected_cable_fourview_surface_occlusion_offline"
reason = "fourview_occlusion_clearance_characterized" if accepted else "fourview_occlusion_clearance_failed"

print("scope=cable_fourview_surface_occlusion_offline")
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
print(f"world_path={world_path}")
print(f"mesh_path={mesh_path}")
print(f"group_csv={group_csv}")
print("uses_trimesh=true")
print("uses_rtree=true")
print("uses_real_aerialcore_collision_mesh=true")
print(f"surface_samples_per_point={surface_samples_per_point}")
print(f"min_occlusion_clear_total_ratio={min_occlusion_clear_total_ratio:.9f}")
print(f"group_count={len(group_rows)}")
print(f"accepted_group_count={accepted_group_count}")
print(f"ray_tests={ray_tests}")
print(f"ray_clear={ray_clear}")
print(f"global_min_occlusion_clear_total_surface_ratio={global_min_occlusion:.9f}")
print(f"global_max_blocked_union_ratio={global_max_blocked:.9f}")
print("claims_active_control_approval=false")
print("claims_final_cable_inspection_coverage=false")
print(f"claims_fourview_surface_occlusion_offline_pass={str(accepted).lower()}")
PY

echo "Cable four-view surface occlusion offline audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Group CSV: ${GROUP_CSV}"

grep -q "decision=accepted_cable_fourview_surface_occlusion_offline" "${SUMMARY_FILE}"
