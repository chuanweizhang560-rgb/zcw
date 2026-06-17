# Cable Inspection Surface Coverage Model

This document defines the future coverage model needed before claiming final cable inspection coverage.

It does not implement the model. It does not approve active control. It does not claim final inspection completion.

## 1. Current Gap

Current accepted cable evidence proves dry-run readiness:

- 5 wire groups exist in the audited geometry.
- offset path and lookahead targets are frame-consistent.
- line-segment lookahead coverage spans the current candidate path.
- all groups have RViz visual overlay evidence.
- no cable active bridge is approved.

This is not final inspection coverage.

The missing layer is a view-dependent inspection metric:

```text
cable surface samples + camera poses + distance gate + FOV gate + view-angle gate + occlusion gate
```

## 2. Coverage Unit

The future model should represent each cable as a thin cylindrical inspection target.

Recommended representation:

- Use the accepted catenary/centerline CSV as the cable center curve.
- Use an assumed or model-derived cable radius.
- Sample each cable into surface points around the circumference and along arc length.
- Store each sample with:
  - `group_id`
  - `arc_length_m`
  - `surface_angle_rad`
  - `x,y,z`
  - outward normal
  - coverage state

This is a geometry surface model, not image-level defect recognition.

## 3. Mature Library Boundary

Use mature geometry libraries where possible:

- `numpy` for vector math.
- `scipy` for interpolation if needed.
- `trimesh` or another mature geometry package for ray/mesh helpers if an explicit mesh is introduced.
- ROS 2 camera info messages for intrinsics if the model is tied to real camera topics.

Do not hand-write a large custom geometry engine.

## 4. Required Inputs

Minimum future inputs:

| Input | Source |
|---|---|
| cable centerline | accepted catenary/centerline CSV |
| offset inspection path | accepted offset path CSV |
| camera trajectory | PX4/Gazebo/P3D or approved active run log |
| camera intrinsics | ROS `CameraInfo` or fixed documented PX4 depth camera intrinsics |
| camera extrinsics | vehicle-to-camera transform |
| occlusion geometry | Gazebo world mesh, point cloud, or accepted occupancy map |

Without camera trajectory and camera model, coverage must remain a path-readiness metric only.

## 5. Coverage Gates

A cable surface sample is covered only if all gates pass:

| Gate | Meaning |
|---|---|
| distance | camera-to-sample distance inside accepted inspection window |
| FOV | sample projects inside camera image bounds |
| normal/view angle | camera observes the visible side of the cylindrical surface |
| occlusion | ray from camera to sample is not blocked |
| pose validity | camera pose is fresh and within accepted trajectory evidence |

The final metric should report:

```text
covered_surface_sample_count / total_surface_sample_count
```

The metric should also report weakest group, weakest arc-length section, and weakest circumference sector.

## 6. Suggested Initial Thresholds

These are review targets, not current accepted thresholds:

| Metric | Initial target |
|---|---:|
| per-group surface coverage | `>= 0.90` |
| global surface coverage | `>= 0.95` |
| weakest 20m arc section | `>= 0.80` |
| max uncovered continuous arc length | `<= 10m` |
| valid camera-pose ratio | `>= 0.95` |

Do not enforce these as current acceptance until a real coverage implementation and evidence exist.

## 7. Relationship To Current Evidence

Current evidence can seed the model:

- `data/results/catenary_offset_yz_zbin2_step5_20260608_000000/depth_camera_motion_catenary_offset_yz_zbin2_step5_offset_path_20260608_085655.csv`
- `data/results/lookahead_target_step5_20m_strict_20260608_090000/depth_camera_motion_lookahead_step5_20m_strict_targets_20260608_085945.csv`
- `data/results/cable_line_segment_coverage_20260617_085604/cable_line_segment_coverage_20260617_085604.txt`
- `data/screenshots/cable_all_groups_rviz_overlay_20260616_093252.png`

But these do not contain enough information to compute final view-dependent cable coverage.

## 8. Future Implementation Shape

When implemented later, keep it offline first:

