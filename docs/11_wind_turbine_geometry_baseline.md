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

This launch now has static geometry audit, headless Offboard verification and real Gazebo GUI motion evidence. The old wind turbine smoke launch remains useful as a minimal movement check, but the multilevel launch is the current wind turbine rule baseline for geometry-oriented reporting.

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

User-confirmed visual boundary:

- The real Gazebo GUI motion screenshot is accepted for the current wind turbine multilevel orbit evidence.
- Per user feedback on 2026-06-04 13:54 CST, no further same-frame wind turbine screenshot is required for this node.

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
- target same-frame evidence is not pursued further per user confirmation.

## 8. Multilevel Orbit Static Geometry Acceptance

Command:

```bash
scripts/audit_wind_turbine_multilevel_orbit_launch.sh
```

This audit is read-only. It parses `single_vehicle_wind_turbine_multilevel_orbit.launch.py` and does not start ROS, PX4, Gazebo, RViz, Offboard, arm, or publish `/fmu/in/*`.

Latest evidence:

- summary: `data/results/wind_turbine_multilevel_orbit_launch_20260604_135831/wind_turbine_multilevel_orbit_launch_20260604_135831.txt`
- waypoint CSV: `data/results/wind_turbine_multilevel_orbit_launch_20260604_135831/wind_turbine_multilevel_orbit_launch_20260604_135831.csv`

Observed result:

```text
decision=accepted_wind_turbine_multilevel_orbit_static_audit
reason=orbit_launch_matches_static_geometry_contract
waypoint_count=49
orbit_waypoint_count=48
yaw_count=49
unique_orbit_z_levels=4
orbit_z_levels=-35.000000,-27.333333,-19.666667,-12.000000
max_radius_error_m=0.000000
max_yaw_error_rad=0.000000
waypoint_count_ok=true
yaw_count_ok=true
level_count_ok=true
orbit_count_ok=true
radius_ok=true
yaw_ok=true
```

Decision:

- accepted as the current wind turbine static geometry baseline.
- still a rule baseline, not a learned policy.
- does not change any cable Phase B active boundary.

## 9. 15m Close-Orbit Candidate

Motivation:

- The 20m multilevel orbit is safe and accepted as the default rule baseline.
- Depth useful-return audit shows many wind frames are dominated by far/saturated depth values.
- A closer orbit may improve observation quality, but it should be introduced as a separate candidate rather than replacing the accepted 20m baseline.

Candidate launch:

- `ros2_ws/src/zcw_bringup/launch/single_vehicle_wind_turbine_multilevel_orbit_r15.launch.py`

Static audit command:

```bash
LAUNCH_PATH=ros2_ws/src/zcw_bringup/launch/single_vehicle_wind_turbine_multilevel_orbit_r15.launch.py \
EXPECTED_RADIUS_M=15.0 \
scripts/audit_wind_turbine_multilevel_orbit_launch.sh
```

Static evidence:

- summary: `data/results/wind_turbine_multilevel_orbit_launch_20260605_143524/wind_turbine_multilevel_orbit_launch_20260605_143524.txt`
- waypoint CSV: `data/results/wind_turbine_multilevel_orbit_launch_20260605_143524/wind_turbine_multilevel_orbit_launch_20260605_143524.csv`

Observed static result:

```text
decision=accepted_wind_turbine_multilevel_orbit_static_audit
expected_radius_m=15.000000
waypoint_count=49
orbit_waypoint_count=48
yaw_count=49
unique_orbit_z_levels=4
max_radius_error_m=0.000000
max_yaw_error_rad=0.000000
```

Depth useful-return evidence:

- summary: `data/results/wind_depth_image_stats_20260605_143754/wind_depth_image_stats_20260605_143754.txt`
- frame CSV: `data/results/wind_depth_image_stats_20260605_143754/depth_image_stats_frames_20260605_143837.csv`

Observed depth result:

```text
decision=accepted_wind_depth_image_stats
launch=single_vehicle_wind_turbine_multilevel_orbit_r15.launch.py
waypoint_advancements=24
mean_useful_ratio=0.11667
max_useful_ratio=0.225683
```

Comparison against 20m baseline:

- 20m multilevel orbit useful depth:
  - `mean_useful_ratio=0.0947751`
  - `max_useful_ratio=0.207139`
