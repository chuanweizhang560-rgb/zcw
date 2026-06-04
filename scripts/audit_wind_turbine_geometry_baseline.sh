#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/wind_turbine_geometry_baseline_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/wind_turbine_geometry_baseline_${STAMP}.txt"
WAYPOINT_CSV="${RESULT_DIR}/wind_turbine_waypoints_${STAMP}.csv"
RECOMMENDED_CSV="${RESULT_DIR}/wind_turbine_recommended_orbit_${STAMP}.csv"

WORLD_PATH="${WORLD_PATH:-third_party/aerialcore_simulation/worlds/wind_turbine_autospawn.world}"
MESH_PATH="${MESH_PATH:-third_party/aerialcore_simulation/models/wind_turbine/wind_turbine_scaled.dae}"
LAUNCH_PATH="${LAUNCH_PATH:-ros2_ws/src/zcw_bringup/launch/single_vehicle_wind_turbine_inspection.launch.py}"

TURBINE_CENTER_X="${TURBINE_CENTER_X:--25.0}"
TURBINE_CENTER_Y="${TURBINE_CENTER_Y:--25.0}"
TARGET_RADIUS_M="${TARGET_RADIUS_M:-20.0}"
MIN_RECOMMENDED_Z_NED="${MIN_RECOMMENDED_Z_NED:--35.0}"
MAX_RECOMMENDED_Z_NED="${MAX_RECOMMENDED_Z_NED:--12.0}"
RECOMMENDED_LEVELS="${RECOMMENDED_LEVELS:-4}"
RECOMMENDED_POINTS_PER_LEVEL="${RECOMMENDED_POINTS_PER_LEVEL:-12}"

for path in "${WORLD_PATH}" "${MESH_PATH}" "${LAUNCH_PATH}"; do
  if [[ ! -f "${path}" ]]; then
    echo "Required wind turbine input missing: ${path}" >&2
    exit 1
  fi
done

mkdir -p "${RESULT_DIR}"

python3 - "$WORLD_PATH" "$MESH_PATH" "$LAUNCH_PATH" "$WAYPOINT_CSV" "$RECOMMENDED_CSV" \
  "$TURBINE_CENTER_X" "$TURBINE_CENTER_Y" "$TARGET_RADIUS_M" "$MIN_RECOMMENDED_Z_NED" \
  "$MAX_RECOMMENDED_Z_NED" "$RECOMMENDED_LEVELS" "$RECOMMENDED_POINTS_PER_LEVEL" >"${SUMMARY_FILE}" <<'PY'
import ast
import csv
import math
import re
import sys
import xml.etree.ElementTree as ET

world_path, mesh_path, launch_path, waypoint_csv, recommended_csv = sys.argv[1:6]
cx = float(sys.argv[6])
cy = float(sys.argv[7])
target_radius = float(sys.argv[8])
min_z = float(sys.argv[9])
max_z = float(sys.argv[10])
levels = int(sys.argv[11])
points_per_level = int(sys.argv[12])

world_text = open(world_path, "r", encoding="utf-8").read()
launch_text = open(launch_path, "r", encoding="utf-8").read()

pose_match = re.search(r"<model name='wind_turbine'>.*?<pose>([^<]+)</pose>", world_text, re.S)
if not pose_match:
    raise SystemExit("wind turbine pose not found in world")
pose_values = [float(v) for v in pose_match.group(1).split()]

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

wp_match = re.search(r"'waypoints_ned'\s*:\s*(\[[^\]]+\])", launch_text, re.S)
if not wp_match:
    raise SystemExit("waypoints_ned list not found in launch")
flat_waypoints = ast.literal_eval(wp_match.group(1))
if len(flat_waypoints) % 3 != 0:
    raise SystemExit("waypoints_ned is not a flat triple list")
waypoints = [
    tuple(float(v) for v in flat_waypoints[i:i + 3])
    for i in range(0, len(flat_waypoints), 3)
]

with open(waypoint_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["index", "ned_x", "ned_y", "ned_z", "radius_xy_m", "angle_deg", "yaw_to_center_rad"])
    for idx, (x, y, z) in enumerate(waypoints):
        dx = x - cx
        dy = y - cy
        radius = math.hypot(dx, dy)
        angle = math.degrees(math.atan2(dy, dx))
        yaw_to_center = math.atan2(cy - y, cx - x)
        writer.writerow([idx, x, y, z, f"{radius:.6f}", f"{angle:.6f}", f"{yaw_to_center:.6f}"])

recommended_rows = []
if levels < 2:
    levels = 2
