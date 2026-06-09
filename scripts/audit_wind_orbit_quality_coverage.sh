#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${OUTPUT_DIR:-${RESULT_ROOT}/wind_orbit_quality_coverage_${STAMP}}"
SUMMARY_FILE="${RESULT_DIR}/wind_orbit_quality_coverage_${STAMP}.txt"
SAMPLE_CSV="${RESULT_DIR}/wind_orbit_quality_coverage_samples_${STAMP}.csv"
BAND_CSV="${RESULT_DIR}/wind_orbit_quality_coverage_bands_${STAMP}.csv"
VIEW_CSV="${RESULT_DIR}/wind_orbit_quality_coverage_views_${STAMP}.csv"

LAUNCH_PATH="${LAUNCH_PATH:-ros2_ws/src/zcw_bringup/launch/single_vehicle_wind_turbine_multilevel_orbit.launch.py}"
WORLD_PATH="${WORLD_PATH:-third_party/aerialcore_simulation/worlds/wind_turbine_autospawn.world}"
MESH_PATH="${MESH_PATH:-third_party/aerialcore_simulation/models/wind_turbine/wind_turbine_scaled.dae}"
DEPTH_STATS_SUMMARY="${DEPTH_STATS_SUMMARY:-}"
CAMERA_HFOV_RAD="${CAMERA_HFOV_RAD:-1.5009831567}"
CAMERA_WIDTH="${CAMERA_WIDTH:-848}"
CAMERA_HEIGHT="${CAMERA_HEIGHT:-480}"
CAMERA_MIN_DEPTH_M="${CAMERA_MIN_DEPTH_M:-0.2}"
CAMERA_MAX_DEPTH_M="${CAMERA_MAX_DEPTH_M:-65.535}"
CAMERA_FORWARD_OFFSET_M="${CAMERA_FORWARD_OFFSET_M:-0.1}"
TURBINE_CENTER_X="${TURBINE_CENTER_X:--25.0}"
TURBINE_CENTER_Y="${TURBINE_CENTER_Y:--25.0}"
TURBINE_CENTER_Z="${TURBINE_CENTER_Z:-0.0}"
MAX_VIEW_ANGLE_DEG="${MAX_VIEW_ANGLE_DEG:-75.0}"
MIN_MEAN_USEFUL_RATIO="${MIN_MEAN_USEFUL_RATIO:-0.001}"
MIN_ANY_USEFUL_RATIO="${MIN_ANY_USEFUL_RATIO:-0.01}"
MIN_NORMAL_FILTERED_COVERAGE_RATIO="${MIN_NORMAL_FILTERED_COVERAGE_RATIO:-0.50}"
Z_BAND_COUNT="${Z_BAND_COUNT:-4}"

for path in "${LAUNCH_PATH}" "${WORLD_PATH}" "${MESH_PATH}"; do
  if [[ ! -f "${path}" ]]; then
    echo "Required input missing: ${path}" >&2
    exit 1
  fi
done

if [[ -n "${DEPTH_STATS_SUMMARY}" && ! -f "${DEPTH_STATS_SUMMARY}" ]]; then
  echo "DEPTH_STATS_SUMMARY not found: ${DEPTH_STATS_SUMMARY}" >&2
  exit 1
fi

mkdir -p "${RESULT_DIR}"

python3 - "$LAUNCH_PATH" "$WORLD_PATH" "$MESH_PATH" "$DEPTH_STATS_SUMMARY" \
  "$SAMPLE_CSV" "$BAND_CSV" "$VIEW_CSV" "$CAMERA_HFOV_RAD" "$CAMERA_WIDTH" "$CAMERA_HEIGHT" \
  "$CAMERA_MIN_DEPTH_M" "$CAMERA_MAX_DEPTH_M" "$CAMERA_FORWARD_OFFSET_M" \
  "$TURBINE_CENTER_X" "$TURBINE_CENTER_Y" "$TURBINE_CENTER_Z" "$MAX_VIEW_ANGLE_DEG" \
  "$MIN_MEAN_USEFUL_RATIO" "$MIN_ANY_USEFUL_RATIO" "$MIN_NORMAL_FILTERED_COVERAGE_RATIO" "$Z_BAND_COUNT" \
  >"${SUMMARY_FILE}" <<'PY'
