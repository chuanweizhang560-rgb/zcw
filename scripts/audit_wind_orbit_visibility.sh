#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${OUTPUT_DIR:-${RESULT_ROOT}/wind_orbit_visibility_${STAMP}}"
SUMMARY_FILE="${RESULT_DIR}/wind_orbit_visibility_${STAMP}.txt"
WAYPOINT_CSV="${RESULT_DIR}/wind_orbit_visibility_waypoints_${STAMP}.csv"

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
MIN_UNION_VISIBLE_RATIO="${MIN_UNION_VISIBLE_RATIO:-0.2}"
MIN_BEST_VIEW_RATIO="${MIN_BEST_VIEW_RATIO:-0.1}"
MIN_BEST_VIEW_FRAME_FILL_RATIO="${MIN_BEST_VIEW_FRAME_FILL_RATIO:-0.09}"

for path in "${LAUNCH_PATH}" "${WORLD_PATH}" "${MESH_PATH}"; do
  if [[ ! -f "${path}" ]]; then
    echo "Required input missing: ${path}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

python3 - "$LAUNCH_PATH" "$WORLD_PATH" "$MESH_PATH" "$WAYPOINT_CSV" \
  "$CAMERA_HFOV_RAD" "$CAMERA_WIDTH" "$CAMERA_HEIGHT" "$CAMERA_MIN_DEPTH_M" \
  "$CAMERA_MAX_DEPTH_M" "$CAMERA_FORWARD_OFFSET_M" "$TURBINE_CENTER_X" "$TURBINE_CENTER_Y" "$TURBINE_CENTER_Z" \
  "$MIN_UNION_VISIBLE_RATIO" "$MIN_BEST_VIEW_RATIO" "$MIN_BEST_VIEW_FRAME_FILL_RATIO" >"${SUMMARY_FILE}" <<'PY'
import ast
import csv
import math
import re
import sys
import xml.etree.ElementTree as ET

launch_path, world_path, mesh_path, waypoint_csv = sys.argv[1:5]
hfov = float(sys.argv[5])
camera_width = int(sys.argv[6])
camera_height = int(sys.argv[7])
min_depth = float(sys.argv[8])
max_depth = float(sys.argv[9])
camera_forward_offset = float(sys.argv[10])
cx = float(sys.argv[11])
cy = float(sys.argv[12])
cz = float(sys.argv[13])
min_union_visible_ratio = float(sys.argv[14])
min_best_view_ratio = float(sys.argv[15])
min_best_view_frame_fill_ratio = float(sys.argv[16])

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

xs = values[0::3]
ys = values[1::3]
zs = values[2::3]

vertices = []
cos_y = math.cos(world_yaw)
sin_y = math.sin(world_yaw)
for x, y, z in zip(xs, ys, zs):
    # Mesh coordinates are exported as Y_UP. Rotate in the world yaw plane and
    # then translate to the turbine's world pose. This keeps the audit
    # conservative and fully read-only.
    xr = x * cos_y - y * sin_y
    yr = x * sin_y + y * cos_y
    vertices.append((world_pose[0] + xr, world_pose[1] + yr, world_pose[2] + z))

vfov = 2.0 * math.atan(math.tan(hfov / 2.0) * (camera_height / camera_width))
half_hfov = hfov / 2.0
half_vfov = vfov / 2.0

def visible_from_view(vertex, cam_pos, look_at):
    vx = vertex[0] - cam_pos[0]
    vy = vertex[1] - cam_pos[1]
    vz = vertex[2] - cam_pos[2]
    dist = math.sqrt(vx * vx + vy * vy + vz * vz)
    if dist < min_depth or dist > max_depth:
        return False

    fx = look_at[0] - cam_pos[0]
    fy = look_at[1] - cam_pos[1]
    fz = look_at[2] - cam_pos[2]
    forward_norm = math.sqrt(fx * fx + fy * fy + fz * fz)
    if forward_norm <= 1e-9:
        return False
    forward = (fx / forward_norm, fy / forward_norm, fz / forward_norm)

    world_up = (0.0, 0.0, 1.0)
    right_x = forward[1] * world_up[2] - forward[2] * world_up[1]
    right_y = forward[2] * world_up[0] - forward[0] * world_up[2]
    right_z = forward[0] * world_up[1] - forward[1] * world_up[0]
    right_norm = math.sqrt(right_x * right_x + right_y * right_y + right_z * right_z)
    if right_norm <= 1e-9:
        return False
    right = (right_x / right_norm, right_y / right_norm, right_z / right_norm)
    up = (
        right[1] * forward[2] - right[2] * forward[1],
        right[2] * forward[0] - right[0] * forward[2],
        right[0] * forward[1] - right[1] * forward[0],
    )

    x_cam = vx * forward[0] + vy * forward[1] + vz * forward[2]
    y_cam = vx * right[0] + vy * right[1] + vz * right[2]
    z_cam = vx * up[0] + vy * up[1] + vz * up[2]
    if x_cam <= 0.0:
        return False
    horizontal = abs(math.atan2(y_cam, x_cam))
    vertical = abs(math.atan2(z_cam, x_cam))
    return horizontal <= half_hfov and vertical <= half_vfov

def project_to_frame(vertex, cam_pos, look_at):
    vx = vertex[0] - cam_pos[0]
    vy = vertex[1] - cam_pos[1]
    vz = vertex[2] - cam_pos[2]
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
    x_cam = vx * forward[0] + vy * forward[1] + vz * forward[2]
    if x_cam <= 0.0:
        return None
    y_cam = vx * right[0] + vy * right[1] + vz * right[2]
    z_cam = vx * up[0] + vy * up[1] + vz * up[2]
    u = 0.5 + 0.5 * (y_cam / (x_cam * math.tan(half_hfov)))
    v = 0.5 - 0.5 * (z_cam / (x_cam * math.tan(half_vfov)))
    return u, v

