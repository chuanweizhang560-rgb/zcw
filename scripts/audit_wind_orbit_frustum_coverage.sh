#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${OUTPUT_DIR:-${RESULT_ROOT}/wind_orbit_frustum_coverage_${STAMP}}"
SUMMARY_FILE="${RESULT_DIR}/wind_orbit_frustum_coverage_${STAMP}.txt"
VERTEX_CSV="${RESULT_DIR}/wind_orbit_frustum_coverage_vertices_${STAMP}.csv"
BAND_CSV="${RESULT_DIR}/wind_orbit_frustum_coverage_bands_${STAMP}.csv"
VIEW_CSV="${RESULT_DIR}/wind_orbit_frustum_coverage_views_${STAMP}.csv"

LAUNCH_PATH="${LAUNCH_PATH:-ros2_ws/src/zcw_bringup/launch/single_vehicle_wind_turbine_multilevel_orbit.launch.py}"
WORLD_PATH="${WORLD_PATH:-third_party/aerialcore_simulation/worlds/wind_turbine_autospawn.world}"
MESH_PATH="${MESH_PATH:-third_party/aerialcore_simulation/models/wind_turbine/wind_turbine_scaled.dae}"
CAMERA_HFOV_RAD="${CAMERA_HFOV_RAD:-1.5009831567}"
CAMERA_WIDTH="${CAMERA_WIDTH:-848}"
CAMERA_HEIGHT="${CAMERA_HEIGHT:-480}"
CAMERA_MIN_DEPTH_M="${CAMERA_MIN_DEPTH_M:-0.2}"
CAMERA_MAX_DEPTH_M="${CAMERA_MAX_DEPTH_M:-65.535}"
CAMERA_FORWARD_OFFSET_M="${CAMERA_FORWARD_OFFSET_M:-0.1}"
TURBINE_CENTER_X="${TURBINE_CENTER_X:--25.0}"
TURBINE_CENTER_Y="${TURBINE_CENTER_Y:--25.0}"
TURBINE_CENTER_Z="${TURBINE_CENTER_Z:-0.0}"
MIN_VERTEX_COVERAGE_RATIO="${MIN_VERTEX_COVERAGE_RATIO:-0.95}"
MIN_DOUBLE_OBSERVED_RATIO="${MIN_DOUBLE_OBSERVED_RATIO:-0.75}"
MIN_BAND_COVERAGE_RATIO="${MIN_BAND_COVERAGE_RATIO:-0.90}"
Z_BAND_COUNT="${Z_BAND_COUNT:-4}"

for path in "${LAUNCH_PATH}" "${WORLD_PATH}" "${MESH_PATH}"; do
  if [[ ! -f "${path}" ]]; then
    echo "Required input missing: ${path}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

python3 - "$LAUNCH_PATH" "$WORLD_PATH" "$MESH_PATH" "$VERTEX_CSV" "$BAND_CSV" "$VIEW_CSV" \
  "$CAMERA_HFOV_RAD" "$CAMERA_WIDTH" "$CAMERA_HEIGHT" "$CAMERA_MIN_DEPTH_M" \
  "$CAMERA_MAX_DEPTH_M" "$CAMERA_FORWARD_OFFSET_M" "$TURBINE_CENTER_X" "$TURBINE_CENTER_Y" "$TURBINE_CENTER_Z" \
  "$MIN_VERTEX_COVERAGE_RATIO" "$MIN_DOUBLE_OBSERVED_RATIO" "$MIN_BAND_COVERAGE_RATIO" "$Z_BAND_COUNT" \
  >"${SUMMARY_FILE}" <<'PY'
import ast
import csv
import math
import re
import sys
import xml.etree.ElementTree as ET

launch_path, world_path, mesh_path, vertex_csv, band_csv, view_csv = sys.argv[1:7]
hfov = float(sys.argv[7])
camera_width = int(sys.argv[8])
camera_height = int(sys.argv[9])
min_depth = float(sys.argv[10])
max_depth = float(sys.argv[11])
camera_forward_offset = float(sys.argv[12])
cx = float(sys.argv[13])
cy = float(sys.argv[14])
cz = float(sys.argv[15])
min_vertex_coverage_ratio = float(sys.argv[16])
min_double_observed_ratio = float(sys.argv[17])
min_band_coverage_ratio = float(sys.argv[18])
z_band_count = int(sys.argv[19])

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

tree = ET.parse(mesh_path)
root = tree.getroot()
ns = {"c": "http://www.collada.org/2005/11/COLLADASchema"}
float_array = root.find(".//c:source[@id='shape0-lib-positions']/c:float_array", ns)
if float_array is None or not float_array.text:
    raise SystemExit("wind turbine DAE position float_array not found")
values = [float(x) for x in float_array.text.split()]
if len(values) % 3 != 0:
    raise SystemExit("wind turbine DAE position count is not divisible by 3")

cos_y = math.cos(world_yaw)
sin_y = math.sin(world_yaw)
vertices = []
for x, y, z in zip(values[0::3], values[1::3], values[2::3]):
    xr = x * cos_y - y * sin_y
    yr = x * sin_y + y * cos_y
    vertices.append((world_pose[0] + xr, world_pose[1] + yr, world_pose[2] + z))

vfov = 2.0 * math.atan(math.tan(hfov / 2.0) * (camera_height / camera_width))
half_hfov = hfov / 2.0
half_vfov = vfov / 2.0

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