import ast
import csv
import math
import re
import sys
import xml.etree.ElementTree as ET

(
    launch_path,
    world_path,
    mesh_path,
    depth_stats_summary,
    sample_csv,
    band_csv,
    view_csv,
) = sys.argv[1:8]
hfov = float(sys.argv[8])
camera_width = int(sys.argv[9])
camera_height = int(sys.argv[10])
min_depth = float(sys.argv[11])
max_depth = float(sys.argv[12])
camera_forward_offset = float(sys.argv[13])
cx = float(sys.argv[14])
cy = float(sys.argv[15])
cz = float(sys.argv[16])
max_view_angle_deg = float(sys.argv[17])
min_mean_useful_ratio = float(sys.argv[18])
min_any_useful_ratio = float(sys.argv[19])
min_normal_filtered_coverage_ratio = float(sys.argv[20])
z_band_count = int(sys.argv[21])

def parse_key_values(path):
    values = {}
    if not path:
        return values
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if "=" not in line or line.startswith("#"):
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return values

def as_float(values, key):
    try:
        return float(values.get(key, "nan"))
    except ValueError:
        return float("nan")

with open(launch_path, "r", encoding="utf-8") as f:
    source = f.read()

module = ast.parse(source, filename=launch_path)
orbit_function = None
for node in module.body:
    if isinstance(node, ast.FunctionDef) and node.name == "_orbit_waypoints":
        orbit_function = node
        break
if orbit_function is None:
    raise SystemExit("_orbit_waypoints function not found")

namespace = {"math": math}
ast.fix_missing_locations(orbit_function)
exec(compile(ast.Module(body=[orbit_function], type_ignores=[]), launch_path, "exec"), namespace)
flat_waypoints, yaws = namespace["_orbit_waypoints"]()
if len(flat_waypoints) % 3 != 0:
    raise SystemExit("waypoints are not a flat list of NED triples")

waypoints = [
    tuple(float(v) for v in flat_waypoints[i:i + 3])
    for i in range(0, len(flat_waypoints), 3)
]
yaws = [float(v) for v in yaws]

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
    semantic = item.attrib.get("semantic")
    source_ref = item.attrib.get("source", "")
    offset = int(item.attrib.get("offset", "0"))
    inputs.append((semantic, source_ref.lstrip("#"), offset))
stride = max(offset for _, _, offset in inputs) + 1
vertex_offset = next((offset for semantic, _, offset in inputs if semantic == "VERTEX"), None)
normal_offset = next((offset for semantic, _, offset in inputs if semantic == "NORMAL"), None)
if vertex_offset is None or normal_offset is None:
    raise SystemExit("DAE triangles must provide VERTEX and NORMAL inputs")
p_node = triangles.find("c:p", ns)
if p_node is None or not p_node.text:
    raise SystemExit("DAE triangles p data not found")
indices = [int(x) for x in p_node.text.split()]
if len(indices) % (3 * stride) != 0:
    raise SystemExit("DAE triangles p data length is incompatible with input stride")

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
        pos_idx = indices[start + vertex_offset]
        normal_idx = indices[start + normal_offset]
        tri_points.append(transform_position(positions[pos_idx]))
        tri_normals.append(transform_normal(normals[normal_idx]))
    centroid = (
        sum(p[0] for p in tri_points) / 3.0,
        sum(p[1] for p in tri_points) / 3.0,
        sum(p[2] for p in tri_points) / 3.0,
    )
    avg_normal = (
        sum(n[0] for n in tri_normals) / 3.0,
        sum(n[1] for n in tri_normals) / 3.0,
        sum(n[2] for n in tri_normals) / 3.0,
    )
    normal_norm = math.sqrt(sum(v * v for v in avg_normal))
    if normal_norm > 1e-9:
        avg_normal = tuple(v / normal_norm for v in avg_normal)
    samples.append((centroid, avg_normal))