```text
scripts/audit_cable_surface_coverage_offline.sh
```

The current first input-gap prototype is:

```text
scripts/audit_cable_surface_coverage_input_gap.sh
```

Latest accepted input-gap result:

- summary: `data/results/cable_surface_coverage_input_gap_20260617_091357/cable_surface_coverage_input_gap_20260617_091357.txt`
- group CSV: `data/results/cable_surface_coverage_input_gap_20260617_091357/cable_surface_coverage_input_gap_groups_20260617_091357.csv`

Key result:

```text
input_ok=true
camera_pose_count=891
path_point_count=125
group_count=5
distance_ready_group_count=0
global_min_camera_distance_m=24.262620544
global_max_nearest_camera_distance_m=79.730567700
fov_gate_implemented=false
occlusion_gate_implemented=false
surface_sampling_implemented=false
claims_final_cable_inspection_coverage=false
coverage_claimable=false
```

Interpretation:

- Existing cable motion pose evidence is parseable.
- It is not sufficient for final cable surface coverage.
- The camera trajectory and accepted offset path have a large distance/height/corridor mismatch for this purpose.
- A future coverage run needs a trajectory intentionally designed for cable surface observation.

The current surface-observation pose candidate generator is:

```text
scripts/audit_cable_surface_observation_pose_candidate.sh
```

Latest accepted candidate:

- summary: `data/results/cable_surface_observation_pose_candidate_20260617_091638/cable_surface_observation_pose_candidate_20260617_091638.txt`
- pose CSV: `data/results/cable_surface_observation_pose_candidate_20260617_091638/cable_surface_observation_pose_candidate_20260617_091638.csv`

Key result:

```text
decision=accepted_cable_surface_observation_pose_candidate
group_count=5
accepted_group_count=5
pose_count=125
min_target_distance_m=5.000000000
max_target_distance_m=5.000000000
global_max_target_distance_error_m=0.000000000
min_pitch_deg=0.000000000
max_pitch_deg=0.000000000
claims_active_control_approval=false
claims_final_cable_inspection_coverage=false
```

Interpretation:

- The accepted offset path already defines a plausible high-altitude observation pose candidate for each sampled cable point.
- This candidate should be used as the intended camera trajectory source for future offline surface coverage, before any active bridge discussion.
- It is still not active control and still not final coverage.

The current trajectory-continuity check for that candidate is:

```text
scripts/audit_cable_surface_observation_trajectory_continuity.sh
```

Latest accepted continuity result:

- summary: `data/results/cable_surface_observation_trajectory_continuity_20260617_092314/cable_surface_observation_trajectory_continuity_20260617_092314.txt`
- group CSV: `data/results/cable_surface_observation_trajectory_continuity_20260617_092314/cable_surface_observation_trajectory_continuity_groups_20260617_092314.csv`

Key result:

```text
decision=accepted_cable_surface_observation_trajectory_continuity
group_count=5
accepted_group_count=5
global_max_step_m=5.000331765
global_max_yaw_step_deg=0.000000000
global_max_pitch_step_deg=0.000000000
global_max_target_distance_error_m=0.000000000
claims_active_control_approval=false
claims_final_cable_inspection_coverage=false
```

Interpretation:

- The surface-observation candidate is continuous enough for offline coverage prototyping.
- It is not yet a PX4 trajectory and must not be published as setpoints without a separate active-control approval path.

The current ideal FOV upper-bound characterization is:

```text
scripts/audit_cable_surface_fov_candidate_upper_bound.sh
```

Latest accepted upper-bound characterization:

- summary: `data/results/cable_surface_fov_candidate_upper_bound_20260617_092636/cable_surface_fov_candidate_upper_bound_20260617_092636.txt`
- group CSV: `data/results/cable_surface_fov_candidate_upper_bound_20260617_092636/cable_surface_fov_candidate_upper_bound_groups_20260617_092636.csv`

Key result:

