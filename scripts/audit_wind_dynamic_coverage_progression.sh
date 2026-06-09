#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${OUTPUT_DIR:-${RESULT_ROOT}/wind_dynamic_coverage_progression_${STAMP}}"
SUMMARY_FILE="${RESULT_DIR}/wind_dynamic_coverage_progression_${STAMP}.txt"
PROGRESSION_CSV="${RESULT_DIR}/wind_dynamic_coverage_progression_${STAMP}.csv"
BAND_CSV="${RESULT_DIR}/wind_dynamic_coverage_progression_bands_${STAMP}.csv"

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
MIN_FINAL_NORMAL_COVERAGE_RATIO="${MIN_FINAL_NORMAL_COVERAGE_RATIO:-0.35}"
Z_BAND_COUNT="${Z_BAND_COUNT:-4}"
POSE_STRIDE="${POSE_STRIDE:-1}"

for path in "${POSE_CSV}" "${MESH_PATH}" "${WORLD_PATH}"; do
  if [[ -z "${path}" || ! -f "${path}" ]]; then
    echo "Required input missing: ${path}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

python3 - "$POSE_CSV" "$WORLD_PATH" "$MESH_PATH" "$PROGRESSION_CSV" "$BAND_CSV" \
  "$CAMERA_HFOV_RAD" "$CAMERA_WIDTH" "$CAMERA_HEIGHT" "$CAMERA_MIN_DEPTH_M" "$CAMERA_MAX_DEPTH_M" \
  "$TURBINE_CENTER_X" "$TURBINE_CENTER_Y" "$TURBINE_CENTER_Z" "$MAX_VIEW_ANGLE_DEG" \
  "$MIN_FINAL_NORMAL_COVERAGE_RATIO" "$Z_BAND_COUNT" "$POSE_STRIDE" >"${SUMMARY_FILE}" <<'PY'
import csv
import math
import re
import sys
import xml.etree.ElementTree as ET

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
min_final_normal_coverage_ratio = float(sys.argv[15])
z_band_count = int(sys.argv[16])
pose_stride = max(1, int(sys.argv[17]))

world_text = open(world_path, "r", encoding="utf-8").read()
pose_match = re.search(r"<model name='wind_turbine'>.*?<pose>([^<]+)</pose>", world_text, re.S)
if not pose_match:
    raise SystemExit("wind turbine pose not found in world")
world_pose = [float(v) for v in pose_match.group(1).split()]
world_yaw = world_pose[5]
cos_y = math.cos(world_yaw)
sin_y = math.sin(world_yaw)

tree = ET.parse(mesh_path)
root = tree.getroot()
ns = {"c": "http://www.collada.org/2005/11/COLLADASchema"}

def parse_float_source(source_id):
    node = root.find(f".//c:source[@id='{source_id}']/c:float_array", ns)
    if node is None or not node.text:
        raise SystemExit(f"DAE float_array not found: {source_id}")
    values = [float(x) for x in node.text.split()]
    if len(values) % 3 != 0:
        raise SystemExit(f"DAE float_array count is not divisible by 3: {source_id}")
    return [tuple(values[i:i + 3]) for i in range(0, len(values), 3)]

positions = parse_float_source("shape0-lib-positions")
normals = parse_float_source("shape0-lib-normals")
triangles = root.find(".//c:triangles", ns)
if triangles is None:
    raise SystemExit("DAE triangles not found")
inputs = []
for item in triangles.findall("c:input", ns):
    inputs.append((item.attrib.get("semantic"), item.attrib.get("source", "").lstrip("#"), int(item.attrib.get("offset", "0"))))
stride = max(offset for _, _, offset in inputs) + 1
vertex_offset = next((offset for semantic, _, offset in inputs if semantic == "VERTEX"), None)
normal_offset = next((offset for semantic, _, offset in inputs if semantic == "NORMAL"), None)
if vertex_offset is None or normal_offset is None:
    raise SystemExit("DAE triangles must provide VERTEX and NORMAL inputs")
p_node = triangles.find("c:p", ns)
if p_node is None or not p_node.text:
    raise SystemExit("DAE triangles p data not found")
indices = [int(x) for x in p_node.text.split()]

