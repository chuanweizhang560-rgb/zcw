# Cable Four-View Camera Mount Strategy

This document records the C3 four-view camera/mount split.

It does not approve active control. It does not approve a gimbal. It does not claim final cable inspection coverage.

## 1. Purpose

The C3 four-view geometry and occlusion gates show that four observation directions can cover the cable surface offline.

That does not mean the current PX4 `iris_depth_camera` body-fixed camera can execute all four views. The vertical `z_negative` and `z_positive` views require `90 deg` absolute pitch, so the full-surface C3 result needs a mount/gimbal review before it can become an active flight plan.

## 2. Accepted Evidence

Accepted mount strategy audit:

- summary: `data/results/cable_fourview_mount_strategy_20260618_133231/cable_fourview_mount_strategy_20260618_133231.txt`
- view CSV: `data/results/cable_fourview_mount_strategy_20260618_133231/cable_fourview_mount_strategy_views_20260618_133231.csv`

Key fields:

```text
decision=accepted_cable_fourview_mount_strategy
view_count=4
body_fixed_ready_view_count=2
gimbal_or_mount_review_view_count=2
full_surface_ratio=1.000000000
occlusion_clear_ratio=1.000000000
fourview_geometry_ready=true
body_fixed_only_full_surface_ready=false
full_surface_requires_mount_review=true
recommended_active_track=body_fixed_side_views_only_until_mount_review
claims_active_control_approval=false
claims_final_cable_inspection_coverage=false
```

## 3. View Split

| View | Classification | Reason |
|---|---|---|
| `y_negative` | body-fixed candidate | `max_abs_pitch_deg=0` |
| `y_positive` | body-fixed candidate | `max_abs_pitch_deg=0` |
| `z_negative` | mount/gimbal review required | `max_abs_pitch_deg=90` |
| `z_positive` | mount/gimbal review required | `max_abs_pitch_deg=90` |

## 4. Current Decision

Current safe active-track recommendation, if active cable control is approved later:

```text
recommended_active_track=body_fixed_side_views_only_until_mount_review
```

That means:

- side-view body-fixed candidates can be reviewed first.
- full-surface C3 flight must wait for a camera mount, gimbal, or attitude-control review.
- no current script may treat the four-view offline geometry as an active PX4 flight plan.