vfov = 2.0 * math.atan(math.tan(hfov / 2.0) * (camera_height / camera_width))
half_hfov = hfov / 2.0
half_vfov = vfov / 2.0
cos_max_view_angle = math.cos(math.radians(max_view_angle_deg))

def camera_basis(cam_pos, look_at):
    fx = look_at[0] - cam_pos[0]
    fy = look_at[1] - cam_pos[1]
    fz = look_at[2] - cam_pos[2]
    forward_norm = math.sqrt(fx * fx + fy * fy + fz * fz)
    if forward_norm <= 1e-9:
        return None
    forward = (fx / forward_norm, fy / forward_norm, fz / forward_norm)
    world_up = (0.0, 0.0, 1.0)
    right_x = forward[1] * world_up[2] - forward[2] * world_up[1]
    right_y = forward[2] * world_up[0] - forward[0] * world_up[2]
    right_z = forward[0] * world_up[1] - forward[1] * world_up[0]
    right_norm = math.sqrt(right_x * right_x + right_y * right_y + right_z * right_z)
    if right_norm <= 1e-9:
        return None
    right = (right_x / right_norm, right_y / right_norm, right_z / right_norm)
    up = (
        right[1] * forward[2] - right[2] * forward[1],
        right[2] * forward[0] - right[0] * forward[2],
        right[0] * forward[1] - right[1] * forward[0],
    )
    return forward, right, up

def frustum_hit(sample, cam_pos, basis):
    point, _ = sample
    vx = point[0] - cam_pos[0]
    vy = point[1] - cam_pos[1]
    vz = point[2] - cam_pos[2]
    dist = math.sqrt(vx * vx + vy * vy + vz * vz)
    if dist < min_depth or dist > max_depth:
        return False, dist
    forward, right, up = basis
    x_cam = vx * forward[0] + vy * forward[1] + vz * forward[2]
    if x_cam <= 0.0:
        return False, dist
    y_cam = vx * right[0] + vy * right[1] + vz * right[2]
    z_cam = vx * up[0] + vy * up[1] + vz * up[2]
    horizontal = abs(math.atan2(y_cam, x_cam))
    vertical = abs(math.atan2(z_cam, x_cam))
    return horizontal <= half_hfov and vertical <= half_vfov, dist

def normal_quality_hit(sample, cam_pos):
    point, normal = sample
    vx = cam_pos[0] - point[0]
    vy = cam_pos[1] - point[1]
    vz = cam_pos[2] - point[2]
    norm = math.sqrt(vx * vx + vy * vy + vz * vz)
    if norm <= 1e-9:
        return False, -1.0
    view_dir = (vx / norm, vy / norm, vz / norm)
    dot = normal[0] * view_dir[0] + normal[1] * view_dir[1] + normal[2] * view_dir[2]
    return dot >= cos_max_view_angle, dot

frustum_hits = [0] * len(samples)
normal_hits = [0] * len(samples)
best_dot = [-1.0] * len(samples)
view_rows = []
look_at = (cx, cy, cz)
for idx, (x, y, z) in enumerate(waypoints):
    yaw = yaws[idx] if idx < len(yaws) else math.atan2(cy - y, cx - x)
    cam_pos = (
        x + camera_forward_offset * math.cos(yaw),
        y + camera_forward_offset * math.sin(yaw),
        z,
    )
    basis = camera_basis(cam_pos, look_at)
    frustum_count = 0
    normal_count = 0
    if basis is not None:
        for sample_idx, sample in enumerate(samples):
            in_frustum, _ = frustum_hit(sample, cam_pos, basis)
            if not in_frustum:
                continue
            frustum_hits[sample_idx] += 1
            frustum_count += 1
            ok_normal, dot = normal_quality_hit(sample, cam_pos)
            best_dot[sample_idx] = max(best_dot[sample_idx], dot)
            if ok_normal:
                normal_hits[sample_idx] += 1
                normal_count += 1
    view_rows.append((
        idx, x, y, z, yaw, frustum_count, normal_count,
        frustum_count / len(samples) if samples else 0.0,
        normal_count / len(samples) if samples else 0.0,
    ))