def transform_position(point):
    x, y, z = point
    xr = x * cos_y - y * sin_y
    yr = x * sin_y + y * cos_y
    return (world_pose[0] + xr, world_pose[1] + yr, world_pose[2] + z)

def transform_normal(normal):
    x, y, z = normal
    xr = x * cos_y - y * sin_y
    yr = x * sin_y + y * cos_y
    norm = math.sqrt(xr * xr + yr * yr + z * z)
    if norm <= 1e-9:
        return (0.0, 0.0, 0.0)
    return (xr / norm, yr / norm, z / norm)

samples = []
for base in range(0, len(indices), 3 * stride):
    tri_points = []
    tri_normals = []
    for corner in range(3):
        start = base + corner * stride
        tri_points.append(transform_position(positions[indices[start + vertex_offset]]))
        tri_normals.append(transform_normal(normals[indices[start + normal_offset]]))
    centroid = tuple(sum(p[i] for p in tri_points) / 3.0 for i in range(3))
    normal = tuple(sum(n[i] for n in tri_normals) / 3.0 for i in range(3))
    norm = math.sqrt(sum(v * v for v in normal))
    if norm > 1e-9:
        normal = tuple(v / norm for v in normal)
    samples.append((centroid, normal))

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
look_at = (cx, cy, cz)

def camera_basis(cam_pos):
    fx = look_at[0] - cam_pos[0]
    fy = look_at[1] - cam_pos[1]
    fz = look_at[2] - cam_pos[2]
    norm = math.sqrt(fx * fx + fy * fy + fz * fz)
    if norm <= 1e-9:
        return None
    forward = (fx / norm, fy / norm, fz / norm)
    world_up = (0.0, 0.0, 1.0)
    right = (
        forward[1] * world_up[2] - forward[2] * world_up[1],
        forward[2] * world_up[0] - forward[0] * world_up[2],
        forward[0] * world_up[1] - forward[1] * world_up[0],
    )
    right_norm = math.sqrt(sum(v * v for v in right))
    if right_norm <= 1e-9:
        return None
    right = tuple(v / right_norm for v in right)
    up = (
        right[1] * forward[2] - right[2] * forward[1],
        right[2] * forward[0] - right[0] * forward[2],
        right[0] * forward[1] - right[1] * forward[0],
    )
    return forward, right, up

def visible(sample, cam_pos, basis):
    point, normal = sample
    vx = point[0] - cam_pos[0]
    vy = point[1] - cam_pos[1]
    vz = point[2] - cam_pos[2]
    dist = math.sqrt(vx * vx + vy * vy + vz * vz)
    if dist < min_depth or dist > max_depth:
        return False, False
    forward, right, up = basis
    x_cam = vx * forward[0] + vy * forward[1] + vz * forward[2]
    if x_cam <= 0.0:
        return False, False
    y_cam = vx * right[0] + vy * right[1] + vz * right[2]
    z_cam = vx * up[0] + vy * up[1] + vz * up[2]
    in_frustum = abs(math.atan2(y_cam, x_cam)) <= half_hfov and abs(math.atan2(z_cam, x_cam)) <= half_vfov
    if not in_frustum:
        return False, False
    to_cam = (cam_pos[0] - point[0], cam_pos[1] - point[1], cam_pos[2] - point[2])
    to_cam_norm = math.sqrt(sum(v * v for v in to_cam))
    dot = -1.0 if to_cam_norm <= 1e-9 else sum(normal[i] * to_cam[i] / to_cam_norm for i in range(3))
    return True, dot >= cos_max_view_angle

frustum_seen = [False] * len(samples)
normal_seen = [False] * len(samples)
progress_rows = []
for pose_index, (t_sec, x, y, z) in enumerate(poses):
    cam_pos = (x, y, z)
    basis = camera_basis(cam_pos)
    pose_frustum_hits = 0
    pose_normal_hits = 0
    if basis is not None:
        for sample_index, sample in enumerate(samples):
            in_frustum, normal_ok = visible(sample, cam_pos, basis)
            if in_frustum:
                pose_frustum_hits += 1
                frustum_seen[sample_index] = True
            if normal_ok:
                pose_normal_hits += 1
                normal_seen[sample_index] = True
    cumulative_frustum = sum(1 for value in frustum_seen if value)
    cumulative_normal = sum(1 for value in normal_seen if value)
    progress_rows.append((
        pose_index, t_sec, x, y, z, pose_frustum_hits, pose_normal_hits,
        cumulative_frustum, cumulative_normal,
        cumulative_frustum / len(samples), cumulative_normal / len(samples),
    ))

