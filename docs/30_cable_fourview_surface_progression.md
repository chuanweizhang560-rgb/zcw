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

## 4. Current Interpretation

C3 proves a stronger offline geometric candidate:

```text
fourview_total_surface_upper_bound_ready=true
active_flight_ready=false
```

It does not prove:

- real PX4 trajectory execution,
- physical camera/gimbal feasibility,
- occlusion-clear four-view full-surface coverage,
- final cable inspection coverage.
