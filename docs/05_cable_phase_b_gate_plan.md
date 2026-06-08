# Cable Phase B Offboard Gate Plan

This document defines the gate that must exist before any cable-tracking topic is allowed to publish PX4 Offboard input topics.

Current status:

- Phase A bridge dry-run is implemented.
- PX4/Gazebo read-only frame sampling has passed.
- `cable_offboard_gate_dry_run` is implemented and verified.
- No cable-tracking node is approved to publish `/fmu/in/*`.

## 1. Hard Boundary

Phase B is not approved by this document.

Publishing to these topics remains forbidden until the user explicitly approves Phase B execution:

- `/fmu/in/offboard_control_mode`
- `/fmu/in/trajectory_setpoint`
- `/fmu/in/vehicle_command`

Before approval, implementation may only add dry-run gate state topics under:

- `/zcw/cable/offboard_gate/*`

## 2. Gate Inputs

The future gate may read:

| Topic | Type | Use |
|---|---|---|
| `/zcw/cable/px4_bridge/state` | `std_msgs/String` | bridge readiness and hold reason |
| `/zcw/cable/px4_bridge/ned_setpoint_dry_run` | `geometry_msgs/PointStamped` | dry-run NED candidate |
| `/fmu/out/vehicle_status` | `px4_msgs/msg/VehicleStatus` | arming/nav state read-only check |
| `/fmu/out/vehicle_local_position` | `px4_msgs/msg/VehicleLocalPosition` | finite/valid local NED check |
| `/zcw/depth_camera/pose` | `nav_msgs/Odometry` | Gazebo read-only pose audit |

It must not read raw perception topics directly:

- `/camera/points`
- `/zcw/cable/lookahead_target`
- `/zcw/cable/offset_path`

The gate can only consume already-gated bridge outputs.

## 3. Gate Outputs

Before Phase B approval, allowed outputs:

| Topic | Type | Meaning |
|---|---|---|
| `/zcw/cable/offboard_gate/state` | `std_msgs/String` | complete gate state and reason |
| `/zcw/cable/offboard_gate/phase_b_allowed` | `std_msgs/Bool` | always false until explicit approval |
| `/zcw/cable/offboard_gate/ned_setpoint_approved_dry_run` | `geometry_msgs/PointStamped` | debug-only approved candidate mirror |

Forbidden before explicit approval:

- any `/fmu/in/*` publisher
- arming command
- Offboard mode command
- trajectory setpoint publisher

## 4. Required Gate States

Minimum state machine:

| State | Meaning | `/fmu/in/*` publication |
|---|---|---|
| `WAITING_FOR_INPUTS` | missing bridge/PX4 pose/status | false |
| `HOLD_USER_NOT_APPROVED` | Phase B not explicitly approved | false |
| `HOLD_BRIDGE_NOT_READY` | bridge state is not `DRY_RUN_READY` | false |
| `HOLD_PX4_NOT_READY` | PX4 status/local position missing or invalid | false |
| `HOLD_SETPOINT_JUMP` | candidate jump exceeds configured gate | false |
| `HOLD_ABORT` | abort condition latched | false |
| `PHASE_B_READY_DRY_RUN` | all checks pass, but still dry-run | false |
| `PHASE_B_ACTIVE` | future approved setpoint publication | true only after user approval |

The first implementation must stop at `PHASE_B_READY_DRY_RUN`.

## 5. Safety Gates

All gates must pass before `PHASE_B_READY_DRY_RUN`:

| Gate | Default |
|---|---:|
| bridge state starts with `DRY_RUN_READY` | required |
| NED candidate finite | required |
| PX4 local position finite | required |
| PX4 `xy_valid` and `z_valid` | required |
| candidate age | `<= 0.5 s` |
| PX4 status age | `<= 1.0 s` |
| PX4 local position age | `<= 1.0 s` |
| horizontal setpoint jump | `<= 2.5 m` active target, `<= 5.0 m` dry-run smoke compatibility |
| vertical setpoint jump | `<= 0.5 m` |
| candidate speed | `<= 5.0 m/s` |
| explicit approval parameter | false before Phase B |

Until Phase B is approved, the explicit approval parameter must default to false and must not be overridden in scripts.

## 6. Abort Conditions

The gate must latch `HOLD_ABORT` if any condition occurs:

1. bridge state changes away from `DRY_RUN_READY`.
2. NED candidate is stale.
3. candidate contains non-finite values.
4. candidate jump exceeds gate limit.
5. PX4 local position becomes invalid.
6. vehicle unexpectedly enters armed state during a dry-run test.
7. any local publisher appears on `/fmu/in/*` during a dry-run test.

