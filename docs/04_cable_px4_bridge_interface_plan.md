# Cable PX4 Bridge Interface Plan

This document defines the planned boundary for a future cable dry-run to PX4 Offboard bridge.

Phase A bridge code is implemented only as a dry-run/debug bridge. It does not publish PX4 input topics.

Current Phase A status:

- `cable_px4_bridge_dry_run` implemented in `zcw_px4_baseline`.
- It publishes only:
  - `/zcw/cable/px4_bridge/state`
  - `/zcw/cable/px4_bridge/ned_setpoint_dry_run`
- Latest evidence:
  - bridge state: `DRY_RUN_READY`
  - `publishes_fmu_in=false`
  - NED frame: `px4_local_ned_dry_run`
  - forbidden `/fmu/in/*` topics: none

## 1. Package Boundary

The bridge must not be implemented inside `zcw_cable_perception`.

Allowed location:

- `ros2_ws/src/zcw_px4_baseline`

Reason:

- `zcw_cable_perception` is a perception and read-only dry-run package.
- `zcw_cable_perception` must not depend on `px4_msgs`.
- `zcw_px4_baseline` already contains official PX4 example-derived Offboard code and already owns `/fmu/in/*` publication.

## 2. Candidate Input Topics

The bridge may subscribe to:

| Topic | Type | Required gate |
|---|---|---|
| `/zcw/cable/dry_run/state` | `std_msgs/String` | starts with `TRACK_READY` |
| `/zcw/cable/dry_run/candidate_setpoint` | `geometry_msgs/PointStamped` | fresh and finite |
| `/zcw/cable/dry_run/path` | `nav_msgs/Path` | optional debug only |
| `/fmu/out/vehicle_status` | `px4_msgs/msg/VehicleStatus` | read-only |
| `/fmu/out/vehicle_local_position` | `px4_msgs/msg/VehicleLocalPosition` | read-only |

The bridge must not subscribe directly to raw perception topics:

- `/camera/points`
- `/zcw/cable/lookahead_target`
- `/zcw/cable/offset_path`

It may only consume the already gated dry-run candidate.

## 3. Candidate Output Topics

Phase A, dry-run bridge:

| Topic | Type | Meaning |
|---|---|---|
| `/zcw/cable/px4_bridge/state` | `std_msgs/String` | bridge state and reason |
| `/zcw/cable/px4_bridge/ned_setpoint_dry_run` | `geometry_msgs/PointStamped` | candidate converted to PX4 local NED frame |

Forbidden in Phase A:

- `/fmu/in/trajectory_setpoint`
- `/fmu/in/offboard_control_mode`
- `/fmu/in/vehicle_command`

Phase B may publish `/fmu/in/*` only after Phase A passes and the user explicitly approves the transition.

## 4. Coordinate Gate

The dry-run candidate is currently in `map` / Gazebo-style ENU-like coordinates.

PX4 `TrajectorySetpoint.position` uses local NED:

- `x`: North
- `y`: East
- `z`: Down

Before any PX4 setpoint publication, the bridge must prove the frame mapping with a logged transform check.

Minimum Phase A transform assumptions:

| Input | Output |
|---|---|
| `map.x` | `ned.x` |
| `map.y` | `ned.y` |
| `map.z` | `ned.z = -map.z` |

This assumption is not enough for real closed-loop flight. It is only acceptable for Phase A dry-run if the output remains on `/zcw/cable/px4_bridge/ned_setpoint_dry_run`.

Required future validation before Phase B:

1. Compare Gazebo model pose, PX4 local position, and candidate setpoint in the same time window.
2. Record at least one RViz/Gazebo screenshot showing frame consistency.
3. Reject the bridge if local origin drift or axis sign mismatch is observed.

## 5. Safety Gates

The bridge must output `HOLD_*` and must not advance its dry-run setpoint unless all gates pass:

| Gate | Required value |
|---|---|
| dry-run state | starts with `TRACK_READY` |
| candidate age | `<= 0.5 s` |
| candidate finite | true |
| NED setpoint finite | true |
| NED horizontal jump | `<= 5.0 m` |
| NED vertical jump | `<= 2.0 m` |
| NED speed estimate | `<= 5.0 m/s` |
| PX4 vehicle status age | `<= 1.0 s` if PX4 is running |
| bridge phase | `PHASE_A_DRY_RUN` |

Phase A must never arm the vehicle.

## 6. Required Verification Script

Implemented verification script:

```bash
scripts/verify_px4_bridge_dry_run_isolation.sh
```

Required behavior:

1. Start `lookahead_path_publisher`.
2. Start `lookahead_safety_monitor`.
3. Start `lookahead_dry_run_setpoint`.
4. Start the future bridge in Phase A only.
5. Echo `/zcw/cable/px4_bridge/state`.
6. Echo `/zcw/cable/px4_bridge/ned_setpoint_dry_run`.
7. Confirm `/fmu/in/trajectory_setpoint` is absent.
8. Confirm `/fmu/in/offboard_control_mode` is absent.
9. Confirm `/fmu/in/vehicle_command` is absent.
10. Confirm no Gazebo/PX4 process is required for this Phase A isolation test.

Latest Phase A evidence:

- bridge state echo: `data/logs/px4_bridge_dry_run_state_echo_20260603_190805.log`
- NED dry-run echo: `data/logs/px4_bridge_dry_run_ned_echo_20260603_190805.log`
- topic list: `data/logs/px4_bridge_dry_run_topic_list_20260603_190805.log`
- forbidden topic log: `data/logs/px4_bridge_dry_run_forbidden_topics_20260603_190805.log`
- RViz overlay screenshot: `data/screenshots/px4_bridge_dry_run_rviz_overlay_20260603_191816.png`
- RViz bridge state echo: `data/logs/px4_bridge_dry_run_rviz_state_echo_20260603_191816.log`
- RViz bridge NED echo: `data/logs/px4_bridge_dry_run_rviz_ned_echo_20260603_191816.log`

## 7. Acceptance Criteria

Phase A passes only if:

1. bridge state reaches `DRY_RUN_READY`.
2. NED dry-run setpoint is finite.
3. NED dry-run jump remains within limits.
4. no `/fmu/in/*` topics exist.
5. `scripts/audit_px4_isolation.sh` still passes for `zcw_cable_perception`.
6. PROCESS_LOG records all evidence paths.

## 8. Explicit Non-Goals

This phase does not:

1. start Gazebo.
2. start PX4.
3. arm a vehicle.
4. publish Offboard heartbeat.
5. publish PX4 trajectory setpoints.
6. claim that the drone can follow the cable.

## 9. RViz Overlay Evidence

Implemented screenshot script:

```bash
scripts/capture_px4_bridge_dry_run_rviz_overlay.sh
```

It starts the read-only lookahead pipeline, Phase A bridge dry-run, static TF and RViz2. It displays:

1. `/zcw/cable/offset_path`
2. `/zcw/cable/lookahead_target`
3. `/zcw/cable/dry_run/path`
4. `/zcw/cable/dry_run/candidate_setpoint`
5. `/zcw/cable/px4_bridge/ned_setpoint_dry_run`

Latest result:

- bridge state: `DRY_RUN_READY`
- `publishes_fmu_in=false`
- NED frame: `px4_local_ned_dry_run`
- forbidden `/fmu/in/*` topics: none

The RViz static transform for `px4_local_ned_dry_run` is debug-only. It is used to render the point and does not prove PX4 local-frame alignment.

## 10. Next Node

The next node should design a PX4/Gazebo read-only coordinate alignment test. It may start Gazebo/PX4 to compare poses, but it must still avoid `/fmu/in/*` publication unless the user explicitly approves the transition to Phase B.
