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
- Slow loop wind coverage audit accepted from the 2026-06-12 PX4 local-position trajectory: converted 29888 valid poses, dynamic normal-filtered coverage `0.729605`, weakest normal band `0.581943`, fast occlusion-clear normal coverage `0.680961`, weakest occlusion band `0.600000`.
- Slow loop orbit-only coverage audit accepted after filtering out takeoff/transition poses: 28408 orbit poses, dynamic normal-filtered coverage `0.674538`, weakest normal band `0.512267`, fast occlusion-clear normal coverage `0.598628`, weakest occlusion band `0.507692`.

Important boundary:

- Static visibility/frustum coverage does not model occlusion or dynamic collision.
- The newer quality coverage audit adds surface-normal/view-angle filtering and useful-depth linkage, but still does not model occlusion, actual visual defect recognition, or dynamic collision safety.
- RTAB-Map screenshots are SLAM plumbing evidence, not inspection coverage certificates.
- 15m is preferred for observation experiments, but not final coverage readiness.
- Slow loop coverage uses PX4 local-position trajectory converted to the existing wind coverage CSV format. The fast occlusion audit is sampled for runtime control (`pose_stride=120`, `face_stride=16`), so it improves comparative evidence but still is not a dense final coverage certificate.
- The stricter orbit-only slow-loop coverage is weaker than the earlier 15m multi-level orbit occlusion result (`0.598628` vs `0.634335`), because slow loop is single-height. Treat slow loop as a strong SLAM loop-closure trajectory, not as the best wind inspection coverage baseline.

Next wind work:

- Add a denser occlusion-aware audit if runtime permits, or keep the fast audit as approximate method evidence.
- Add image-level quality/defect-detection integration only through mature open-source models or clearly separated future work.
- Define explicit wind inspection acceptance thresholds before claiming completion.
- Capture a fresh wind dynamic RViz/Gazebo screenshot only if it adds new evidence beyond the existing motion/RViz screenshots.
- Keep 20m as the conservative accepted rule baseline until dynamic safety and coverage evidence justify promotion; slow loop is currently the strongest wind SLAM loop-closure evidence, while multi-level orbit remains stronger for wind coverage.

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
- RTAB-Map RGB-D quality gate accepted with stable smoke/consistency, `/map` + `/cloud_map` + `/octomap_*` topics, depth contract evidence, and three real RViz screenshots checked.
- RTAB-Map database info metrics accepted using official `rtabmap-info`: cable motion DB has 47 graph poses and 259.931030m odometry length; wind motion DB has 62 graph poses and 383.794189m odometry length.
- RTAB-Map trajectory-error readiness accepted as a negative/limitation audit: existing DB poses are available, but effective ground-truth poses are `0` and current reference logs contain only one sample per scenario, so ATE cannot be computed from existing files.
- Updated wind RTAB-Map RGB-D motion capture accepted on 2026-06-11 with 48 waypoint advancements, 14264 PX4 local-position trajectory samples, 1142 P3D depth-pose trajectory samples, and a new RViz screenshot.
- Wind RTAB-Map trajectory ATE audit accepted as an odom-consistency metric: 39 RTAB-Map poses, 1142 P3D reference samples, 31 matched pairs, rigid-aligned `rmse_m=0.000001010`.
- Generic RTAB-Map trajectory ATE audit script accepted by reproducing the wind ATE CSV exactly with `SCENARIO=rtabmap_wind_generic`.
- RTAB-Map loop-closure evidence audit accepted as a limitation audit: latest wind DB has one raw `Link.type=1` candidate between nearly identical startup nodes, but official `rtabmap-info` reports `GlobalClosure=0`, so `claims_loop_closure_pass=false`.
- Updated cable RTAB-Map RGB-D motion capture accepted on 2026-06-12 with real PX4/Gazebo/RViz evidence, 11134 PX4 local-position trajectory samples, 891 P3D depth-pose trajectory samples, and screenshot `data/screenshots/rtabmap_depth_camera_rgbd_motion_rviz_overlay_20260612_132911.png`.
- Cable RTAB-Map trajectory ATE audit accepted as an odom-consistency metric: 38 RTAB-Map poses, 891 P3D reference samples, 32 matched pairs, rigid-aligned `rmse_m=0.000001421`.
- Cable RTAB-Map loop-closure evidence audit accepted as a limitation audit: latest cable DB has 23 neighbor links and `0` raw/official loop-closure links, so `claims_loop_closure_pass=false`.
- Deliberate wind loop-closure smoke entry accepted on 2026-06-12 using `single_vehicle_wind_turbine_loop_closure_smoke.launch.py`, two repeated wind-orbit laps, and RTAB-Map parameter file `rtabmap_loop_closure_smoke.yaml`; the accepted run produced 60 nodes, 111 words, 33 neighbor links, 1 official `LocalTimeClosure`, and screenshot `data/screenshots/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260612_141032.png`.
- Loop-closure evidence audit now distinguishes `claims_official_loop_evidence` from `claims_task_level_loop_closure_pass`; the loop smoke has `claims_official_loop_evidence=true` but `claims_task_level_loop_closure_pass=false` because official `GlobalClosure=0` and `LocalSpaceClosure=0`.
- Loop smoke trajectory ATE audit accepted as an odom-consistency metric: 60 RTAB-Map poses, 1491 P3D reference samples, 52 matched pairs, rigid-aligned `rmse_m=0.000000804`.
- RTAB-Map rejected-loop-candidate audit accepted for the loop smoke: 29 rejected candidates, best visual inliers `10/20`, best match count `103` but `0` inliers, and `near_pass_count=0`.
- Slow wind loop-closure smoke accepted on 2026-06-12 using `single_vehicle_wind_turbine_slow_loop_closure_smoke.launch.py`: 15m radius, 32 points per lap, 3 repeated laps, 97 waypoint advancements, 83 RTAB-Map nodes, 140 words, 64 neighbor links, official `GlobalClosure=4`, official `LocalTimeClosure=3`, and screenshot `data/screenshots/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260612_143153.png`.
- Slow loop closure audit has `claims_loop_closure_pass=true`, `claims_official_loop_evidence=true`, and `claims_task_level_loop_closure_pass=true`; slow loop ATE remains an odom-consistency metric with 83 RTAB-Map poses, 2391 P3D reference samples, 75 matched pairs, and rigid-aligned `rmse_m=0.000001033`.
- PX4 local-position cross-check audit accepted for the slow loop: 83 RTAB-Map poses, 29888 PX4 local-position samples, 76 matched elapsed-time pairs, rigid-aligned `rmse_m=3.020397355`, `p95_error_m=3.177182157`, and `max_error_m=16.625628476`; this uses PX4 estimator output, not independent ground truth.

