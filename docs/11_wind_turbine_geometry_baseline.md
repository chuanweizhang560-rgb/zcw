# Wind Turbine Geometry Baseline

This document records the current wind turbine inspection baseline and the next safe upgrade path.

It does not change PX4 control behavior.

## 1. Current Inputs

Open-source asset:

- upstream: `third_party/aerialcore_simulation`
- world: `third_party/aerialcore_simulation/worlds/wind_turbine_autospawn.world`
- mesh: `third_party/aerialcore_simulation/models/wind_turbine/wind_turbine_scaled.dae`
- license record: `OPEN_SOURCE_AUDIT.md`

Current launch:

- `ros2_ws/src/zcw_bringup/launch/single_vehicle_wind_turbine_inspection.launch.py`
- executable: `offboard_waypoint_sequence`
- behavior: fixed NED waypoint smoke baseline

## 2. Audit Command

```bash
scripts/audit_wind_turbine_geometry_baseline.sh
```

The audit is allowed to:

- parse the open-source AerialCore wind turbine world.
- parse the local DAE vertex positions for rough asset bounds.
- parse the current launch waypoint list.
- write CSV and summary files under `data/results/`.

The audit is not allowed to:

- start ROS, PX4, Gazebo or RViz.
- start Offboard.
- arm.
- publish `/fmu/in/*`.
- create a new controller.

## 3. Why The Current Baseline Is Not Enough

The current wind turbine launch is useful as a PX4 movement smoke test, but it is not yet a coverage baseline:

- it uses one orbit height after takeoff.
- it does not encode yaw-to-center in the PX4 setpoint node.
- it has only a small number of orbit points.
- it does not separate tower, nacelle and blade inspection bands.

Latest audit evidence:

- summary: `data/results/wind_turbine_geometry_baseline_20260604_131304/wind_turbine_geometry_baseline_20260604_131304.txt`
- current waypoint CSV: `data/results/wind_turbine_geometry_baseline_20260604_131304/wind_turbine_waypoints_20260604_131304.csv`
- recommended orbit CSV: `data/results/wind_turbine_geometry_baseline_20260604_131304/wind_turbine_recommended_orbit_20260604_131304.csv`

Latest result:

```text
decision=accepted_wind_turbine_geometry_asset_audit
current_waypoint_decision=rejected_current_wind_waypoints_for_coverage_baseline
current_waypoint_reason=current_waypoints_are_smoke_test_only_not_multilevel_orbit
world_pose_x=-25.000000
world_pose_y=-25.000000
world_pose_yaw_rad=0.261800
dae_vertices=4802
dae_x_min=-0.847701
dae_x_max=1.883050
dae_y_min=-6.377210
dae_y_max=6.446130
dae_z_min=0.351190
dae_z_max=11.803300
current_orbit_waypoint_count=5
current_radius_mean_m=20.000000
current_unique_orbit_z_levels=1
recommended_levels=4
recommended_points_per_level=12
recommended_waypoints=48
```

The next upgrade should be a separate multilevel orbit launch, not an overwrite of the existing smoke launch.

## 4. Required Next Review

Before connecting a new wind turbine orbit to PX4:

1. Review the generated recommended orbit CSV.
2. Decide whether yaw should be added to `offboard_waypoint_sequence` or handled by a separate PX4-supported yaw setpoint baseline.
3. Keep the existing smoke launch unchanged until the multilevel orbit has its own audit and screenshot.
4. Capture real Gazebo GUI evidence after the new launch exists.

The recommended CSV is a planning artifact, not an approved active mission.

## 5. Current Decision

Keep `single_vehicle_wind_turbine_inspection.launch.py` as the already verified movement smoke baseline.

The next implementation node is a separate wind turbine multilevel orbit launch:

- launch: `ros2_ws/src/zcw_bringup/launch/single_vehicle_wind_turbine_multilevel_orbit.launch.py`
- verification wrapper: `scripts/verify_wind_turbine_multilevel_orbit.sh`
- setpoint layer: existing PX4 official-example-derived `offboard_waypoint_sequence`
- yaw handling: optional `yaws_rad`; old launches keep yaw `0.0` by default

This launch still needs its own headless verification and real Gazebo screenshot evidence before it can replace the old wind turbine smoke baseline in reports.

## 6. Multilevel Orbit Headless Result

Latest headless verification:

- command: `scripts/verify_wind_turbine_multilevel_orbit.sh`
- agent log: `data/logs/waypoints_agent_20260604_132205.log`
- PX4 log: `data/logs/waypoints_px4_20260604_132205.log`
- waypoint log: `data/logs/waypoints_control_20260604_132205.log`
- vehicle status: `data/logs/waypoints_vehicle_status_20260604_132205.log`
- vehicle local position: `data/logs/waypoints_vehicle_local_position_20260604_132205.log`

Observed result:

```text
PX4 Offboard waypoint baseline verified.
arming_state: 2
nav_state: 14
last_observed_advancement: waypoint 29 [-35.00, -7.68, -19.67], yaw -1.05
last_observed_local_position: x=-31.930338, y=-6.575594, z=-19.689199
```

The first sandboxed run failed before PX4 startup because Micro XRCE-DDS could not bind UDP `8888`. The same script passed when run outside the restricted network namespace. This should be treated as an execution-environment issue, not a wind launch failure.

Remaining evidence gap:

- Target-framed Gazebo GUI screenshot for the multilevel orbit is still pending.

GUI capture entry:

```bash
scripts/capture_wind_turbine_multilevel_orbit_gui.sh
```

Latest GUI motion evidence:

- screenshot: `data/screenshots/wind_turbine_multilevel_orbit_gui_20260604_134640.png`
- window id: `data/screenshots/wind_turbine_multilevel_orbit_gui_20260604_134640.png.window_id.txt`
- agent log: `data/logs/wind_multilevel_gui_agent_20260604_134640.log`
- PX4 log: `data/logs/wind_multilevel_gui_px4_20260604_134640.log`
- offboard log: `data/logs/wind_multilevel_gui_offboard_20260604_134640.log`
- vehicle status: `data/logs/wind_multilevel_gui_vehicle_status_20260604_134640.log`
- vehicle local position: `data/logs/wind_multilevel_gui_vehicle_local_position_20260604_134640.log`

Observed:

```text
gazebo_window_id=0x5c00010
screenshot_size=2560x1403
advancements=8
arming_state: 2
nav_state: 14
local_position: x=-42.167988, y=-35.401360, z=-35.040619
```

Visual audit:

- accepted as real Gazebo GUI motion evidence.
- not accepted as target-framed inspection evidence because the wind turbine target is not visible in the screenshot.