```text
decision=accepted_cable_surface_fov_candidate_upper_bound_characterization
group_count=5
accepted_group_count=5
global_min_total_surface_coverage_upper_bound_ratio=0.437500000
global_min_visible_side_coverage_upper_bound_ratio=1.000000000
global_min_fov_ok_ratio=1.000000000
visible_side_upper_bound_ready=true
meets_total_surface_target=false
occlusion_gate_implemented=false
uses_real_camera_trajectory=false
claims_final_cable_inspection_coverage=false
```

Interpretation:

- The single-side 5m offset candidate is good for the visible side of each cable.
- It cannot support a whole-circumference cable surface coverage claim.
- Full surface coverage requires multi-view observation, a different metric, or a deliberately narrower accepted claim such as visible-side inspection.
- The multiview upgrade path is documented in `docs/23_cable_multiview_surface_observation_plan.md`.

The first offline visible-side claim node is now accepted:

- summary: `data/results/cable_visible_side_surface_coverage_offline_20260617_093538/cable_visible_side_surface_coverage_offline_20260617_093538.txt`
- group CSV: `data/results/cable_visible_side_surface_coverage_offline_20260617_093538/cable_visible_side_surface_coverage_offline_groups_20260617_093538.csv`

Key result:

```text
decision=accepted_cable_visible_side_surface_coverage_offline
group_count=5
accepted_group_count=5
global_min_visible_side_ratio=1.000000000
global_max_total_surface_ratio=0.437500000
visible_side_ready=true
full_surface_ready=false
claims_visible_side_surface_coverage_offline_pass=true
claims_final_cable_inspection_coverage=false
```

Interpretation:

- The project can now claim a stable offline visible-side cable surface coverage milestone.
- The same evidence still does not justify a full-surface cable inspection claim.
- This is a project progression node, not an active-control approval.

The C2 offline multiview node is also accepted:

- multiview candidate summary: `data/results/cable_multiview_surface_candidate_offline_20260617_094219/cable_multiview_surface_candidate_offline_20260617_094219.txt`
- multiview candidate CSV: `data/results/cable_multiview_surface_candidate_offline_20260617_094219/cable_multiview_surface_candidate_offline_20260617_094219.csv`
- union summary: `data/results/cable_multiview_surface_union_offline_20260617_094233/cable_multiview_surface_union_offline_20260617_094233.txt`
- union group CSV: `data/results/cable_multiview_surface_union_offline_20260617_094233/cable_multiview_surface_union_offline_groups_20260617_094233.csv`

Key result:

```text
decision=accepted_cable_multiview_surface_union_offline
group_count=5
accepted_group_count=5
global_min_total_surface_coverage_upper_bound_ratio=0.875000000
global_min_visible_side_coverage_upper_bound_ratio=1.000000000
global_min_side_a_coverage_upper_bound_ratio=0.437500000
global_min_side_b_coverage_upper_bound_ratio=0.437500000
meets_total_surface_target=true
claims_multiview_surface_union_offline_pass=true
claims_final_cable_inspection_coverage=false
```

Interpretation:

- Two opposite-side offline views materially improve the surface claim over the single-side node.
- This still is not a final cable inspection certificate.
- It is a stronger C2 offline geometry milestone that can support later multiview work.

Expected behavior:

- read accepted cable geometry CSVs.
- read a camera trajectory log.
- read camera model/extrinsics.
- sample cable surface.
- compute coverage gates.
- write summary CSV and per-group CSV.
- never publish `/fmu/in/*`.
- never start Offboard/arm.

Only after offline coverage is stable should it be tied to active simulation evidence.

## 9. Non-Claims

Until this model exists and passes, do not claim:

- final cable inspection coverage.
- full cable traversal completion.
- visible defect coverage.
- defect detection or classification.
- active cable tracking success.
- multi-vehicle cable inspection completion.

## 10. Current Status

Current status:

```text
surface_coverage_model_documented=true
surface_coverage_implementation_exists=false
final_cable_inspection_coverage_claim=false
active_control_approved=false
```

The next useful work is an offline prototype that consumes existing trajectory evidence, not an active bridge.
