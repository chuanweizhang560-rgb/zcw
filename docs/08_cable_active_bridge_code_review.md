# Cable Active Bridge Code Review Template

This document is the required review template for a future `cable_offboard_active_bridge`.

It does not approve Phase B execution and does not request active publication.

## 1. Review Scope

The future active bridge must be introduced as a separate diff and a separate executable:

```text
ros2_ws/src/zcw_px4_baseline/src/cable_offboard_active_bridge.cpp
```

Required CMake target:

```text
cable_offboard_active_bridge
```

Forbidden in the active bridge diff:

- modifying `cable_px4_bridge_dry_run` behavior.
- modifying `cable_offboard_gate_dry_run` behavior.
- adding PX4 dependencies to `zcw_cable_perception`.
- using raw perception or path topics as active setpoint input.
- enabling `phase_b_user_approved:=true` in a committed script.

## 2. Required Inputs

The active bridge may subscribe only to:

| Topic | Type | Reason |
|---|---|---|
| `/zcw/cable/offboard_gate/state` | `std_msgs/String` | final gate state |
| `/zcw/cable/offboard_gate/phase_b_allowed` | `std_msgs/Bool` | explicit approval mirror |
| `/zcw/cable/offboard_gate/ned_setpoint_approved_dry_run` | `geometry_msgs/PointStamped` | final gated NED setpoint |
| `/fmu/out/vehicle_status` | `px4_msgs/msg/VehicleStatus` | arming/nav readback |
| `/fmu/out/vehicle_local_position` | `px4_msgs/msg/VehicleLocalPosition` | local validity/readback |

Forbidden direct inputs:

- `/camera/points`
- `/zcw/cable/offset_path`
- `/zcw/cable/lookahead_target`
- `/zcw/cable/dry_run/candidate_setpoint`
- `/zcw/cable/px4_bridge/ned_setpoint_dry_run`

## 3. Required Outputs

After explicit approval only:

| Topic | Type | Review requirement |
|---|---|---|
| `/fmu/in/offboard_control_mode` | `px4_msgs/msg/OffboardControlMode` | heartbeat first, before mode command |
| `/fmu/in/trajectory_setpoint` | `px4_msgs/msg/TrajectorySetpoint` | only gate-approved NED setpoint |
| `/fmu/in/vehicle_command` | `px4_msgs/msg/VehicleCommand` | Offboard and arm after pre-roll only |
| `/zcw/cable/offboard_active/state` | `std_msgs/String` | state and reason |
| `/zcw/cable/offboard_active/abort` | `std_msgs/Bool` | latched abort state |

Before approval, any local publisher on `/fmu/in/*` is a failure.

## 4. Required State Machine

The active implementation must expose these states in `/zcw/cable/offboard_active/state`:

1. `WAITING_FOR_APPROVAL`
2. `WAITING_FOR_GATE`
3. `PRE_ROLL_HEARTBEAT`
4. `OFFBOARD_REQUESTED`
5. `ARM_REQUESTED`
6. `ACTIVE_TRACKING`
7. `HOLD_ABORT`

Review requirements:

- `PRE_ROLL_HEARTBEAT` must publish heartbeat and a finite setpoint before any mode command.
- `OFFBOARD_REQUESTED` must occur before `ARM_REQUESTED`.
- `ACTIVE_TRACKING` must require PX4 nav state to report Offboard.
- `HOLD_ABORT` must stop advancing the cable setpoint stream.

## 5. Required Safety Gates

All gates must be visible in state text or structured logs:

| Gate | Required future limit |
|---|---:|
| approved NED setpoint age | `<= 0.5 s` |
| vehicle status age | `<= 1.0 s` |
| local position age | `<= 1.0 s` |
| active horizontal jump | `<= 2.5 m` |
| active vertical jump | `<= 0.5 m` |
| observed dry-run step before active approval | `<= 1.1 m` |
| setpoint publication rate | `>= 20 Hz` |
| pre-roll duration | PX4 official Offboard-compatible warm-up before mode command |

The active bridge must not convert a 10m raw lookahead target jump into a PX4 setpoint jump.

## 6. Required Abort Conditions

The active bridge must latch abort on:

1. `phase_b_allowed=false`.
2. gate state stale or not ready.
3. approved NED setpoint stale, non-finite, or wrong frame.
4. active horizontal or vertical jump over limit.
5. PX4 local position invalid.
6. unexpected armed state before pre-roll completes.
7. Offboard nav state timeout.
8. setpoint stream rate below threshold.
9. any `zcw_cable_perception` package publisher on `/fmu/in/*`.

Abort reset must be explicit, not automatic.

## 7. Required Tests

Before active code review can pass, evidence must include:

1. `scripts/audit_phase_b_active_preflight_boundary.sh`
2. `scripts/audit_cable_setpoint_thresholds.sh`
3. a new active bridge static audit script.
4. a dry-run mode of the active bridge that publishes only `/zcw/cable/offboard_active/*`.
5. a publisher audit proving `/fmu/in/*` publisher count is 0 in dry-run active-bridge mode.
6. a future explicit approval run that records nonzero publisher count only for the intended active executable.
7. Gazebo/RViz screenshot after active approval showing drone, line, and path alignment.

The current repository has not reached items 3-7.

## 8. Review Decision Format

Every future active bridge review must end with one of:

```text
decision=rejected_cable_active_bridge_review
```

or:

```text
decision=accepted_cable_active_bridge_review
```

Acceptance is allowed only after explicit Phase B approval and after all required tests pass.

Current decision:

```text
decision=not_started_cable_active_bridge_review
phase_b_approved=false
active_bridge_present=false
publishes_fmu_in=false
```

## 9. Template Audit Evidence

Implemented audit:

```bash
scripts/audit_active_bridge_review_template.sh
```

Latest evidence:

- summary: `data/results/active_bridge_review_template_20260604_094724/active_bridge_review_template_20260604_094724.txt`
- template checks: `data/results/active_bridge_review_template_20260604_094724/template_checks_20260604_094724.log`
- boundary checks: `data/results/active_bridge_review_template_20260604_094724/boundary_checks_20260604_094724.log`

Latest result:

- `decision=accepted_active_bridge_review_template_audit`
- `phase_b_approved=false`
- `active_bridge_present=false`
- `publishes_fmu_in=false`
- `starts_px4=false`
- `starts_offboard=false`
- `arms=false`