def visible_from_basis(vertex, cam_pos, basis):
    vx = vertex[0] - cam_pos[0]
    vy = vertex[1] - cam_pos[1]
    vz = vertex[2] - cam_pos[2]
    dist = math.sqrt(vx * vx + vy * vy + vz * vz)
    if dist < min_depth or dist > max_depth:
        return False
    forward, right, up = basis
    x_cam = vx * forward[0] + vy * forward[1] + vz * forward[2]
    if x_cam <= 0.0:
        return False
    y_cam = vx * right[0] + vy * right[1] + vz * right[2]
    z_cam = vx * up[0] + vy * up[1] + vz * up[2]
    horizontal = abs(math.atan2(y_cam, x_cam))
    vertical = abs(math.atan2(z_cam, x_cam))
    return horizontal <= half_hfov and vertical <= half_vfov

vertex_hits = [0] * len(vertices)
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
    visible_count = 0
    if basis is not None:
        for vi, vertex in enumerate(vertices):
            if visible_from_basis(vertex, cam_pos, basis):
                vertex_hits[vi] += 1
                visible_count += 1
    view_rows.append((idx, x, y, z, yaw, visible_count, visible_count / len(vertices) if vertices else 0.0))

covered_once = sum(1 for hits in vertex_hits if hits >= 1)
covered_twice = sum(1 for hits in vertex_hits if hits >= 2)
max_observations = max(vertex_hits) if vertex_hits else 0
mean_observations = sum(vertex_hits) / len(vertex_hits) if vertex_hits else 0.0
vertex_coverage_ratio = covered_once / len(vertex_hits) if vertex_hits else 0.0
double_observed_ratio = covered_twice / len(vertex_hits) if vertex_hits else 0.0

z_min = min(v[2] for v in vertices) if vertices else 0.0
z_max = max(v[2] for v in vertices) if vertices else 0.0
band_rows = []
min_band_observed = 1.0
for band in range(max(1, z_band_count)):
    lower = z_min + (z_max - z_min) * band / max(1, z_band_count)
    upper = z_min + (z_max - z_min) * (band + 1) / max(1, z_band_count)
    indices = [
        i for i, vertex in enumerate(vertices)
        if (vertex[2] >= lower and (vertex[2] < upper or band == z_band_count - 1))
    ]
    if indices:
        band_covered = sum(1 for i in indices if vertex_hits[i] >= 1)
        band_ratio = band_covered / len(indices)
        min_band_observed = min(min_band_observed, band_ratio)
    else:
        band_covered = 0
        band_ratio = 0.0
        min_band_observed = 0.0
    band_rows.append((band, lower, upper, len(indices), band_covered, band_ratio))

with open(vertex_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["index", "world_x", "world_y", "world_z", "frustum_observations"])
    for idx, (vertex, hits) in enumerate(zip(vertices, vertex_hits)):
        writer.writerow([idx, f"{vertex[0]:.6f}", f"{vertex[1]:.6f}", f"{vertex[2]:.6f}", hits])

with open(band_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["band", "z_min", "z_max", "vertex_count", "covered_once_count", "covered_once_ratio"])
    for row in band_rows:
        band, lower, upper, count, covered, ratio = row
        writer.writerow([band, f"{lower:.6f}", f"{upper:.6f}", count, covered, f"{ratio:.6f}"])

with open(view_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["index", "ned_x", "ned_y", "ned_z", "yaw_rad", "visible_vertices", "visible_ratio"])
    for row in view_rows:
        idx, x, y, z, yaw, visible_count, ratio = row
        writer.writerow([idx, f"{x:.6f}", f"{y:.6f}", f"{z:.6f}", f"{yaw:.6f}", visible_count, f"{ratio:.6f}"])

accepted = (
    vertex_coverage_ratio >= min_vertex_coverage_ratio
    and double_observed_ratio >= min_double_observed_ratio
    and min_band_observed >= min_band_coverage_ratio
)

print("scope=wind_orbit_frustum_coverage_static_audit")
print(f"decision={'accepted_wind_orbit_frustum_coverage_static_audit' if accepted else 'rejected_wind_orbit_frustum_coverage_static_audit'}")
print(f"reason={'orbit_frustum_covers_mesh_vertices_upper_bound' if accepted else 'orbit_frustum_coverage_below_threshold'}")
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
print("coverage_model=mesh_vertex_frustum_upper_bound_no_occlusion")
print(f"camera_hfov_rad={hfov:.6f}")
print(f"camera_vfov_rad={vfov:.6f}")
print(f"camera_min_depth_m={min_depth:.6f}")
print(f"camera_max_depth_m={max_depth:.6f}")
print(f"mesh_vertices={len(vertices)}")
print(f"view_count={len(view_rows)}")
print(f"covered_once_vertices={covered_once}")
print(f"covered_twice_vertices={covered_twice}")
print(f"vertex_coverage_ratio={vertex_coverage_ratio:.6f}")
print(f"double_observed_ratio={double_observed_ratio:.6f}")
print(f"mean_observations_per_vertex={mean_observations:.6f}")
print(f"max_observations_per_vertex={max_observations}")
print(f"z_band_count={z_band_count}")
print(f"min_band_coverage_ratio_observed={min_band_observed:.6f}")
print(f"min_vertex_coverage_ratio={min_vertex_coverage_ratio:.6f}")
print(f"min_double_observed_ratio={min_double_observed_ratio:.6f}")
print(f"min_band_coverage_ratio={min_band_coverage_ratio:.6f}")
print(f"vertex_csv={vertex_csv}")
print(f"band_csv={band_csv}")
print(f"view_csv={view_csv}")

if not accepted:
    raise SystemExit(2)
PY

grep -q '^decision=accepted_wind_orbit_frustum_coverage_static_audit$' "${SUMMARY_FILE}"

echo "Wind orbit frustum coverage static audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Vertex CSV: ${VERTEX_CSV}"
echo "Band CSV: ${BAND_CSV}"
echo "View CSV: ${VIEW_CSV}"
