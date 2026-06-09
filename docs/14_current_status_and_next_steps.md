# Current Status And Next Steps

This document is the current handoff summary for the repository.

It does not approve cable Phase B active control. It records what is currently runnable, what evidence exists, and what remains open.

## 1. Global Boundary

- Stack remains Gazebo 11 + ROS 2 Humble + PX4 SITL.
- The repository scope remains wind turbine inspection and cable inspection only.
- The project still follows the rule-baseline-first path.
- Mature upstream components remain preferred. Current SLAM baseline is RTAB-Map RGB-D from ROS Humble packages.
- Cable Phase B active bridge is still not implemented and not approved.
- Cable lookahead/gate outputs are still dry-run only.

## 2. Cable Status

Current cable geometry candidate:

- offset path: `data/results/catenary_offset_yz_zbin2_step5_20260608_000000/depth_camera_motion_catenary_offset_yz_zbin2_step5_offset_path_20260608_085655.csv`
- lookahead targets: `data/results/lookahead_target_step5_20m_strict_20260608_090000/depth_camera_motion_lookahead_step5_20m_strict_targets_20260608_085945.csv`
- group: `y8_z20`

Accepted evidence:

- geometry and Frenet consistency accepted.
- ROS topic and RViz overlay accepted.
- safety monitor and dry-run candidate accepted.
- Phase A bridge dry-run isolation accepted.
- PX4/Gazebo offboard gate dry-run accepted with `phase_b_allowed=false`.
- gate RViz/debug overlay accepted.
- dry-run readiness accepted.

Important boundary:

- `/fmu/in/*` topics may appear when PX4 uXRCE-DDS is running, but current cable gate evidence requires their publisher count to be `0`.
- No cable active bridge exists.
- No cable lookahead/gate setpoint is published to PX4 active input topics.

Next cable work:

- Do not implement active bridge without explicit approval.
- Useful safe next nodes are better dry-run evidence, stricter coordinate-frame audits, or offline tracking/coverage analysis.

## 3. Wind Status

Current wind rule candidates:

- default accepted baseline: `single_vehicle_wind_turbine_multilevel_orbit.launch.py` at 20m radius.
- preferred observation candidate: `single_vehicle_wind_turbine_multilevel_orbit_r15.launch.py` at 15m radius.

Accepted evidence:

- multilevel orbit static geometry audit accepted.
- headless and GUI motion evidence accepted.
- 15m useful-depth audit accepted and modestly better than 20m.
- 15m static clearance accepted: minimum static clearance `3.119593m`.
- 15m static visibility accepted: best frame-fill ratio `0.109478`, better than 20m `0.092567`.
- 15m RTAB-Map RGB-D motion-backed RViz evidence accepted.
- static mesh-vertex frustum coverage upper-bound accepted for both 20m and 15m.
- static quality coverage audit accepted for both 20m and 15m, combining frustum, mesh surface-normal/view-angle filtering and prior useful-depth stats.
- 15m short dynamic orbit audit accepted with real PX4/Gazebo motion, 350 pose samples, 101 depth frames, `final_normal_filtered_coverage_ratio=0.637935`.
- 15m longer dynamic orbit audit accepted with all 48 waypoint advancements, 1200 pose samples, 315 depth frames, `min_conservative_clearance_m=2.72578086707`, `mean_useful_ratio=0.232852213737`, `final_normal_filtered_coverage_ratio=0.688708`, weakest band `0.546614`.
- 15m occlusion-aware fast progression audit accepted using `trimesh`/`rtree` ray intersection, with `pose_stride=20`, `face_stride=8`, `ray_tests=28505`, `final_occlusion_clear_normal_coverage_ratio=0.634335`, weakest band `0.534884`.

Important boundary:

- Static visibility/frustum coverage does not model occlusion or dynamic collision.
- The newer quality coverage audit adds surface-normal/view-angle filtering and useful-depth linkage, but still does not model occlusion, actual visual defect recognition, or dynamic collision safety.
- RTAB-Map screenshots are SLAM plumbing evidence, not inspection coverage certificates.
- 15m is preferred for observation experiments, but not final coverage readiness.

Next wind work:

- Add a denser occlusion-aware audit if runtime permits, or keep the fast audit as approximate method evidence.
- Add image-level quality/defect-detection integration only through mature open-source models or clearly separated future work.
- Define explicit wind inspection acceptance thresholds before claiming completion.
- Capture a fresh wind dynamic RViz/Gazebo screenshot only if it adds new evidence beyond the existing motion/RViz screenshots.
- Keep 20m as the conservative accepted rule baseline until dynamic safety and coverage evidence justify promotion.