sample_count = len(samples)
frustum_covered = sum(1 for hits in frustum_hits if hits >= 1)
normal_covered = sum(1 for hits in normal_hits if hits >= 1)
normal_covered_twice = sum(1 for hits in normal_hits if hits >= 2)
frustum_coverage_ratio = frustum_covered / sample_count if sample_count else 0.0
normal_filtered_coverage_ratio = normal_covered / sample_count if sample_count else 0.0
normal_double_observed_ratio = normal_covered_twice / sample_count if sample_count else 0.0
mean_normal_observations = sum(normal_hits) / sample_count if sample_count else 0.0
max_normal_observations = max(normal_hits) if normal_hits else 0
max_best_dot = max(best_dot) if best_dot else -1.0

depth_values = parse_key_values(depth_stats_summary)
mean_useful_ratio = as_float(depth_values, "mean_useful_ratio")
max_useful_ratio = as_float(depth_values, "max_useful_ratio")
depth_decision = depth_values.get("decision", "")
depth_frames = depth_values.get("depth_frames", "")
depth_stats_available = bool(depth_values)
depth_quality_ok = (
    depth_stats_available
    and not math.isnan(mean_useful_ratio)
    and not math.isnan(max_useful_ratio)
    and mean_useful_ratio >= min_mean_useful_ratio
    and max_useful_ratio >= min_any_useful_ratio
)
normal_candidate_ok = normal_filtered_coverage_ratio >= min_normal_filtered_coverage_ratio

z_min = min(sample[0][2] for sample in samples) if samples else 0.0
z_max = max(sample[0][2] for sample in samples) if samples else 0.0
band_rows = []
min_band_normal_coverage = 1.0
for band in range(max(1, z_band_count)):
    lower = z_min + (z_max - z_min) * band / max(1, z_band_count)
    upper = z_min + (z_max - z_min) * (band + 1) / max(1, z_band_count)
    indices_in_band = [
        i for i, sample in enumerate(samples)
        if sample[0][2] >= lower and (sample[0][2] < upper or band == z_band_count - 1)
    ]
    if indices_in_band:
        f_count = sum(1 for i in indices_in_band if frustum_hits[i] >= 1)
        n_count = sum(1 for i in indices_in_band if normal_hits[i] >= 1)
        f_ratio = f_count / len(indices_in_band)
        n_ratio = n_count / len(indices_in_band)
        min_band_normal_coverage = min(min_band_normal_coverage, n_ratio)
    else:
        f_count = n_count = 0
        f_ratio = n_ratio = 0.0
        min_band_normal_coverage = 0.0
    band_rows.append((band, lower, upper, len(indices_in_band), f_count, f_ratio, n_count, n_ratio))

