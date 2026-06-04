#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${RESULT_ROOT:-${ROOT_DIR}/data/results}"
RESULT_DIR="${RESULT_ROOT}/wind_turbine_multilevel_orbit_launch_${STAMP}"
SUMMARY_FILE="${RESULT_DIR}/wind_turbine_multilevel_orbit_launch_${STAMP}.txt"
WAYPOINT_CSV="${RESULT_DIR}/wind_turbine_multilevel_orbit_launch_${STAMP}.csv"

LAUNCH_PATH="${LAUNCH_PATH:-ros2_ws/src/zcw_bringup/launch/single_vehicle_wind_turbine_multilevel_orbit.launch.py}"
TURBINE_CENTER_X="${TURBINE_CENTER_X:--25.0}"
TURBINE_CENTER_Y="${TURBINE_CENTER_Y:--25.0}"
EXPECTED_RADIUS_M="${EXPECTED_RADIUS_M:-20.0}"
EXPECTED_LEVELS="${EXPECTED_LEVELS:-4}"
EXPECTED_POINTS_PER_LEVEL="${EXPECTED_POINTS_PER_LEVEL:-12}"
EXPECTED_TAKEOFF_WAYPOINTS="${EXPECTED_TAKEOFF_WAYPOINTS:-1}"
RADIUS_TOLERANCE_M="${RADIUS_TOLERANCE_M:-0.01}"
YAW_TOLERANCE_RAD="${YAW_TOLERANCE_RAD:-0.001}"

if [[ ! -f "${LAUNCH_PATH}" ]]; then
  echo "Required launch file missing: ${LAUNCH_PATH}" >&2
  exit 1
fi

mkdir -p "${RESULT_DIR}"

python3 - "$LAUNCH_PATH" "$WAYPOINT_CSV" "$TURBINE_CENTER_X" "$TURBINE_CENTER_Y" \
  "$EXPECTED_RADIUS_M" "$EXPECTED_LEVELS" "$EXPECTED_POINTS_PER_LEVEL" \
  "$EXPECTED_TAKEOFF_WAYPOINTS" "$RADIUS_TOLERANCE_M" "$YAW_TOLERANCE_RAD" >"${SUMMARY_FILE}" <<'PY'
import ast
import csv
import math
import sys

launch_path, waypoint_csv = sys.argv[1:3]
cx = float(sys.argv[3])
cy = float(sys.argv[4])
expected_radius = float(sys.argv[5])
expected_levels = int(sys.argv[6])
expected_points_per_level = int(sys.argv[7])
expected_takeoff_waypoints = int(sys.argv[8])
radius_tolerance = float(sys.argv[9])
yaw_tolerance = float(sys.argv[10])

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

flat_waypoints, yaws = namespace["_orbit_waypoints"](
    center_x=cx,
    center_y=cy,
    radius=expected_radius,
)

if len(flat_waypoints) % 3 != 0:
    raise SystemExit("waypoints are not a flat list of NED triples")

waypoints = [
    tuple(float(v) for v in flat_waypoints[i:i + 3])
    for i in range(0, len(flat_waypoints), 3)
]
yaws = [float(v) for v in yaws]

orbit_waypoints = waypoints[expected_takeoff_waypoints:]
orbit_yaws = yaws[expected_takeoff_waypoints:]
expected_orbit_count = expected_levels * expected_points_per_level
expected_total_count = expected_takeoff_waypoints + expected_orbit_count

rows = []
radius_errors = []
yaw_errors = []
levels = sorted(set(round(z, 6) for _, _, z in orbit_waypoints))

for idx, (x, y, z) in enumerate(waypoints):
    dx = x - cx
    dy = y - cy
    radius = math.hypot(dx, dy)
    expected_yaw = math.atan2(cy - y, cx - x)
    yaw = yaws[idx] if idx < len(yaws) else float("nan")
    yaw_error = abs(math.atan2(math.sin(yaw - expected_yaw), math.cos(yaw - expected_yaw)))
    if idx >= expected_takeoff_waypoints:
        radius_errors.append(abs(radius - expected_radius))
        yaw_errors.append(yaw_error)
    rows.append((idx, x, y, z, radius, yaw, expected_yaw, yaw_error))