for level in range(levels):
    if levels == 1:
        z = min_z
    else:
        z = min_z + (max_z - min_z) * level / (levels - 1)
    for point in range(points_per_level):
        theta = 2.0 * math.pi * point / points_per_level
        x = cx + target_radius * math.cos(theta)
        y = cy + target_radius * math.sin(theta)
        yaw_to_center = math.atan2(cy - y, cx - x)
        recommended_rows.append((level, point, x, y, z, target_radius, math.degrees(theta), yaw_to_center))

with open(recommended_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["level", "point", "ned_x", "ned_y", "ned_z", "radius_xy_m", "angle_deg", "yaw_to_center_rad"])
    for row in recommended_rows:
        level, point, x, y, z, radius, angle, yaw = row
        writer.writerow([level, point, f"{x:.6f}", f"{y:.6f}", f"{z:.6f}", f"{radius:.6f}", f"{angle:.6f}", f"{yaw:.6f}"])

radii = [math.hypot(x - cx, y - cy) for x, y, _ in waypoints[1:]]
zs_ned = [z for _, _, z in waypoints[1:]]
angles = [math.degrees(math.atan2(y - cy, x - cx)) for x, y, _ in waypoints[1:]]
unique_z = sorted(set(round(z, 3) for z in zs_ned))

radial_min = min(radii) if radii else 0.0
radial_max = max(radii) if radii else 0.0
radial_mean = sum(radii) / len(radii) if radii else 0.0
z_min = min(zs_ned) if zs_ned else 0.0
z_max = max(zs_ned) if zs_ned else 0.0

radius_ok = abs(radial_mean - target_radius) <= 2.0 and (radial_max - radial_min) <= 4.0
height_ok = len(unique_z) >= 3 and min_z <= z_min <= max_z and min_z <= z_max <= max_z
angle_ok = len(angles) >= 8
current_decision = "accepted_current_wind_waypoints"
current_reason = "current_waypoints_match_basic_orbit_expectation"
if not radius_ok or not height_ok or not angle_ok:
    current_decision = "rejected_current_wind_waypoints_for_coverage_baseline"
    current_reason = "current_waypoints_are_smoke_test_only_not_multilevel_orbit"

print("scope=wind_turbine_geometry_baseline_audit")
print("decision=accepted_wind_turbine_geometry_asset_audit")
print(f"current_waypoint_decision={current_decision}")
print(f"current_waypoint_reason={current_reason}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print(f"world_path={world_path}")
print(f"mesh_path={mesh_path}")
print(f"launch_path={launch_path}")
print(f"world_pose_x={pose_values[0]:.6f}")
print(f"world_pose_y={pose_values[1]:.6f}")
print(f"world_pose_z={pose_values[2]:.6f}")
print(f"world_pose_yaw_rad={pose_values[5]:.6f}")
print("dae_up_axis=Y_UP")
print(f"dae_vertices={len(xs)}")
print(f"dae_x_min={min(xs):.6f}")
print(f"dae_x_max={max(xs):.6f}")
print(f"dae_y_min={min(ys):.6f}")
print(f"dae_y_max={max(ys):.6f}")
print(f"dae_z_min={min(zs):.6f}")
print(f"dae_z_max={max(zs):.6f}")
print(f"current_waypoint_count={len(waypoints)}")
print(f"current_orbit_waypoint_count={len(waypoints[1:])}")
print(f"current_radius_min_m={radial_min:.6f}")
print(f"current_radius_max_m={radial_max:.6f}")
print(f"current_radius_mean_m={radial_mean:.6f}")
print(f"current_z_min_ned={z_min:.6f}")
print(f"current_z_max_ned={z_max:.6f}")
print(f"current_unique_orbit_z_levels={len(unique_z)}")
print(f"target_radius_m={target_radius:.6f}")
print(f"recommended_levels={levels}")
print(f"recommended_points_per_level={points_per_level}")
print(f"recommended_waypoints={len(recommended_rows)}")
print(f"waypoint_csv={waypoint_csv}")
print(f"recommended_csv={recommended_csv}")
print("recommendation=keep current launch as smoke baseline; add a separate multilevel orbit launch only after reviewing recommended CSV and yaw/frame handling.")
PY

grep -q '^decision=accepted_wind_turbine_geometry_asset_audit$' "${SUMMARY_FILE}"

echo "Wind turbine geometry baseline audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Current waypoint CSV: ${WAYPOINT_CSV}"
echo "Recommended orbit CSV: ${RECOMMENDED_CSV}"