- 15m candidate useful depth:
  - `mean_useful_ratio=0.11667`
  - `max_useful_ratio=0.225683`

Decision:

- The 15m candidate improves useful depth return modestly and is worth keeping for further wind observation tests.
- It also has accepted RTAB-Map RGB-D RViz smoke evidence:
  - summary: `data/results/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260605_144439/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260605_144439.txt`
  - screenshot: `data/screenshots/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260605_144439.png`
  - `waypoint_advancements=46`
- It has accepted conservative static clearance evidence:
  - 20m summary: `data/results/wind_orbit_clearance_20260605_145036/wind_orbit_clearance_20260605_145036.txt`
  - 15m summary: `data/results/wind_orbit_clearance_20260605_145042/wind_orbit_clearance_20260605_145042.txt`
  - conservative mesh radius: `11.880407m`
  - 20m minimum clearance: `8.119593m`
  - 15m minimum clearance: `3.119593m`
- It is now the preferred wind-side observation-quality candidate.
- It is not promoted as a final coverage baseline because static clearance is not the same as dynamic collision checking or surface coverage.

Supplemental static re-check on 2026-06-08:

- 20m visibility summary: `data/results/wind_visibility_20m_20260608_105400/wind_orbit_visibility_20260608_105405/wind_orbit_visibility_20260608_105405.txt`
- 15m visibility summary: `data/results/wind_visibility_r15_20260608_105400/wind_orbit_visibility_20260608_105411/wind_orbit_visibility_20260608_105411.txt`
- 20m clearance summary: `data/results/wind_clearance_20m_20260608_105400/wind_orbit_clearance_20260608_105417/wind_orbit_clearance_20260608_105417.txt`
- 15m clearance summary: `data/results/wind_clearance_r15_20260608_105400/wind_orbit_clearance_20260608_105424/wind_orbit_clearance_20260608_105424.txt`
- 20m best_view_frame_fill_ratio: `0.092567`
- 15m best_view_frame_fill_ratio: `0.109478`
- 20m minimum static clearance: `8.119593m`
- 15m minimum static clearance: `3.119593m`

The 2026-06-08 re-check confirms the earlier conclusion: 15m remains the preferred observation-quality candidate, but it is still not final dynamic collision safety or inspection coverage evidence.

Supplemental 15m RTAB-Map RGB-D motion evidence on 2026-06-08:

- command: `OFFBOARD_LAUNCH_FILE=single_vehicle_wind_turbine_multilevel_orbit_r15.launch.py MIN_WAYPOINT_ADVANCEMENTS=8 MOTION_SETTLE_SEC=115 scripts/capture_rtabmap_depth_camera_rgbd_wind_rviz_overlay.sh`
- summary: `data/results/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260608_105840/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260608_105840.txt`
- screenshot: `data/screenshots/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260608_105840.png`
- RTAB-Map log: `data/logs/rtabmap_depth_camera_rgbd_wind_rviz_rtabmap_20260608_105840.log`
- waypoint motion log: `data/logs/rtabmap_depth_camera_rgbd_wind_rviz_offboard_20260608_105840.log`
- `waypoint_advancements=46`
- `rtabmap_ok=true`
- `outputs_ok=true`
- `motion_ok=true`
- `screenshot_ok=1`

Manual screenshot review: RViz Global Status is OK; `Cloud Map` and `Octomap Occupied Space` displays are OK; the screenshot is non-empty and shows localized cloud/octomap structure. This supports 15m as the preferred observation candidate, but still does not prove turbine surface coverage completion.

Supplemental frustum coverage upper-bound audit on 2026-06-09:

- script: `scripts/audit_wind_orbit_frustum_coverage.sh`
- 20m summary: `data/results/wind_frustum_coverage_20m_20260609_000000/wind_orbit_frustum_coverage_20260609_092332.txt`
- 15m summary: `data/results/wind_frustum_coverage_r15_20260609_000000/wind_orbit_frustum_coverage_20260609_092324.txt`
- 20m vertex_coverage_ratio: `1.000000`
- 15m vertex_coverage_ratio: `1.000000`
- 20m double_observed_ratio: `1.000000`
- 15m double_observed_ratio: `1.000000`
- 20m min_band_coverage_ratio_observed: `1.000000`
- 15m min_band_coverage_ratio_observed: `1.000000`