view_visible_counts = []
view_frame_fill_ratios = []
vertex_visible_once = [False] * len(vertices)
rows = []

for idx, (x, y, z) in enumerate(waypoints):
    yaw = yaws[idx]
    cam_x = x + camera_forward_offset * math.cos(yaw)
    cam_y = y + camera_forward_offset * math.sin(yaw)
    cam_z = z
    cam_pos = (cam_x, cam_y, cam_z)
    look_at = (cx, cy, cz)
    visible_count = 0
    projected = []
    for vi, vertex in enumerate(vertices):
      # ray/occlusion is intentionally omitted; this audit is a frustum-only
      # visibility upper bound using existing open-source geometry inputs.
        if visible_from_view(vertex, cam_pos, look_at):
            visible_count += 1
            vertex_visible_once[vi] = True
            uv = project_to_frame(vertex, cam_pos, look_at)
            if uv is not None and 0.0 <= uv[0] <= 1.0 and 0.0 <= uv[1] <= 1.0:
                projected.append(uv)
    ratio = visible_count / len(vertices) if vertices else 0.0
    view_visible_counts.append(visible_count)
    if projected:
        u_values = [p[0] for p in projected]
        v_values = [p[1] for p in projected]
        bbox_area_ratio = max(0.0, min(1.0, (max(u_values) - min(u_values)) * (max(v_values) - min(v_values))))
    else:
        bbox_area_ratio = 0.0
    view_frame_fill_ratios.append(bbox_area_ratio)
    rows.append((idx, x, y, z, yaw, visible_count, ratio, bbox_area_ratio))

union_visible_count = sum(1 for seen in vertex_visible_once if seen)
union_visible_ratio = union_visible_count / len(vertices) if vertices else 0.0
best_view_visible_count = max(view_visible_counts) if view_visible_counts else 0
best_view_visible_ratio = best_view_visible_count / len(vertices) if vertices else 0.0
mean_view_visible_ratio = (
    sum(view_visible_counts) / len(view_visible_counts) / len(vertices)
    if view_visible_counts and vertices else 0.0
)
best_view_frame_fill_ratio = max(view_frame_fill_ratios) if view_frame_fill_ratios else 0.0
mean_view_frame_fill_ratio = (
    sum(view_frame_fill_ratios) / len(view_frame_fill_ratios)
    if view_frame_fill_ratios else 0.0
)

with open(waypoint_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["index", "ned_x", "ned_y", "ned_z", "yaw_rad", "visible_vertices", "visible_ratio", "frame_fill_ratio"])
    for row in rows:
        idx, x, y, z, yaw, visible_count, ratio, bbox_area_ratio = row
        writer.writerow([idx, f"{x:.6f}", f"{y:.6f}", f"{z:.6f}", f"{yaw:.6f}", visible_count, f"{ratio:.6f}", f"{bbox_area_ratio:.6f}"])

accepted = (
    union_visible_ratio >= min_union_visible_ratio
    and best_view_visible_ratio >= min_best_view_ratio
    and best_view_frame_fill_ratio >= min_best_view_frame_fill_ratio
)

print("scope=wind_orbit_visibility_static_audit")
print(f"decision={'accepted_wind_orbit_visibility_static_audit' if accepted else 'rejected_wind_orbit_visibility_static_audit'}")
print(f"reason={'orbit_views_have_measurable_visible_surface_upper_bound' if accepted else 'orbit_views_have_too_little_visible_surface_upper_bound'}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print(f"launch_path={launch_path}")
print(f"world_pose_x={world_pose[0]:.6f}")
print(f"world_pose_y={world_pose[1]:.6f}")
print(f"world_pose_z={world_pose[2]:.6f}")
print(f"world_pose_yaw_rad={world_yaw:.6f}")
print(f"camera_hfov_rad={hfov:.6f}")
print(f"camera_vfov_rad={vfov:.6f}")
print(f"camera_min_depth_m={min_depth:.6f}")
print(f"camera_max_depth_m={max_depth:.6f}")
print(f"camera_forward_offset_m={camera_forward_offset:.6f}")
print(f"camera_look_at_x={cx:.6f}")
print(f"camera_look_at_y={cy:.6f}")
print(f"camera_look_at_z={cz:.6f}")
print(f"mesh_vertices={len(vertices)}")
print(f"view_count={len(rows)}")
print(f"union_visible_vertices={union_visible_count}")
print(f"union_visible_ratio={union_visible_ratio:.6f}")
print(f"best_view_visible_vertices={best_view_visible_count}")
print(f"best_view_visible_ratio={best_view_visible_ratio:.6f}")
print(f"mean_view_visible_ratio={mean_view_visible_ratio:.6f}")
print(f"best_view_frame_fill_ratio={best_view_frame_fill_ratio:.6f}")
print(f"mean_view_frame_fill_ratio={mean_view_frame_fill_ratio:.6f}")
print(f"min_best_view_frame_fill_ratio={min_best_view_frame_fill_ratio:.6f}")
print(f"min_union_visible_ratio={min_union_visible_ratio:.6f}")
print(f"min_best_view_ratio={min_best_view_ratio:.6f}")
print(f"waypoint_csv={waypoint_csv}")

if not accepted:
    raise SystemExit(2)
PY

grep -q '^decision=accepted_wind_orbit_visibility_static_audit$' "${SUMMARY_FILE}"

echo "Wind orbit visibility static audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Waypoint CSV: ${WAYPOINT_CSV}"
