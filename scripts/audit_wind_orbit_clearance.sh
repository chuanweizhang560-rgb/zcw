#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${OUTPUT_DIR:-${RESULT_ROOT}/wind_orbit_clearance_${STAMP}}"
SUMMARY_FILE="${RESULT_DIR}/wind_orbit_clearance_${STAMP}.txt"
WAYPOINT_CSV="${RESULT_DIR}/wind_orbit_clearance_waypoints_${STAMP}.csv"

LAUNCH_PATH="${LAUNCH_PATH:-ros2_ws/src/zcw_bringup/launch/single_vehicle_wind_turbine_multilevel_orbit.launch.py}"
MESH_PATH="${MESH_PATH:-third_party/aerialcore_simulation/models/wind_turbine/wind_turbine_scaled.dae}"
TURBINE_CENTER_X="${TURBINE_CENTER_X:--25.0}"
TURBINE_CENTER_Y="${TURBINE_CENTER_Y:--25.0}"
MIN_CLEARANCE_M="${MIN_CLEARANCE_M:-1.0}"

for path in "${LAUNCH_PATH}" "${MESH_PATH}"; do
  if [[ ! -f "${path}" ]]; then
    echo "Required input missing: ${path}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

python3 - "$LAUNCH_PATH" "$MESH_PATH" "$WAYPOINT_CSV" "$TURBINE_CENTER_X" "$TURBINE_CENTER_Y" "$MIN_CLEARANCE_M" >"${SUMMARY_FILE}" <<'PY'
import ast
import csv
import math
import sys
import xml.etree.ElementTree as ET

launch_path, mesh_path, waypoint_csv = sys.argv[1:4]
cx = float(sys.argv[4])
cy = float(sys.argv[5])
min_clearance = float(sys.argv[6])

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

# The Collada asset declares Y_UP, while Gazebo imports it into a Z-up world.
# Use the maximum radial extent over all coordinate-plane projections as a
# conservative static clearance envelope.
mesh_radius_xy = max(math.hypot(x, y) for x, y in zip(xs, ys))
mesh_radius_xz = max(math.hypot(x, z) for x, z in zip(xs, zs))
mesh_radius_yz = max(math.hypot(y, z) for y, z in zip(ys, zs))
conservative_mesh_radius = max(mesh_radius_xy, mesh_radius_xz, mesh_radius_yz)

rows = []
orbit_radii = []
clearances = []
for idx, (x, y, z) in enumerate(waypoints):
    radius = math.hypot(x - cx, y - cy)
    clearance = radius - conservative_mesh_radius
    rows.append((idx, x, y, z, radius, clearance))
    if idx > 0:
        orbit_radii.append(radius)
        clearances.append(clearance)

with open(waypoint_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["index", "ned_x", "ned_y", "ned_z", "radius_xy_m", "conservative_clearance_m"])
    for row in rows:
        idx, x, y, z, radius, clearance = row
        writer.writerow([idx, f"{x:.6f}", f"{y:.6f}", f"{z:.6f}", f"{radius:.6f}", f"{clearance:.6f}"])

min_orbit_radius = min(orbit_radii) if orbit_radii else 0.0
max_orbit_radius = max(orbit_radii) if orbit_radii else 0.0
min_clearance_observed = min(clearances) if clearances else -conservative_mesh_radius
accepted = min_clearance_observed >= min_clearance

print("scope=wind_orbit_clearance_static_audit")
print(f"decision={'accepted_wind_orbit_clearance_static_audit' if accepted else 'rejected_wind_orbit_clearance_static_audit'}")
print(f"reason={'orbit_clearance_above_static_threshold' if accepted else 'orbit_clearance_below_static_threshold'}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print(f"launch_path={launch_path}")
print(f"mesh_path={mesh_path}")
print("clearance_model=conservative_max_collada_coordinate_plane_radius")
print(f"mesh_radius_xy_m={mesh_radius_xy:.6f}")
print(f"mesh_radius_xz_m={mesh_radius_xz:.6f}")
print(f"mesh_radius_yz_m={mesh_radius_yz:.6f}")
print(f"conservative_mesh_radius_m={conservative_mesh_radius:.6f}")
print(f"orbit_waypoint_count={max(0, len(waypoints) - 1)}")
print(f"min_orbit_radius_m={min_orbit_radius:.6f}")
print(f"max_orbit_radius_m={max_orbit_radius:.6f}")
print(f"min_clearance_m={min_clearance_observed:.6f}")
print(f"required_min_clearance_m={min_clearance:.6f}")
print(f"waypoint_csv={waypoint_csv}")

if not accepted:
    raise SystemExit(2)
PY

grep -q '^decision=accepted_wind_orbit_clearance_static_audit$' "${SUMMARY_FILE}"

echo "Wind orbit clearance static audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Waypoint CSV: ${WAYPOINT_CSV}"