Abort latch reset must be explicit and logged.

## 7. Publisher Audit

Every dry-run verification must write:

1. full ROS topic list.
2. `ros2 topic info --verbose` for every `/fmu/in/*` topic.
3. summary line proving every `/fmu/in/*` topic has `Publisher count: 0`.

PX4 uXRCE-DDS creates `/fmu/in/*` subscriptions, so topic existence alone is not a failure. A nonzero publisher count is a failure before Phase B approval.

## 8. Required Verification Before Phase B

Before any real setpoint publication, these evidence files must exist:

1. bridge dry-run isolation summary.
2. bridge RViz overlay screenshot.
3. PX4/Gazebo read-only frame summary.
4. offboard gate dry-run summary with `phase_b_allowed=false`.
5. forbidden publisher audit with every `/fmu/in/*` publisher count equal to 0.
6. PROCESS_LOG entry listing the exact evidence paths.

## 9. Future Phase B Transition

Phase B can start only after an explicit user instruction that says to enable PX4 setpoint publication.

At that time, the implementation must:

1. create a separate executable for active publication.
2. keep the dry-run gate executable unchanged.
3. publish Offboard heartbeat before trajectory setpoints.
4. never arm until setpoint stream has been stable for the PX4-required pre-roll.
5. log arming state, nav state, publisher count, and abort state.
6. provide a kill/abort path that returns to hold.

## 10. Implemented Dry-run Gate

- executable: `cable_offboard_gate_dry_run`
- script: `scripts/verify_cable_offboard_gate_dry_run.sh`

The script must not start Offboard, must not arm, and must not publish `/fmu/in/*`.

Latest evidence:

- summary: `data/results/cable_offboard_gate_dry_run_20260608_101325/cable_offboard_gate_dry_run_20260608_101325.txt`
- gate state: `data/logs/cable_offboard_gate_state_echo_20260608_101325.log`
- phase B allowed: `data/logs/cable_offboard_gate_allowed_echo_20260608_101325.log`
- forbidden publishers: `data/logs/cable_offboard_gate_forbidden_publishers_20260608_101325.log`

Latest result:

- `decision=accepted_cable_offboard_gate_dry_run_smoke`
- `PHASE_B_READY_DRY_RUN`
- `phase_b_allowed=false`
- `publishes_fmu_in=false`
- every `/fmu/in/*` topic had `Publisher count: 0`

RViz/debug overlay evidence:

- script: `scripts/capture_cable_offboard_gate_dry_run_rviz_overlay.sh`
- RViz config: `ros2_ws/src/zcw_cable_perception/rviz/offboard_gate_dry_run_overlay.rviz`
- summary: `data/results/cable_offboard_gate_rviz_overlay_20260608_101949/cable_offboard_gate_rviz_overlay_20260608_101949.txt`
- screenshot: `data/screenshots/cable_offboard_gate_dry_run_rviz_overlay_20260608_101949.png`
- gate state: `data/logs/cable_offboard_gate_rviz_state_echo_20260608_101949.log`
- phase B allowed: `data/logs/cable_offboard_gate_rviz_allowed_echo_20260608_101949.log`
- forbidden publishers: `data/logs/cable_offboard_gate_rviz_forbidden_publishers_20260608_101949.log`

RViz result:

- `decision=accepted_cable_offboard_gate_rviz_overlay_capture`
- `PHASE_B_READY_DRY_RUN`
- `phase_b_allowed=false`
- `publishes_fmu_in=false`
- every `/fmu/in/*` topic had `Publisher count: 0`
- the screenshot is a debug overlay only; identity `map -> px4_local_ned_dry_run` TF does not prove active PX4 coordinate-loop closure.

## 11. Active Preflight Boundary

The active bridge preflight boundary is documented in:

```bash
docs/06_cable_phase_b_active_bridge_preflight.md
```

Implemented audit:

```bash
scripts/audit_phase_b_active_preflight_boundary.sh
```

Latest evidence:

- summary: `data/results/phase_b_active_preflight_boundary_20260608_102731/phase_b_active_preflight_boundary_20260608_102731.txt`
- static checks: `data/results/phase_b_active_preflight_boundary_20260608_102731/static_checks_20260608_102731.log`
- evidence checks: `data/results/phase_b_active_preflight_boundary_20260608_102731/evidence_checks_20260608_102731.log`

Latest result:

- `decision=accepted_phase_b_active_preflight_boundary`
- `phase_b_approved=false`
- `active_bridge_present=false`
- `publishes_fmu_in=false`

This audit does not approve Phase B. It only proves the current repository boundary remains dry-run-only and that the local evidence needed before future active work is present.