with open(waypoint_csv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow([
        "index",
        "ned_x",
        "ned_y",
        "ned_z",
        "radius_xy_m",
        "yaw_rad",
        "expected_yaw_to_center_rad",
        "yaw_error_rad",
    ])
    for row in rows:
        idx, x, y, z, radius, yaw, expected_yaw, yaw_error = row
        writer.writerow([
            idx,
            f"{x:.6f}",
            f"{y:.6f}",
            f"{z:.6f}",
            f"{radius:.6f}",
            f"{yaw:.6f}",
            f"{expected_yaw:.6f}",
            f"{yaw_error:.6f}",
        ])

waypoint_count_ok = len(waypoints) == expected_total_count
yaw_count_ok = len(yaws) == len(waypoints)
level_count_ok = len(levels) == expected_levels
orbit_count_ok = len(orbit_waypoints) == expected_orbit_count
radius_ok = bool(radius_errors) and max(radius_errors) <= radius_tolerance
yaw_ok = bool(yaw_errors) and max(yaw_errors) <= yaw_tolerance

decision = "accepted_wind_turbine_multilevel_orbit_static_audit"
reason = "orbit_launch_matches_static_geometry_contract"
if not all([waypoint_count_ok, yaw_count_ok, level_count_ok, orbit_count_ok, radius_ok, yaw_ok]):
    decision = "rejected_wind_turbine_multilevel_orbit_static_audit"
    reason = "orbit_launch_does_not_match_static_geometry_contract"

print("scope=wind_turbine_multilevel_orbit_launch_static_audit")
print(f"decision={decision}")
print(f"reason={reason}")
print("starts_ros=false")
print("starts_px4=false")
print("starts_gazebo=false")
print("starts_rviz=false")
print("starts_offboard=false")
print("arms=false")
print("publishes_fmu_in=false")
print(f"launch_path={launch_path}")
print(f"turbine_center_x={cx:.6f}")
print(f"turbine_center_y={cy:.6f}")
print(f"expected_radius_m={expected_radius:.6f}")
print(f"expected_levels={expected_levels}")
print(f"expected_points_per_level={expected_points_per_level}")
print(f"expected_takeoff_waypoints={expected_takeoff_waypoints}")
print(f"waypoint_count={len(waypoints)}")
print(f"expected_total_waypoint_count={expected_total_count}")
print(f"orbit_waypoint_count={len(orbit_waypoints)}")
print(f"expected_orbit_waypoint_count={expected_orbit_count}")
print(f"yaw_count={len(yaws)}")
print(f"unique_orbit_z_levels={len(levels)}")
print("orbit_z_levels=" + ",".join(f"{z:.6f}" for z in levels))
print(f"max_radius_error_m={max(radius_errors) if radius_errors else float('nan'):.6f}")
print(f"radius_tolerance_m={radius_tolerance:.6f}")
print(f"max_yaw_error_rad={max(yaw_errors) if yaw_errors else float('nan'):.6f}")
print(f"yaw_tolerance_rad={yaw_tolerance:.6f}")
print(f"waypoint_count_ok={str(waypoint_count_ok).lower()}")
print(f"yaw_count_ok={str(yaw_count_ok).lower()}")
print(f"level_count_ok={str(level_count_ok).lower()}")
print(f"orbit_count_ok={str(orbit_count_ok).lower()}")
print(f"radius_ok={str(radius_ok).lower()}")
print(f"yaw_ok={str(yaw_ok).lower()}")
print(f"waypoint_csv={waypoint_csv}")

if decision.startswith("rejected_"):
    raise SystemExit(2)
PY

grep -q '^decision=accepted_wind_turbine_multilevel_orbit_static_audit$' "${SUMMARY_FILE}"

echo "Wind turbine multilevel orbit launch static audit completed."
echo "Summary: ${SUMMARY_FILE}"
echo "Waypoint CSV: ${WAYPOINT_CSV}"