Important boundary:

- Gazebo pose / P3D odometry is used as debug/reference odometry in current smoke tests.
- SLAM output is not used for PX4 control.
- The quality gate, database metrics and trajectory-error readiness audit do not claim SLAM accuracy; current audited DBs have `ground_truth_total=0`, `total_global_closures=0`, and `total_local_space_closures=0`.
- The new ATE result is a consistency check against the same Gazebo/P3D debug odometry source used by RTAB-Map, not independent ground-truth SLAM accuracy.
- The wind raw closure candidate is not accepted as task-level loop closure because it is an early near-duplicate link and official RTAB-Map info does not confirm a GlobalClosure.
- The cable loop-closure audit has no raw candidate and no official closure evidence.
- The first deliberate loop smoke improved the evidence from `0 words` to a word-bearing RTAB-Map DB and one official local-time closure.
- The slow loop smoke now provides official task-level loop-closure evidence through RTAB-Map `GlobalClosure=4`, but it still does not prove independent SLAM accuracy because Gazebo/P3D debug odometry is still the odometry input/reference.
- The PX4 local-position cross-check is useful as an estimator-consistency warning: it is much larger than P3D ATE, but PX4 local position is still not an independent ground-truth system.

Next SLAM work:

- Add a true independent map-to-ground-truth metric before claiming SLAM completion; keep RTAB-Map loop closure as a smoke-level integration result, not final localization accuracy.
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
- Four-vehicle dry-run M2 ROS graph smoke is accepted; dry-run topics publish with four PX4/Gazebo read-only instances while key `/px4_i/fmu/in/*` publisher counts remain `0`.
- Four-vehicle dry-run sample audit is accepted; full-length samples show four goal topics, `FOUR_TOPOLOGY_READY`, `FOUR_SAFETY_READY_DRY_RUN`, rule-baseline assignment fields, `learned_policy=false`, and no-active/no-PX4-input flags.
- Four-vehicle dry-run M3 RViz overlay screenshot is accepted at `data/screenshots/four_vehicle_dry_run_overlay_20260611_143238.png`.
- Four-vehicle dry-run M4 rule scoring is accepted; `/zcw/multi_vehicle/four_vehicle_dry_run/scoring_state` publishes topology/state/task-distance/total rule scores while key `/px4_i/fmu/in/*` publisher counts remain `0`.
- Four-vehicle dry-run M5 scoring marker overlay is accepted; `/zcw/multi_vehicle/four_vehicle_dry_run/score_markers` publishes RViz `MarkerArray` score/role text and screenshot evidence exists at `data/screenshots/four_vehicle_dry_run_overlay_20260611_150906.png`.
- Four-vehicle dry-run M6 offline rule score sweep is accepted; `scripts/audit_four_vehicle_rule_score_sweep.sh` verifies nominal, exact-goal, task-far, chain-break, base-range-break, stale-status and missing-pose cases without starting ROS/PX4/Gazebo/RViz.
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

1. Continue with four-vehicle dry-run assignment/topology evidence, or return to cable/wind evidence; active multi-vehicle Offboard remains forbidden.

Reason:

- Wind has strong single-vehicle dynamic/coverage evidence now.
- Multi-vehicle has refreshed read-only namespace evidence and a dry-run-first rule-baseline design.
- Four-vehicle read-only startup is now accepted, but four-vehicle active control is still forbidden.
- Four-vehicle dry-run planner M1 static contract is accepted.
- Four-vehicle dry-run M2 ROS graph smoke and sample audit are accepted.
- Four-vehicle dry-run M3 RViz overlay is accepted.
- Four-vehicle dry-run M4 rule scoring is accepted.
- Four-vehicle dry-run M5 scoring marker overlay is accepted.
- Four-vehicle dry-run M6 offline rule score sweep is accepted.
- M1, M2, M3, M4 and M5 are accepted for the two-vehicle dry-run baseline.
- The next multi-vehicle gap is richer assignment/topology evidence or a separate active-control review, not evidence that the dry-run node can publish.

Safety boundary for that node:

- It must not start multi-vehicle Offboard or arm.
- It must not publish `/fmu/in/*`.
- It must not create or use cable Phase B active bridge.