This confirms that the current orbit geometry satisfies a static mesh-vertex frustum upper-bound audit. It is intentionally not a final coverage certificate because it does not model occlusion, surface normals, image texture quality, dynamic collision safety, or useful-depth validity.

Supplemental quality coverage static audit on 2026-06-09:

- script: `scripts/audit_wind_orbit_quality_coverage.sh`
- 20m summary: `data/results/wind_quality_coverage_20m_20260609_000000/wind_orbit_quality_coverage_20260609_093420.txt`
- 15m summary: `data/results/wind_quality_coverage_r15_20260609_000000/wind_orbit_quality_coverage_20260609_093420.txt`
- 20m normal_filtered_coverage_ratio: `0.723701`
- 15m normal_filtered_coverage_ratio: `0.715221`
- 20m normal_filtered_double_observed_ratio: `0.700837`
- 15m normal_filtered_double_observed_ratio: `0.686561`
- 20m min_band_normal_coverage_ratio_observed: `0.613346`
- 15m min_band_normal_coverage_ratio_observed: `0.582924`
- 20m mean_useful_ratio: `0.094775`
- 15m mean_useful_ratio: `0.116670`
- 20m max_useful_ratio: `0.207139`
- 15m max_useful_ratio: `0.225683`

Decision:

- Both the 20m baseline and 15m candidate produce valid offline quality metrics with real wind depth-stat evidence attached.
- The 20m baseline has slightly stronger normal-filtered mesh coverage in this static model.
- The 15m candidate still has stronger useful-depth image returns.
- The current practical decision remains unchanged: keep 20m as the safer accepted baseline, keep 15m as the preferred observation-quality candidate for additional dynamic tests.
- This audit still does not model occlusion, dynamic collision safety, actual image defect recognition or final inspection completion.

Supplemental 15m dynamic orbit audit on 2026-06-09:

- script: `scripts/verify_wind_dynamic_orbit_audit.sh`
- wrapper summary: `data/results/wind_dynamic_orbit_audit_20260609_094838/wind_dynamic_orbit_audit_wrapper_20260609_094838.txt`
- node summary: `data/results/wind_dynamic_orbit_audit_20260609_094838/wind_dynamic_orbit_audit_20260609_094921.txt`
- pose CSV: `data/results/wind_dynamic_orbit_audit_20260609_094838/wind_dynamic_orbit_pose_20260609_094921.csv`
- depth CSV: `data/results/wind_dynamic_orbit_audit_20260609_094838/wind_dynamic_orbit_depth_20260609_094921.csv`
- launch: `single_vehicle_wind_turbine_multilevel_orbit_r15.launch.py`
- waypoint_advancements: `23`
- pose_samples: `350`
- depth_frames: `101`
- min_conservative_clearance_m: `2.8703362146`
- mean_radius_error_m: `0.177446480778`
- max_radius_error_m_observed: `0.462360872702`
- mean_useful_ratio: `0.0854219693785`
- max_useful_ratio: `0.218219339623`

Decision:

- The 15m candidate now has accepted real-motion dynamic audit evidence in headless PX4/Gazebo.
- The audit uses a conservative mesh-radius clearance proxy and does not replace full mesh collision checking.
- It records useful depth during real motion, but it still does not prove final inspection coverage, occlusion-free observation, or defect detection.
- The 15m candidate remains the preferred observation-quality candidate and is now stronger than before, but final promotion still needs a coverage progression audit tied to mesh samples or RViz/Gazebo visual evidence.

Supplemental 15m dynamic coverage progression audit on 2026-06-09:

- script: `scripts/audit_wind_dynamic_coverage_progression.sh`
- summary: `data/results/wind_dynamic_coverage_progression_r15_20260609_000000/wind_dynamic_coverage_progression_20260609_095332.txt`
- progression CSV: `data/results/wind_dynamic_coverage_progression_r15_20260609_000000/wind_dynamic_coverage_progression_20260609_095332.csv`
- band CSV: `data/results/wind_dynamic_coverage_progression_r15_20260609_000000/wind_dynamic_coverage_progression_bands_20260609_095332.csv`
- pose source: `data/results/wind_dynamic_orbit_audit_20260609_094838/wind_dynamic_orbit_pose_20260609_094921.csv`
- pose_samples_used: `350`
- mesh_samples: `9316`
- final_frustum_coverage_ratio: `1.000000`
- final_normal_filtered_coverage_ratio: `0.637935`
- min_band_normal_coverage_ratio_observed: `0.410206`