## 4. SLAM Status

Current SLAM baseline:

- RTAB-Map RGB-D is the primary single-vehicle SLAM smoke baseline.
- scan-cloud mode remains fallback/comparison only.

Accepted evidence:

- RTAB-Map installation audit accepted.
- RGB-D smoke accepted.
- RGB-D consistency accepted.
- RGB-D RViz overlay accepted.
- cable motion-backed RGB-D RViz accepted.
- wind 15m motion-backed RGB-D RViz accepted.

Important boundary:

- Gazebo pose / P3D odometry is used as debug/reference odometry in current smoke tests.
- SLAM output is not used for PX4 control.
- No quantitative SLAM accuracy, loop-closure quality, or map-to-ground-truth metric is complete.

Next SLAM work:

- Add map quality metrics before claiming SLAM completion.
- Keep RTAB-Map output out of active control until a separate safety review exists.

## 5. Multi-Vehicle Status

Current status:

- PX4/Gazebo Classic multi-vehicle readiness has been audited separately.
- Two-vehicle read-only smoke was refreshed on 2026-06-09 and accepted with `/px4_1` and `/px4_2` output namespaces observed.
- Refreshed multi-vehicle forbidden publisher audit confirms key `/px4_1/fmu/in/*` and `/px4_2/fmu/in/*` project publisher counts are `0`.
- Four-vehicle read-only namespace smoke is accepted with `/px4_1` through `/px4_4` output namespaces observed and key `/px4_i/fmu/in/*` publisher counts at `0`.
- Two-vehicle rule-baseline design exists at `docs/15_two_vehicle_rule_baseline_design.md`.
- Four-vehicle rule-baseline design exists at `docs/16_four_vehicle_rule_baseline_design.md`.
- Four-vehicle dry-run planner source/launch exists and M1 static contract audit is accepted.
- Two-vehicle dry-run planner source/launch exists and M1 static contract audit is accepted.
- Two-vehicle dry-run M2 read-only smoke is accepted; dry-run topics publish while key `/px4_1/fmu/in/*` and `/px4_2/fmu/in/*` publisher counts remain `0`.
- Two-vehicle dry-run M3 RViz overlay screenshot is accepted at `data/screenshots/two_vehicle_dry_run_overlay_20260609_105743.png`.
- Two-vehicle dry-run M4 role assignment enrichment is accepted; `/zcw/multi_vehicle/dry_run/assignment_state` publishes rule-baseline role candidates while key `/px4_1/fmu/in/*` and `/px4_2/fmu/in/*` publisher counts remain `0`.
- Two-vehicle dry-run M5 sample audit is accepted; full-length samples show non-placeholder `TOPOLOGY_READY`, rule-baseline assignment fields, `learned_policy=false`, and no-active/no-PX4-input flags.
- Multi-vehicle task planning/RL is not implemented.
- Current reliable evidence is mostly single-vehicle baseline, mapping, and dry-run control-gate evidence.

Next multi-vehicle work:

- Design a four-vehicle dry-run rule-baseline plan before any four-vehicle Offboard/arm.
- Keep the first multi-vehicle control node dry-run or read-only.
- Do not combine multi-vehicle, SLAM feedback, and active cable setpoint publication in one step.

## 6. Immediate Next Recommended Node

Recommended next node:

1. Run four-vehicle dry-run ROS graph smoke after the M1 static contract, or return to cable/wind evidence; active multi-vehicle Offboard remains forbidden.

Reason:

- Wind has strong single-vehicle dynamic/coverage evidence now.
- Multi-vehicle has refreshed read-only namespace evidence and a dry-run-first rule-baseline design.
- Four-vehicle read-only startup is now accepted, but four-vehicle active control is still forbidden.
- Four-vehicle dry-run planner M1 static contract is accepted.
- M1, M2, M3, M4 and M5 are accepted for the two-vehicle dry-run baseline.
- The next multi-vehicle gap is offline scoring/richer topology evidence or a separate active-control review, not evidence that the dry-run node can publish.

Safety boundary for that node:

- It must not start multi-vehicle Offboard or arm.
- It must not publish `/fmu/in/*`.
- It must not create or use cable Phase B active bridge.