with open(sample_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow([
        "triangle_index", "world_x", "world_y", "world_z", "normal_x", "normal_y", "normal_z",
        "frustum_observations", "normal_filtered_observations", "best_normal_view_dot",
    ])
    for idx, ((point, normal), f_hits, n_hits, dot) in enumerate(zip(samples, frustum_hits, normal_hits, best_dot)):
        writer.writerow([
            idx,
            f"{point[0]:.6f}", f"{point[1]:.6f}", f"{point[2]:.6f}",
            f"{normal[0]:.6f}", f"{normal[1]:.6f}", f"{normal[2]:.6f}",
            f_hits, n_hits, f"{dot:.6f}",
        ])

with open(band_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow([
        "band", "z_min", "z_max", "sample_count", "frustum_covered_count",
        "frustum_covered_ratio", "normal_covered_count", "normal_covered_ratio",
    ])
    for row in band_rows:
        band, lower, upper, count, f_count, f_ratio, n_count, n_ratio = row
        writer.writerow([
            band, f"{lower:.6f}", f"{upper:.6f}", count, f_count, f"{f_ratio:.6f}",
            n_count, f"{n_ratio:.6f}",
        ])

with open(view_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow([
        "index", "ned_x", "ned_y", "ned_z", "yaw_rad", "frustum_samples",
        "normal_filtered_samples", "frustum_ratio", "normal_filtered_ratio",
    ])
    for row in view_rows:
        idx, x, y, z, yaw, f_count, n_count, f_ratio, n_ratio = row
        writer.writerow([
            idx, f"{x:.6f}", f"{y:.6f}", f"{z:.6f}", f"{yaw:.6f}",
            f_count, n_count, f"{f_ratio:.6f}", f"{n_ratio:.6f}",
        ])

accepted = sample_count > 0 and len(view_rows) > 0 and depth_quality_ok

print("scope=wind_orbit_quality_coverage_static_audit")
print(f"decision={'accepted_wind_orbit_quality_coverage_static_audit' if accepted else 'rejected_wind_orbit_quality_coverage_static_audit'}")
print(f"reason={'quality_metrics_generated_with_depth_stats' if accepted else 'quality_metrics_or_depth_stats_invalid'}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print(f"launch_path={launch_path}")
print(f"world_path={world_path}")
print(f"mesh_path={mesh_path}")
print(f"depth_stats_summary={depth_stats_summary}")
print("coverage_model=mesh_triangle_centroid_frustum_normal_depth_quality_no_occlusion")
print("claims_final_coverage=false")
print(f"camera_hfov_rad={hfov:.6f}")
print(f"camera_vfov_rad={vfov:.6f}")
print(f"camera_min_depth_m={min_depth:.6f}")
print(f"camera_max_depth_m={max_depth:.6f}")
print(f"max_view_angle_deg={max_view_angle_deg:.6f}")
print(f"cos_max_view_angle={cos_max_view_angle:.6f}")
print(f"sample_count={sample_count}")
print(f"view_count={len(view_rows)}")
print(f"frustum_covered_samples={frustum_covered}")
print(f"normal_filtered_covered_samples={normal_covered}")
print(f"normal_filtered_twice_samples={normal_covered_twice}")
print(f"frustum_coverage_ratio={frustum_coverage_ratio:.6f}")
print(f"normal_filtered_coverage_ratio={normal_filtered_coverage_ratio:.6f}")
print(f"normal_filtered_double_observed_ratio={normal_double_observed_ratio:.6f}")
print(f"mean_normal_observations_per_sample={mean_normal_observations:.6f}")
print(f"max_normal_observations_per_sample={max_normal_observations}")
print(f"max_best_normal_view_dot={max_best_dot:.6f}")
print(f"z_band_count={z_band_count}")
print(f"min_band_normal_coverage_ratio_observed={min_band_normal_coverage:.6f}")
print(f"min_normal_filtered_coverage_ratio={min_normal_filtered_coverage_ratio:.6f}")
print(f"normal_candidate_ok={str(normal_candidate_ok).lower()}")
print(f"depth_stats_available={str(depth_stats_available).lower()}")
print(f"depth_stats_decision={depth_decision}")
print(f"depth_frames={depth_frames}")
print(f"mean_useful_ratio={mean_useful_ratio:.6f}")
print(f"max_useful_ratio={max_useful_ratio:.6f}")
print(f"min_mean_useful_ratio={min_mean_useful_ratio:.6f}")
print(f"min_any_useful_ratio={min_any_useful_ratio:.6f}")
print(f"depth_quality_ok={str(depth_quality_ok).lower()}")
print(f"sample_csv={sample_csv}")
print(f"band_csv={band_csv}")
print(f"view_csv={view_csv}")

if not accepted:
    raise SystemExit(2)
PY

grep -q '^decision=accepted_wind_orbit_quality_coverage_static_audit$' "${SUMMARY_FILE}"

echo "Wind orbit quality coverage static audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Sample CSV: ${SAMPLE_CSV}"
echo "Band CSV: ${BAND_CSV}"
echo "View CSV: ${VIEW_CSV}"
