#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${OUTPUT_DIR:-${RESULT_ROOT}/wind_occlusion_coverage_progression_${STAMP}}"
SUMMARY_FILE="${RESULT_DIR}/wind_occlusion_coverage_progression_${STAMP}.txt"
PROGRESSION_CSV="${RESULT_DIR}/wind_occlusion_coverage_progression_${STAMP}.csv"
BAND_CSV="${RESULT_DIR}/wind_occlusion_coverage_progression_bands_${STAMP}.csv"

GEOMETRY_PYTHON="${GEOMETRY_PYTHON:-${ROOT_DIR}/.venv/geometry/bin/python}"
POSE_CSV="${POSE_CSV:-}"
if [[ -z "${POSE_CSV}" ]]; then
  POSE_CSV="$(find data/results -path '*wind_dynamic_orbit_audit_*' -type f -name 'wind_dynamic_orbit_pose_*.csv' | sort | tail -n 1)"
fi
MESH_PATH="${MESH_PATH:-third_party/aerialcore_simulation/models/wind_turbine/wind_turbine_scaled.dae}"
WORLD_PATH="${WORLD_PATH:-third_party/aerialcore_simulation/worlds/wind_turbine_autospawn.world}"
CAMERA_HFOV_RAD="${CAMERA_HFOV_RAD:-1.5009831567}"
CAMERA_WIDTH="${CAMERA_WIDTH:-848}"
CAMERA_HEIGHT="${CAMERA_HEIGHT:-480}"
CAMERA_MIN_DEPTH_M="${CAMERA_MIN_DEPTH_M:-0.2}"
CAMERA_MAX_DEPTH_M="${CAMERA_MAX_DEPTH_M:-65.535}"
TURBINE_CENTER_X="${TURBINE_CENTER_X:--25.0}"
TURBINE_CENTER_Y="${TURBINE_CENTER_Y:--25.0}"
TURBINE_CENTER_Z="${TURBINE_CENTER_Z:-0.0}"
MAX_VIEW_ANGLE_DEG="${MAX_VIEW_ANGLE_DEG:-75.0}"
MIN_FINAL_OCCLUDED_NORMAL_COVERAGE_RATIO="${MIN_FINAL_OCCLUDED_NORMAL_COVERAGE_RATIO:-0.25}"
Z_BAND_COUNT="${Z_BAND_COUNT:-4}"
POSE_STRIDE="${POSE_STRIDE:-20}"
FACE_STRIDE="${FACE_STRIDE:-8}"
RAY_CHUNK_SIZE="${RAY_CHUNK_SIZE:-5000}"
OCCLUSION_EPS_M="${OCCLUSION_EPS_M:-0.05}"

for path in "${GEOMETRY_PYTHON}" "${POSE_CSV}" "${MESH_PATH}" "${WORLD_PATH}"; do
  if [[ -z "${path}" || ! -e "${path}" ]]; then
    echo "Required input missing: ${path}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

"${GEOMETRY_PYTHON}" - "$POSE_CSV" "$WORLD_PATH" "$MESH_PATH" "$PROGRESSION_CSV" "$BAND_CSV" \
  "$CAMERA_HFOV_RAD" "$CAMERA_WIDTH" "$CAMERA_HEIGHT" "$CAMERA_MIN_DEPTH_M" "$CAMERA_MAX_DEPTH_M" \
  "$TURBINE_CENTER_X" "$TURBINE_CENTER_Y" "$TURBINE_CENTER_Z" "$MAX_VIEW_ANGLE_DEG" \
  "$MIN_FINAL_OCCLUDED_NORMAL_COVERAGE_RATIO" "$Z_BAND_COUNT" "$POSE_STRIDE" "$FACE_STRIDE" \
  "$RAY_CHUNK_SIZE" "$OCCLUSION_EPS_M" >"${SUMMARY_FILE}" <<'PY'
import csv
import math
import re
import sys

import numpy as np
import trimesh

(
    pose_csv,
    world_path,
    mesh_path,
    progression_csv,
    band_csv,
) = sys.argv[1:6]
hfov = float(sys.argv[6])
camera_width = int(sys.argv[7])
camera_height = int(sys.argv[8])
min_depth = float(sys.argv[9])
max_depth = float(sys.argv[10])
cx = float(sys.argv[11])
cy = float(sys.argv[12])
cz = float(sys.argv[13])
max_view_angle_deg = float(sys.argv[14])
min_final_occluded_normal_coverage_ratio = float(sys.argv[15])
z_band_count = int(sys.argv[16])
pose_stride = max(1, int(sys.argv[17]))
face_stride = max(1, int(sys.argv[18]))
ray_chunk_size = max(1, int(sys.argv[19]))
occlusion_eps_m = float(sys.argv[20])

world_text = open(world_path, "r", encoding="utf-8").read()
pose_match = re.search(r"<model name='wind_turbine'>.*?<pose>([^<]+)</pose>", world_text, re.S)
if not pose_match:
    raise SystemExit("wind turbine pose not found in world")
world_pose = [float(v) for v in pose_match.group(1).split()]
world_yaw = world_pose[5]

