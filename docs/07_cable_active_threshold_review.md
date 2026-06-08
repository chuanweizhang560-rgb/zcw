# Cable Active Threshold Review

This document records the current dry-run setpoint spacing and the safety thresholds that a future active bridge must respect.

It does not approve Phase B execution.

## 1. Inputs

Latest local evidence:

| Input | Path |
|---|---|
| offset path CSV | `data/results/catenary_offset_yz_zbin2_step5_20260608_000000/depth_camera_motion_catenary_offset_yz_zbin2_step5_offset_path_20260608_085655.csv` |
| lookahead target CSV | `data/results/lookahead_target_step5_20m_strict_20260608_090000/depth_camera_motion_lookahead_step5_20m_strict_targets_20260608_085945.csv` |
| gate state echo | `data/logs/cable_offboard_gate_rviz_state_echo_20260608_101949.log` |
| gate approved NED echo | `data/logs/cable_offboard_gate_rviz_approved_ned_echo_20260608_101949.log` |

Because `data/` is ignored, a fresh clone must regenerate these artifacts before repeating the audit.

## 2. Audit Entry

Implemented audit:

```bash
scripts/audit_cable_setpoint_thresholds.sh
```

The audit:

- reads only CSV and log files.
- does not start ROS, PX4, Gazebo, RViz or Offboard.
- does not arm.
- does not publish `/fmu/in/*`.
- writes a summary under `data/results/cable_setpoint_thresholds_*`.

## 3. Current Threshold Contract

The current dry-run chain has two different spacing concepts:

| Quantity | Current role | Limit |
|---|---|---:|
| offset path sampling step | offline fitted path spacing | `<= 5.6 m` |
| lookahead target spacing | target sequence spacing | `<= 5.6 m` |
| dry-run observed setpoint step | real candidate step after speed limiting | `<= 1.1 m` |
| active horizontal jump gate | future active bridge safety gate | `<= 2.5 m` |
| active vertical jump gate | future active bridge safety gate | `<= 0.5 m` |
| dry-run smoke horizontal compatibility | current bridge/gate smoke compatibility | `<= 5.0 m` |
| dry-run smoke vertical compatibility | current bridge/gate smoke compatibility | `<= 2.0 m` |

The active bridge must never use raw lookahead target spacing as direct PX4 setpoint jumps. It must consume the gate-approved NED dry-run output after speed limiting and jump gating.

## 4. Latest Result

Latest audit evidence:

- summary: `data/results/cable_setpoint_thresholds_20260608_102731/cable_setpoint_thresholds_20260608_102731.txt`
- offset path stats: `data/results/cable_setpoint_thresholds_20260608_102731/offset_path_stats_20260608_102731.txt`
- lookahead target stats: `data/results/cable_setpoint_thresholds_20260608_102731/lookahead_target_stats_20260608_102731.txt`
- gate state stats: `data/results/cable_setpoint_thresholds_20260608_102731/gate_state_stats_20260608_102731.txt`
- approved NED stats: `data/results/cable_setpoint_thresholds_20260608_102731/approved_ned_stats_20260608_102731.txt`

Latest result:

- `decision=accepted_cable_setpoint_threshold_audit`
- `publishes_fmu_in=false`
- `starts_px4=false`
- `starts_offboard=false`
- `arms=false`
- `max_offset_step_m=5.000264`
- `max_target_jump_m=5.000264`
- `observed_gate_horizontal_jump_m=1.000000`
- `observed_gate_vertical_jump_m=0.005523`

The current evidence supports keeping the active horizontal jump gate at `<= 2.5m`, the active vertical jump gate at `<= 0.5m`, and requiring the observed dry-run step to remain around `<= 1.1m` before any future active approval.