Decision:

- The accepted 15m real-motion pose CSV now has offline cumulative coverage progression evidence.
- The 35-second segment covers enough normal-filtered samples for a partial dynamic audit, but it is not a full 4-level orbit completion certificate.
- The weakest final band is the top band (`0.410206` normal-filtered), so final wind inspection coverage still needs either a longer full-orbit run or orbit adjustment evidence.
- This audit still omits occlusion and real image defect recognition.

Supplemental longer 15m dynamic orbit and coverage progression on 2026-06-09:

- dynamic wrapper summary: `data/results/wind_dynamic_orbit_audit_20260609_095652/wind_dynamic_orbit_audit_wrapper_20260609_095652.txt`
- dynamic node summary: `data/results/wind_dynamic_orbit_audit_20260609_095652/wind_dynamic_orbit_audit_20260609_095734.txt`
- pose CSV: `data/results/wind_dynamic_orbit_audit_20260609_095652/wind_dynamic_orbit_pose_20260609_095734.csv`
- depth CSV: `data/results/wind_dynamic_orbit_audit_20260609_095652/wind_dynamic_orbit_depth_20260609_095734.csv`
- progression summary: `data/results/wind_dynamic_coverage_progression_r15_full_20260609_000000/wind_dynamic_coverage_progression_20260609_100000.txt`
- progression CSV: `data/results/wind_dynamic_coverage_progression_r15_full_20260609_000000/wind_dynamic_coverage_progression_20260609_100000.csv`
- progression band CSV: `data/results/wind_dynamic_coverage_progression_r15_full_20260609_000000/wind_dynamic_coverage_progression_bands_20260609_100000.csv`
- waypoint_advancements: `48`
- pose_samples: `1200`
- depth_frames: `315`
- min_conservative_clearance_m: `2.72578086707`
- mean_radius_error_m: `0.131602303283`
- max_radius_error_m_observed: `0.481701799685`
- mean_useful_ratio: `0.232852213737`
- max_useful_ratio: `0.423267983491`
- final_normal_filtered_coverage_ratio: `0.688708`
- min_band_normal_coverage_ratio_observed: `0.546614`

Decision:

- The longer 15m run completed all 48 orbit waypoint advancements and is the strongest current wind dynamic evidence.
- Compared with the 35-second partial run, final normal-filtered coverage improved from `0.637935` to `0.688708`, and the weakest band improved from `0.410206` to `0.546614`.
- The result still omits occlusion and image-level inspection quality, so it should be treated as dynamic geometry/sensor-readiness evidence rather than final inspection acceptance.

Supplemental occlusion-aware 15m coverage progression on 2026-06-09:

- setup script: `scripts/setup_geometry_venv.sh`
- audit script: `scripts/audit_wind_occlusion_coverage_progression.sh`
- dependency path: `.venv/geometry`
- mature libraries used: `trimesh==4.12.2`, `rtree==1.4.1`, `pycollada==0.9.3`
- first default attempt with denser sampling was terminated after excessive runtime
- accepted fast summary: `data/results/wind_occlusion_coverage_progression_r15_full_fast_20260609_000000/wind_occlusion_coverage_progression_20260609_103920.txt`
- accepted fast progression CSV: `data/results/wind_occlusion_coverage_progression_r15_full_fast_20260609_000000/wind_occlusion_coverage_progression_20260609_103920.csv`
- accepted fast band CSV: `data/results/wind_occlusion_coverage_progression_r15_full_fast_20260609_000000/wind_occlusion_coverage_progression_bands_20260609_103920.csv`
- pose source: `data/results/wind_dynamic_orbit_audit_20260609_095652/wind_dynamic_orbit_pose_20260609_095734.csv`
- pose_stride: `20`
- face_stride: `8`
- pose_samples_used: `60`
- mesh_samples: `1165`
- ray_tests: `28505`
- final_normal_filtered_coverage_ratio: `0.690129`
- final_occlusion_clear_normal_coverage_ratio: `0.634335`
- min_band_occlusion_clear_normal_ratio_observed: `0.534884`