mesh = trimesh.load(mesh_path, force="mesh")
if mesh.is_empty or len(mesh.faces) == 0:
    raise SystemExit("wind turbine mesh is empty")
transform = np.eye(4)
transform[:3, :3] = trimesh.transformations.rotation_matrix(world_yaw, [0, 0, 1])[:3, :3]
transform[:3, 3] = [world_pose[0], world_pose[1], world_pose[2]]
mesh.apply_transform(transform)
mesh.remove_unreferenced_vertices()

face_indices = np.arange(0, len(mesh.faces), face_stride, dtype=np.int64)
samples = mesh.triangles_center[face_indices]
normals = mesh.face_normals[face_indices]
sample_count = len(samples)
if sample_count == 0:
    raise SystemExit("no mesh samples after FACE_STRIDE")

poses = []
with open(pose_csv, "r", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for idx, row in enumerate(reader):
        if idx % pose_stride != 0:
            continue
        if row.get("xy_valid") != "true" or row.get("z_valid") != "true":
            continue
        poses.append((float(row["t_sec"]), float(row["x"]), float(row["y"]), float(row["z"])))
if not poses:
    raise SystemExit("no valid pose samples found")

vfov = 2.0 * math.atan(math.tan(hfov / 2.0) * (camera_height / camera_width))
half_hfov = hfov / 2.0
half_vfov = vfov / 2.0
cos_max_view_angle = math.cos(math.radians(max_view_angle_deg))
look_at = np.array([cx, cy, cz], dtype=float)

def camera_basis(cam_pos):
    forward = look_at - cam_pos
    norm = np.linalg.norm(forward)
    if norm <= 1e-9:
        return None
    forward = forward / norm
    world_up = np.array([0.0, 0.0, 1.0])
    right = np.cross(forward, world_up)
    right_norm = np.linalg.norm(right)
    if right_norm <= 1e-9:
        return None
    right = right / right_norm
    up = np.cross(right, forward)
    return forward, right, up

frustum_seen = np.zeros(sample_count, dtype=bool)
normal_seen = np.zeros(sample_count, dtype=bool)
occluded_normal_seen = np.zeros(sample_count, dtype=bool)
progress_rows = []
ray_tests = 0
ray_clear = 0

for pose_index, (t_sec, x, y, z) in enumerate(poses):
    cam_pos = np.array([x, y, z], dtype=float)
    basis = camera_basis(cam_pos)
    pose_frustum_hits = 0
    pose_normal_hits = 0
    pose_occluded_normal_hits = 0
    if basis is not None:
        forward, right, up = basis
        vectors = samples - cam_pos
        distances = np.linalg.norm(vectors, axis=1)
        valid_distance = (distances >= min_depth) & (distances <= max_depth)
        x_cam = vectors @ forward
        y_cam = vectors @ right
        z_cam = vectors @ up
        in_front = x_cam > 0.0
        horizontal = np.abs(np.arctan2(y_cam, x_cam))
        vertical = np.abs(np.arctan2(z_cam, x_cam))
        in_frustum = valid_distance & in_front & (horizontal <= half_hfov) & (vertical <= half_vfov)
        pose_frustum_hits = int(in_frustum.sum())
        frustum_seen |= in_frustum

        to_cam = cam_pos - samples
        to_cam_norm = np.linalg.norm(to_cam, axis=1)
        safe_norm = np.maximum(to_cam_norm, 1e-9)
        dots = np.einsum("ij,ij->i", normals, to_cam / safe_norm[:, None])
        normal_ok = in_frustum & (dots >= cos_max_view_angle)
        pose_normal_hits = int(normal_ok.sum())
        normal_seen |= normal_ok

        candidate_indices = np.flatnonzero(normal_ok)
        occlusion_ok = np.zeros(sample_count, dtype=bool)
        for start in range(0, len(candidate_indices), ray_chunk_size):
            chunk_indices = candidate_indices[start:start + ray_chunk_size]
            targets = samples[chunk_indices]
            ray_vectors = targets - cam_pos
            target_distances = np.linalg.norm(ray_vectors, axis=1)
            directions = ray_vectors / np.maximum(target_distances, 1e-9)[:, None]
            origins = np.repeat(cam_pos[None, :], len(chunk_indices), axis=0)
            loc, ray_idx, _tri_idx = mesh.ray.intersects_location(
                origins,
                directions,
                multiple_hits=False,
            )
            ray_tests += len(chunk_indices)
            clear_chunk = np.ones(len(chunk_indices), dtype=bool)
            if len(ray_idx) > 0:
                hit_distances = np.linalg.norm(loc - origins[ray_idx], axis=1)
                for local_ray, hit_distance in zip(ray_idx, hit_distances):
                    if hit_distance < target_distances[local_ray] - occlusion_eps_m:
                        clear_chunk[local_ray] = False
            ray_clear += int(clear_chunk.sum())
            occlusion_ok[chunk_indices] = clear_chunk
        pose_occluded_normal_hits = int(occlusion_ok.sum())
        occluded_normal_seen |= occlusion_ok

    cumulative_frustum = int(frustum_seen.sum())
    cumulative_normal = int(normal_seen.sum())
    cumulative_occluded = int(occluded_normal_seen.sum())
    progress_rows.append((
        pose_index, t_sec, x, y, z, pose_frustum_hits, pose_normal_hits, pose_occluded_normal_hits,
        cumulative_frustum, cumulative_normal, cumulative_occluded,
        cumulative_frustum / sample_count,
        cumulative_normal / sample_count,
        cumulative_occluded / sample_count,
    ))

with open(progression_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow([
        "pose_index", "t_sec", "x", "y", "z", "pose_frustum_hits", "pose_normal_hits",
        "pose_occlusion_clear_normal_hits", "cumulative_frustum_samples",
        "cumulative_normal_samples", "cumulative_occlusion_clear_normal_samples",
        "cumulative_frustum_ratio", "cumulative_normal_ratio", "cumulative_occlusion_clear_normal_ratio",
    ])
    for row in progress_rows:
        writer.writerow([
            row[0], f"{row[1]:.6f}", f"{row[2]:.6f}", f"{row[3]:.6f}", f"{row[4]:.6f}",
            row[5], row[6], row[7], row[8], row[9], row[10],
            f"{row[11]:.6f}", f"{row[12]:.6f}", f"{row[13]:.6f}",
        ])

z_min = float(samples[:, 2].min())
z_max = float(samples[:, 2].max())
band_rows = []
min_band_occluded = 1.0
for band in range(max(1, z_band_count)):
    lower = z_min + (z_max - z_min) * band / max(1, z_band_count)
    upper = z_min + (z_max - z_min) * (band + 1) / max(1, z_band_count)
    in_band = (samples[:, 2] >= lower) & ((samples[:, 2] < upper) | (band == z_band_count - 1))
    count = int(in_band.sum())
    frustum_count = int((frustum_seen & in_band).sum())
    normal_count = int((normal_seen & in_band).sum())
    occluded_count = int((occluded_normal_seen & in_band).sum())
    frustum_ratio = frustum_count / count if count else 0.0
    normal_ratio = normal_count / count if count else 0.0
    occluded_ratio = occluded_count / count if count else 0.0
    min_band_occluded = min(min_band_occluded, occluded_ratio)
    band_rows.append((band, lower, upper, count, frustum_count, frustum_ratio, normal_count, normal_ratio, occluded_count, occluded_ratio))

with open(band_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow([
        "band", "z_min", "z_max", "sample_count", "frustum_covered_count", "frustum_covered_ratio",
        "normal_covered_count", "normal_covered_ratio", "occlusion_clear_normal_count",
        "occlusion_clear_normal_ratio",
    ])
    for row in band_rows:
        writer.writerow([row[0], f"{row[1]:.6f}", f"{row[2]:.6f}", row[3], row[4], f"{row[5]:.6f}", row[6], f"{row[7]:.6f}", row[8], f"{row[9]:.6f}"])

final_frustum_ratio = progress_rows[-1][11]
final_normal_ratio = progress_rows[-1][12]
final_occluded_ratio = progress_rows[-1][13]
accepted = final_occluded_ratio >= min_final_occluded_normal_coverage_ratio

print("scope=wind_occlusion_coverage_progression_static_audit")
print(f"decision={'accepted_wind_occlusion_coverage_progression_static_audit' if accepted else 'rejected_wind_occlusion_coverage_progression_static_audit'}")
print(f"reason={'trimesh_ray_occlusion_clear_coverage_above_threshold' if accepted else 'trimesh_ray_occlusion_clear_coverage_below_threshold'}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print("uses_trimesh=true")
print("uses_rtree=true")
print(f"pose_csv={pose_csv}")
print(f"world_path={world_path}")
print(f"mesh_path={mesh_path}")
print("coverage_model=dynamic_pose_mesh_triangle_centroid_frustum_normal_trimesh_ray_no_image_defect_detection")
print("claims_final_coverage=false")
print(f"pose_stride={pose_stride}")
print(f"face_stride={face_stride}")
print(f"pose_samples_used={len(poses)}")
print(f"mesh_faces={len(mesh.faces)}")
print(f"mesh_samples={sample_count}")
print(f"ray_tests={ray_tests}")
print(f"ray_clear={ray_clear}")
print(f"final_frustum_coverage_ratio={final_frustum_ratio:.6f}")
print(f"final_normal_filtered_coverage_ratio={final_normal_ratio:.6f}")
print(f"final_occlusion_clear_normal_coverage_ratio={final_occluded_ratio:.6f}")
print(f"min_band_occlusion_clear_normal_ratio_observed={min_band_occluded:.6f}")
print(f"min_final_occluded_normal_coverage_ratio={min_final_occluded_normal_coverage_ratio:.6f}")
print(f"progression_csv={progression_csv}")
print(f"band_csv={band_csv}")
if not accepted:
    raise SystemExit(2)
PY

grep -q '^decision=accepted_wind_occlusion_coverage_progression_static_audit$' "${SUMMARY_FILE}"

echo "Wind occlusion coverage progression audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Progression CSV: ${PROGRESSION_CSV}"
echo "Band CSV: ${BAND_CSV}"
