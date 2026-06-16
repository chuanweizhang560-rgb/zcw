# Wind Acceptance Thresholds

This document defines the current acceptance threshold contract for the single-vehicle wind turbine rule baseline.

It does not approve multi-vehicle active Offboard, cable active bridge, learned policy control, image-level defect detection, or final inspection coverage claims.

## 1. Scope

Accepted scope:

- One PX4 vehicle in the AerialCore wind turbine world.
- Gazebo 11 + ROS 2 Humble + PX4 SITL.
- Rule baseline first, using the existing multilevel slow-loop wind orbit.
- Mature upstream components only. Current SLAM smoke evidence uses RTAB-Map RGB-D from ROS Humble packages.

Out of scope:

- Wind turbine defect detection.
- Learned policy control.
- Multi-vehicle active control.
- Cable active bridge.
- Using SLAM output to control PX4.
- Claiming independent SLAM accuracy from P3D/PX4 estimator comparisons.

## 2. Authoritative Audit

The current aggregate audit is:

```bash
scripts/audit_wind_rule_baseline_acceptance.sh
```

The audit is read-only and must keep these boundary fields:

```text
starts_ros=false
starts_px4=false
starts_gazebo=false
starts_rviz=false
starts_offboard=false
arms=false
publishes_fmu_in=false
```

Important distinction:

- The aggregate audit itself is read-only.
- Its source capture evidence did start PX4, Gazebo, RViz, Offboard, arming, and `/fmu/in/*` publication for the single-vehicle wind rule baseline only.
- That source capture permission does not transfer to cable active bridge or multi-vehicle active Offboard.

Latest accepted aggregate:

- `data/results/wind_rule_baseline_acceptance_20260616_085445/wind_rule_baseline_acceptance_20260616_085445.txt`

## 3. Default Thresholds

These values are the current default gate values in `scripts/audit_wind_rule_baseline_acceptance.sh`.

| Gate | Field | Threshold | Current accepted observation |
|---|---:|---:|---:|
| Waypoint progress | `MIN_WAYPOINT_ADVANCEMENTS` | `120` | `145` |
| PX4 local-position samples | `MIN_LOCAL_POSITION_SAMPLES` | `40000` | `44884` |
| Converted valid pose samples | `MIN_VALID_POSE_SAMPLES` | `40000` | `43611` |
| Capture duration | `MIN_CAPTURE_DURATION_SEC` | `300` | `348.991111000` |
| Conservative clearance | `MIN_CLEARANCE_M` | `1.0m` | `1.688958000m` |
| Dynamic normal-filtered coverage | `MIN_DYNAMIC_NORMAL_COVERAGE` | `0.70` | `0.733899000` |
| Dynamic weakest height-band coverage | `MIN_DYNAMIC_BAND_COVERAGE` | `0.55` | `0.595682000` |
| Occlusion-clear normal-filtered coverage | `MIN_OCCLUSION_CLEAR_COVERAGE` | `0.65` | `0.708904000` |
| Occlusion-clear weakest height-band coverage | `MIN_OCCLUSION_BAND_COVERAGE` | `0.55` | `0.593750000` |
| RTAB-Map DB nodes | `MIN_DB_NODES` | `180` | `205` |
| Official global closures | `MIN_OFFICIAL_GLOBAL_CLOSURES` | `1` | `6` |
| P3D-aligned ATE RMSE | `MAX_P3D_ATE_RMSE_M` | `0.01m` | `0.000001087m` |
| PX4 estimator cross-check p95 | `MAX_PX4_CROSSCHECK_P95_M` | `4.0m` | `2.559375689m` |

## 4. Required Evidence Inputs

The aggregate audit must consume all of these evidence groups:

| Evidence group | Required source type | Current accepted source |
|---|---|---|
| Wind RGB-D RViz motion capture | real PX4/Gazebo/RViz source capture | `data/results/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260615_091712/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260615_091712.txt` |
| PX4 local-position pose conversion | offline conversion from source capture log | `data/results/wind_pose_from_multilevel_slow_loop_20260615_091712/wind_pose_from_px4_local_position_20260615_092317.txt` |
| Dynamic coverage progression | offline mesh/FOV/normal audit | `data/results/wind_dynamic_coverage_multilevel_slow_loop_20260615_091712/wind_dynamic_coverage_progression_20260615_092327.txt` |
| Occlusion-aware coverage progression | offline `trimesh`/`rtree` ray audit | `data/results/wind_occlusion_coverage_multilevel_slow_loop_very_fast_20260615_091712/wind_occlusion_coverage_progression_20260615_092417.txt` |
| RTAB-Map loop closure evidence | offline DB audit and official `rtabmap-info` counters | `data/results/rtabmap_loop_closure_evidence_20260615_093152/rtabmap_loop_closure_evidence_20260615_093152.txt` |
| RTAB-Map output boundary | offline log/topic/DB boundary audit | `data/results/rtabmap_wind_capture_output_boundary_20260615_093222/rtabmap_wind_capture_output_boundary_20260615_093222.txt` |
| P3D ATE consistency | offline RTAB-Map DB vs Gazebo/P3D reference check | `data/results/rtabmap_multilevel_slow_loop_final_db_trajectory_ate_20260615_093152/rtabmap_multilevel_slow_loop_final_db_trajectory_ate_20260615_093152.txt` |
| PX4 estimator cross-check | offline RTAB-Map DB vs PX4 local-position check | `data/results/rtabmap_multilevel_slow_loop_px4_final_db_20260615_093152/rtabmap_multilevel_slow_loop_px4_final_db_20260615_093152.txt` |

## 5. Pass Meaning

If `scripts/audit_wind_rule_baseline_acceptance.sh` passes, the allowed claim is:

```text
The single-vehicle wind turbine rule baseline has accepted motion, geometry coverage, occlusion-sampled coverage, and RTAB-Map RGB-D smoke evidence under the current repository thresholds.
```

The accepted claim remains a rule-baseline evidence claim, not final inspection completion.

## 6. Non-Claims

Even when the audit passes, do not claim:

- final 95% physical surface inspection coverage.
- image-level defect detection.
- independent SLAM localization accuracy.
- SLAM-driven control.
- multi-vehicle wind inspection.
- cable active bridge approval.
- learned policy/MARL control.

Reason:

- Coverage is computed from sampled mesh/FOV/normal/occlusion checks, not from a dense certified inspection standard.
- Occlusion audit is sampled for runtime control and is still an engineering approximation.
- P3D ATE uses Gazebo/P3D debug odometry, which is also part of the RTAB-Map input/reference chain.
- PX4 local position is estimator output, not independent ground truth.
- RTAB-Map evidence is integration and loop-closure smoke evidence.

## 7. Next Upgrade Gates

Before stronger wind claims, add at least one of these:

- A denser occlusion audit with lower pose/face stride and recorded runtime budget.
- A documented inspection surface model with a target threshold such as 95% view-valid surfel coverage.
- A mature open-source defect detection or image-quality model, kept separate from the motion/coverage baseline.
- Independent ground-truth localization or map-to-known-mesh accuracy evidence.
- A separate active-control review before using SLAM or learned policy output in PX4 setpoints.

## 8. Maintenance Rule

When changing any default threshold in `scripts/audit_wind_rule_baseline_acceptance.sh`, update this document and rerun:

```bash
scripts/audit_wind_acceptance_threshold_contract.sh
scripts/audit_wind_rule_baseline_acceptance.sh
```
