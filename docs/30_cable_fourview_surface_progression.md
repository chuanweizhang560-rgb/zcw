# Cable Four-View Surface Progression

This document records the C3 four-view cable surface progression.

It does not approve active control. It does not claim final cable inspection coverage.

## 1. Purpose

The previous two-view C2 result improved total surface coverage from the single-side upper bound, but it still had:

```text
global_min_total_surface_coverage_upper_bound_ratio=0.875000000
```

C3 adds four offline observation directions around each cable centerline point:

- `y_negative`
- `y_positive`
- `z_negative`
- `z_positive`

The goal is to characterize whether a full-circumference geometric candidate can reach the 0.95 total-surface target before any active-control work.

## 2. Accepted C3 Evidence

Accepted four-view candidate:

- summary: `data/results/cable_fourview_surface_candidate_offline_20260618_131942/cable_fourview_surface_candidate_offline_20260618_131942.txt`
- CSV: `data/results/cable_fourview_surface_candidate_offline_20260618_131942/cable_fourview_surface_candidate_offline_20260618_131942.csv`

Key fields:

```text
decision=accepted_cable_fourview_surface_candidate_offline
group_count=5
accepted_group_count=5
pose_count=500
min_target_distance_m=5.000000000
max_target_distance_m=5.000000000
claims_active_control_approval=false
claims_final_cable_inspection_coverage=false
```

Accepted four-view union characterization:

- summary: `data/results/cable_fourview_surface_union_offline_20260618_131943/cable_fourview_surface_union_offline_20260618_131943.txt`
- group CSV: `data/results/cable_fourview_surface_union_offline_20260618_131943/cable_fourview_surface_union_offline_groups_20260618_131943.csv`

Key fields:

```text
decision=accepted_cable_fourview_surface_union_offline
group_count=5
accepted_group_count=5
global_min_total_surface_coverage_upper_bound_ratio=1.000000000
meets_total_surface_target=true
claims_active_control_approval=false
claims_final_cable_inspection_coverage=false
```

## 3. Attitude Feasibility Boundary

The four-view candidate includes top and bottom observation directions. Those views require pitch values up to `90 deg`, so they are not directly approved for body-fixed camera active flight.

Accepted feasibility characterization:

- summary: `data/results/cable_fourview_attitude_feasibility_20260618_132059/cable_fourview_attitude_feasibility_20260618_132059.txt`
- view CSV: `data/results/cable_fourview_attitude_feasibility_20260618_132059/cable_fourview_attitude_feasibility_views_20260618_132059.csv`

Expected boundary:

```text
direct_body_camera_ready=false
requires_gimbal_or_attitude_review=true
claims_active_control_approval=false
```

## 4. Occlusion Gate

The four-view candidate was also checked against the real AerialCore two-tower wire collision mesh with `trimesh`/`rtree` ray intersection.

Accepted evidence:

- summary: `data/results/cable_fourview_surface_occlusion_offline_20260618_132716/cable_fourview_surface_occlusion_offline_20260618_132716.txt`
- group CSV: `data/results/cable_fourview_surface_occlusion_offline_20260618_132716/cable_fourview_surface_occlusion_offline_groups_20260618_132716.csv`

Key fields:

```text
decision=accepted_cable_fourview_surface_occlusion_offline
uses_real_aerialcore_collision_mesh=true
group_count=5
accepted_group_count=5
ray_tests=7500
ray_clear=7500
global_min_occlusion_clear_total_surface_ratio=1.000000000
global_max_blocked_union_ratio=0.000000000
claims_active_control_approval=false
claims_final_cable_inspection_coverage=false
```

This strengthens the C3 offline geometry evidence from a pure FOV union upper bound to an AerialCore-mesh occlusion-clear characterization.

## 5. Current Interpretation

C3 proves a stronger offline geometric candidate:

```text
fourview_total_surface_upper_bound_ready=true
fourview_occlusion_clear_offline=true
mount_strategy_review_required=true
active_flight_ready=false
```

It does not prove:

- real PX4 trajectory execution,
- physical camera/gimbal feasibility,
- final cable inspection coverage.

## 6. Mount Strategy Split

The camera/mount split is documented separately at `docs/31_cable_fourview_camera_mount_strategy.md`.

Accepted evidence:

- summary: `data/results/cable_fourview_mount_strategy_20260618_133231/cable_fourview_mount_strategy_20260618_133231.txt`
- view CSV: `data/results/cable_fourview_mount_strategy_20260618_133231/cable_fourview_mount_strategy_views_20260618_133231.csv`

Key fields:

```text
body_fixed_ready_view_count=2
gimbal_or_mount_review_view_count=2
body_fixed_only_full_surface_ready=false
full_surface_requires_mount_review=true
recommended_active_track=body_fixed_side_views_only_until_mount_review
claims_active_control_approval=false
```