with open(progression_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow([
        "pose_index", "t_sec", "x", "y", "z", "pose_frustum_hits", "pose_normal_hits",
        "cumulative_frustum_samples", "cumulative_normal_samples",
        "cumulative_frustum_ratio", "cumulative_normal_ratio",
    ])
    for row in progress_rows:
        writer.writerow([row[0], f"{row[1]:.6f}", f"{row[2]:.6f}", f"{row[3]:.6f}", f"{row[4]:.6f}", row[5], row[6], row[7], row[8], f"{row[9]:.6f}", f"{row[10]:.6f}"])

z_min = min(sample[0][2] for sample in samples)
z_max = max(sample[0][2] for sample in samples)
band_rows = []
min_band_normal = 1.0
for band in range(max(1, z_band_count)):
    lower = z_min + (z_max - z_min) * band / max(1, z_band_count)
    upper = z_min + (z_max - z_min) * (band + 1) / max(1, z_band_count)
    indices_in_band = [
        i for i, sample in enumerate(samples)
        if sample[0][2] >= lower and (sample[0][2] < upper or band == z_band_count - 1)
    ]
    frustum_count = sum(1 for i in indices_in_band if frustum_seen[i])
    normal_count = sum(1 for i in indices_in_band if normal_seen[i])
    frustum_ratio = frustum_count / len(indices_in_band) if indices_in_band else 0.0
    normal_ratio = normal_count / len(indices_in_band) if indices_in_band else 0.0
    min_band_normal = min(min_band_normal, normal_ratio)
    band_rows.append((band, lower, upper, len(indices_in_band), frustum_count, frustum_ratio, normal_count, normal_ratio))

with open(band_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["band", "z_min", "z_max", "sample_count", "frustum_covered_count", "frustum_covered_ratio", "normal_covered_count", "normal_covered_ratio"])
    for row in band_rows:
        writer.writerow([row[0], f"{row[1]:.6f}", f"{row[2]:.6f}", row[3], row[4], f"{row[5]:.6f}", row[6], f"{row[7]:.6f}"])

final_frustum_ratio = progress_rows[-1][9]
final_normal_ratio = progress_rows[-1][10]
accepted = final_normal_ratio >= min_final_normal_coverage_ratio

print("scope=wind_dynamic_coverage_progression_static_audit")
print(f"decision={'accepted_wind_dynamic_coverage_progression_static_audit' if accepted else 'rejected_wind_dynamic_coverage_progression_static_audit'}")
print(f"reason={'dynamic_pose_samples_cover_sufficient_normal_filtered_mesh_samples' if accepted else 'dynamic_pose_samples_below_normal_filtered_coverage_threshold'}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print(f"pose_csv={pose_csv}")
print(f"world_path={world_path}")
print(f"mesh_path={mesh_path}")
print("coverage_model=dynamic_pose_mesh_triangle_centroid_frustum_normal_no_occlusion")
print("claims_final_coverage=false")
print(f"pose_stride={pose_stride}")
print(f"pose_samples_used={len(poses)}")
print(f"mesh_samples={len(samples)}")
print(f"final_frustum_coverage_ratio={final_frustum_ratio:.6f}")
print(f"final_normal_filtered_coverage_ratio={final_normal_ratio:.6f}")
print(f"min_band_normal_coverage_ratio_observed={min_band_normal:.6f}")
print(f"min_final_normal_coverage_ratio={min_final_normal_coverage_ratio:.6f}")
print(f"progression_csv={progression_csv}")
print(f"band_csv={band_csv}")
if not accepted:
    raise SystemExit(2)
PY

grep -q '^decision=accepted_wind_dynamic_coverage_progression_static_audit$' "${SUMMARY_FILE}"

echo "Wind dynamic coverage progression audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Progression CSV: ${PROGRESSION_CSV}"
echo "Band CSV: ${BAND_CSV}"
