# Cable Phase B Active Bridge Preflight

This document is a preflight contract for a future cable-tracking active PX4 bridge.

It does not approve Phase B execution.

Current status:

- Phase A bridge dry-run passed.
- PX4/Gazebo read-only frame sampling passed.
- Offboard gate dry-run passed.
- Offboard gate RViz/debug overlay passed.
- No cable-tracking node is approved to publish `/fmu/in/*`.

## 1. Approval Boundary

Active Phase B can start only after an explicit user instruction that says PX4 setpoint publication is approved.

Until then, forbidden actions remain:

- create a cable active publisher to `/fmu/in/offboard_control_mode`
- create a cable active publisher to `/fmu/in/trajectory_setpoint`
- create a cable active publisher to `/fmu/in/vehicle_command`
- set `phase_b_user_approved:=true` in any script
- arm from a cable tracking script
- switch to Offboard from a cable tracking script

The existing generic PX4 baseline executables may keep their official-example-derived Offboard behavior:

- `offboard_hover_retry`
- `offboard_waypoint_sequence`

They are not the cable active bridge and must not be used as proof that cable tracking can safely publish active setpoints.

## 2. Required New Executable

The future active bridge must be a new executable under:

```text
ros2_ws/src/zcw_px4_baseline
```

Required naming:

```text
cable_offboard_active_bridge
```

It must not modify the proven dry-run executables:

- `cable_px4_bridge_dry_run`
- `cable_offboard_gate_dry_run`

Reason:

- dry-run evidence must remain reproducible.
- active publication must be reviewable as a separate diff.
- rollback must mean stopping the active executable, not changing perception or dry-run state.

## 3. Allowed Inputs

The future active bridge may read only already-gated outputs:

| Topic | Type | Required condition |
|---|---|---|
| `/zcw/cable/offboard_gate/state` | `std_msgs/String` | starts with `PHASE_B_READY_DRY_RUN` before active approval |
| `/zcw/cable/offboard_gate/phase_b_allowed` | `std_msgs/Bool` | true only in future approved active run |
| `/zcw/cable/offboard_gate/ned_setpoint_approved_dry_run` | `geometry_msgs/PointStamped` | fresh, finite, jump-gated |
| `/fmu/out/vehicle_status` | `px4_msgs/msg/VehicleStatus` | disarmed before active pre-roll |
| `/fmu/out/vehicle_local_position` | `px4_msgs/msg/VehicleLocalPosition` | finite and valid |

It must not read raw perception or path topics directly:

- `/camera/points`
- `/zcw/cable/lookahead_target`
- `/zcw/cable/offset_path`
- `/zcw/cable/dry_run/candidate_setpoint`
- `/zcw/cable/px4_bridge/ned_setpoint_dry_run`

The active bridge must consume the final gate output, not bypass intermediate gates.

## 4. Allowed Outputs After Approval

Only the future active executable may publish:

| Topic | Type | Purpose |
|---|---|---|
| `/fmu/in/offboard_control_mode` | `px4_msgs/msg/OffboardControlMode` | PX4 Offboard heartbeat |
| `/fmu/in/trajectory_setpoint` | `px4_msgs/msg/TrajectorySetpoint` | local NED setpoint |
| `/fmu/in/vehicle_command` | `px4_msgs/msg/VehicleCommand` | mode/arm commands, after pre-roll only |
| `/zcw/cable/offboard_active/state` | `std_msgs/String` | active bridge state |
| `/zcw/cable/offboard_active/abort` | `std_msgs/Bool` | latched abort |

Before approval, these outputs remain forbidden:

- any local publisher on `/fmu/in/*`
- `/zcw/cable/offboard_active/*`

## 5. Active State Machine

Minimum future state machine:

| State | Meaning | `/fmu/in/*` publication |
|---|---|---|
| `WAITING_FOR_APPROVAL` | user approval not present | false |
| `WAITING_FOR_GATE` | gate not ready or stale | false |
| `PRE_ROLL_HEARTBEAT` | Offboard heartbeat/setpoint stream warm-up | heartbeat and setpoint only |
| `OFFBOARD_REQUESTED` | mode command sent | heartbeat and setpoint |
| `ARM_REQUESTED` | arm command sent after Offboard request | heartbeat and setpoint |
| `ACTIVE_TRACKING` | tracking setpoint stream active | heartbeat and setpoint |
| `HOLD_ABORT` | latched abort, no new setpoint stream | false except explicit hold/disarm command if approved |

`PRE_ROLL_HEARTBEAT` must run before any Offboard mode request, following PX4 official Offboard example behavior already used in the baseline package.

## 6. Abort Conditions

The future active bridge must latch `HOLD_ABORT` if any condition occurs:

1. gate state is stale.
2. `phase_b_allowed` becomes false.
3. approved NED setpoint is stale or non-finite.
4. horizontal jump exceeds the active threshold.
5. vertical jump exceeds the active threshold.
6. PX4 local position becomes invalid.
7. vehicle is armed before active bridge pre-roll completes.
8. nav state fails to enter Offboard within the configured timeout.
9. any cable perception package starts publishing `/fmu/in/*`.

Abort reset must be a separate explicit command and must be logged.

## 7. Evidence Required Before Implementing Active Publisher

These evidence files must exist and be referenced in `PROCESS_LOG.md`:

| Evidence | Latest local path |
|---|---|
| Phase A bridge dry-run state | `data/logs/px4_bridge_dry_run_state_echo_20260608_091305.log` |
| Phase A bridge RViz screenshot | `data/screenshots/px4_bridge_dry_run_rviz_overlay_20260608_102352.png` |
| PX4/Gazebo frame audit summary | `data/results/px4_gazebo_frame_alignment_20260608_102532/px4_gazebo_frame_alignment_20260608_102532.txt` |
| Offboard gate dry-run summary | `data/results/cable_offboard_gate_dry_run_20260608_101325/cable_offboard_gate_dry_run_20260608_101325.txt` |
| Offboard gate dry-run forbidden publisher audit | `data/logs/cable_offboard_gate_forbidden_publishers_20260608_101325.log` |
| Offboard gate RViz summary | `data/results/cable_offboard_gate_rviz_overlay_20260608_101949/cable_offboard_gate_rviz_overlay_20260608_101949.txt` |
| Offboard gate RViz screenshot | `data/screenshots/cable_offboard_gate_dry_run_rviz_overlay_20260608_101949.png` |

Because `data/` is intentionally ignored by git, a fresh clone must regenerate these artifacts before active work.

## 8. Preflight Audit Script

Implemented preflight boundary audit:

```bash
scripts/audit_phase_b_active_preflight_boundary.sh
```

The audit is allowed to:

- read source code and scripts.
- run static checks.
- check local evidence artifacts.
- write a summary under `data/results/`.

The audit is not allowed to:

- start PX4/Gazebo.
- start Offboard.
- arm.
- publish `/fmu/in/*`.
- create active bridge source code.

Passing this audit means the repository boundary is ready for a future explicit approval step. It does not mean active Phase B is approved.

## 9. Threshold Review

The current active-threshold evidence is documented in:

```bash
docs/07_cable_active_threshold_review.md
```

Implemented audit:

```bash
scripts/audit_cable_setpoint_thresholds.sh
```

Latest result:

- `decision=accepted_cable_setpoint_threshold_audit`
- `max_offset_step_m=5.000264`
- `max_target_jump_m=5.000264`
- `observed_gate_horizontal_jump_m=1.000000`
- `observed_gate_vertical_jump_m=0.005523`
- `publishes_fmu_in=false`

This confirms that the future active bridge must consume the gate-approved dry-run NED output after speed limiting. It must not publish raw lookahead target jumps directly to PX4.

## 10. Code Review Template

The future active bridge review template is documented in:

```bash
docs/08_cable_active_bridge_code_review.md
```

Implemented audit:

```bash
scripts/audit_active_bridge_review_template.sh
```

Current review decision:

- `decision=accepted_active_bridge_review_template_audit`
- `phase_b_approved=false`
- `active_bridge_present=false`
- `publishes_fmu_in=false`