Decision:

- The project now has a mature-library occlusion-aware wind coverage audit path.
- The current accepted occlusion result is intentionally sampled for runtime control, so it is evidence of method readiness and approximate coverage, not dense final coverage certification.
- The result still does not perform image-level defect detection or guarantee photometric quality.

## 10. Static Frustum/Frame-Fill Visibility Audit

Purpose:

- The clearance audit only checks geometry margin.
- The useful-depth audit shows whether the camera returns non-saturated depth.
- This visibility audit adds a read-only upper-bound check for how much of the turbine can be framed by the orbit viewpoints.
- It does not start ROS, PX4, Gazebo, RViz, Offboard, arm, or publish `/fmu/in/*`.

Audit command:

```bash
scripts/audit_wind_orbit_visibility.sh
```

Compared candidates:

- default 20m orbit:
  - summary: `data/results/wind_visibility_20m_20260608_105400/wind_orbit_visibility_20260608_105405/wind_orbit_visibility_20260608_105405.txt`
- 15m close orbit:
  - summary: `data/results/wind_visibility_r15_20260608_105400/wind_orbit_visibility_20260608_105411/wind_orbit_visibility_20260608_105411.txt`

Observed result:

```text
20m best_view_frame_fill_ratio=0.092567
15m best_view_frame_fill_ratio=0.109478
20m union_visible_ratio=1.000000
15m union_visible_ratio=1.000000
```

Decision:

- The 15m candidate keeps the full-view upper bound and improves frame fill ratio over the 20m baseline.
- This makes 15m the stronger wind observation candidate for later coverage or SLAM checks.
- The result is still a static upper bound, not a proof of dynamic collision safety or full inspection coverage.

## 11. Multi-Level Slow-Loop Rule-Baseline Acceptance

Purpose:

- Aggregate the latest single-vehicle wind evidence into one auditable rule-baseline decision.
- Keep the boundary explicit: this is wind-only evidence. It does not approve cable active bridge, multi-vehicle active control, image-level defect detection, or final inspection coverage.
- The audit itself is offline and does not start ROS, PX4, Gazebo, RViz, Offboard, arm, or publish PX4 input topics.

Audit command:

```bash
scripts/audit_wind_rule_baseline_acceptance.sh
```

Latest accepted result:

- summary: `data/results/wind_rule_baseline_acceptance_20260616_085445/wind_rule_baseline_acceptance_20260616_085445.txt`
- source capture: `data/results/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260615_091712/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260615_091712.txt`
- dynamic coverage: `data/results/wind_dynamic_coverage_multilevel_slow_loop_20260615_091712/wind_dynamic_coverage_progression_20260615_092327.txt`
- occlusion coverage: `data/results/wind_occlusion_coverage_multilevel_slow_loop_very_fast_20260615_091712/wind_occlusion_coverage_progression_20260615_092417.txt`
- loop closure: `data/results/rtabmap_loop_closure_evidence_20260615_093152/rtabmap_loop_closure_evidence_20260615_093152.txt`
- mapping boundary: `data/results/rtabmap_wind_capture_output_boundary_20260615_093222/rtabmap_wind_capture_output_boundary_20260615_093222.txt`

Accepted fields:

```text
decision=accepted_wind_rule_baseline_acceptance
capture_ok=true
pose_ok=true
dynamic_ok=true
occlusion_ok=true
loop_ok=true
mapping_boundary_ok=true
p3d_ate_ok=true
px4_crosscheck_ok=true
waypoint_advancements=145
valid_pose_samples=43611
min_conservative_clearance_m=1.688958000
final_normal_filtered_coverage_ratio=0.733899000
min_band_normal_coverage_ratio_observed=0.595682000
final_occlusion_clear_normal_coverage_ratio=0.708904000
min_band_occlusion_clear_normal_ratio_observed=0.593750000
rtabmap_node_count=205
official_global_closure_links=6
claims_wind_rule_baseline_acceptance_pass=true
```

Decision:

- The 15m multi-level slow-loop is now the strongest accepted single-vehicle wind rule-baseline candidate.
- The older 20m orbit remains useful as a simple conservative baseline.
- The accepted aggregate still does not claim final defect inspection or dense final coverage certification.
