# Cable PX4 Dry-Run Gate

This document defines the required gate between the read-only cable lookahead pipeline and any PX4 Offboard setpoint integration.

Current status:

- Perception source: PX4 official `iris_depth_camera` in AerialCore `danube_wires`.
- Geometry chain: PCL multiline RANSAC -> Ceres/Eigen catenary fit -> offset path -> lookahead target.
- Read-only ROS topics:
  - `/zcw/cable/offset_path`
  - `/zcw/cable/lookahead_target`
  - `/zcw/cable/tracking_state`
  - `/zcw/cable/safety_gate`
- Latest safety evidence:
  - `TRACK_READY`
  - `path_points=13`
  - `min_target_to_path_m=0`
  - `last_target_jump_m=10.0005`
  - `safety_gate=true`
- Latest dry-run evidence:
  - `TRACK_READY`
  - `target_to_path_m=0`
  - `candidate_jump_m=1.99995`
  - `candidate_vertical_jump_m=0.0105846`
  - `candidate_speed_mps=5`
  - `publishes_px4=false`
  - forbidden `/fmu/in/*` topics: none
- Latest dry-run RViz evidence:
  - screenshot: `data/screenshots/lookahead_dry_run_rviz_overlay_20260603_175512.png`
  - Global Status: OK
  - Offset Path: OK
  - Lookahead Target: OK
  - Dry Run Path: OK
  - Dry Run Candidate: OK
  - forbidden `/fmu/in/*` topics: none
- Latest PX4 isolation evidence:
  - summary: `data/results/px4_isolation_audit_20260603_180400/px4_isolation_audit_20260603_180310.txt`
  - `package.xml` has no `px4_msgs` dependency
  - CMake does not find/link `px4_msgs`
  - cable perception source has no PX4 message API reference
  - cable perception source does not publish `/fmu/in/*`
  - lookahead scripts do not publish `/fmu/in/*`
  - decision: `accepted_px4_isolation_smoke`

No PX4 Offboard control may consume these topics until the dry-run gates below pass.

## 1. Scope

Dry-run means:

1. Subscribe to cable lookahead and safety topics.
2. Compute the candidate PX4 position setpoint that would be sent.
3. Publish/log the candidate setpoint on a non-PX4 debug topic.
4. Never publish to `/fmu/in/trajectory_setpoint`.
5. Never publish `/fmu/in/vehicle_command`.
6. Never arm the vehicle.

The dry-run node may publish only debug topics under `/zcw/cable/dry_run/*`.

## 2. Required Input Gates

The dry-run node must refuse to produce a candidate setpoint unless all gates pass:

| Gate | Required value |
|---|---|
| `/zcw/cable/safety_gate` | `true` |
| `/zcw/cable/tracking_state` | starts with `TRACK_READY` |
| offset path age | `<= 1.0 s` |
| lookahead target age | `<= 1.0 s` |
| target to path distance | `<= 2.0 m` |
| target jump | `<= 25.0 m` |
| candidate setpoint jump | `<= 5.0 m` |
| candidate vertical jump | `<= 2.0 m` |
| candidate speed estimate | `<= 5.0 m/s` |

If any gate fails, the dry-run output state must be `HOLD` and the candidate setpoint must not advance.

## 3. Dry-Run Output Topics

Allowed debug topics:

| Topic | Type | Meaning |
|---|---|---|
| `/zcw/cable/dry_run/state` | `std_msgs/String` | `WAITING`, `TRACK_READY`, `HOLD_*` |
| `/zcw/cable/dry_run/candidate_setpoint` | `geometry_msgs/PointStamped` | Candidate position that would later feed PX4 |
| `/zcw/cable/dry_run/path` | `nav_msgs/Path` | Candidate setpoint history for RViz |

Forbidden in dry-run:

- `/fmu/in/trajectory_setpoint`
- `/fmu/in/offboard_control_mode`
- `/fmu/in/vehicle_command`

## 4. Verification Sequence

Dry-run verification must run in this order:

1. Start `lookahead_path_publisher`.
2. Start `lookahead_safety_monitor`.
3. Start dry-run node.
4. Echo allowed debug topics.
5. Confirm forbidden PX4 input topics are not published by dry-run.
6. Capture RViz with:
   - green offset path
   - red lookahead target
   - candidate setpoint/path in a third color
7. Check no PX4 arming command was published.
8. Check no Gazebo/PX4/RViz residual processes after the script exits.

## 5. Acceptance Evidence

Required logs:

1. dry-run node log.
2. topic list log.
3. dry-run state echo.
4. candidate setpoint echo.
5. absence check for forbidden PX4 input topics.
6. RViz screenshot.
7. PROCESS_LOG entry.

Required pass criteria:

1. `dry_run/state` reaches `TRACK_READY`.
2. `candidate_setpoint` remains within 5m of the previous candidate.
3. no forbidden PX4 input topic is published by dry-run.
4. RViz screenshot is not blank and shows path, target, and candidate.
5. no residual process remains.

## 6. Next Code Node

`lookahead_dry_run_setpoint.cpp` has passed the first read-only smoke test and RViz overlay evidence.

The next implementation node should design the PX4 Offboard dry-run bridge interface. It must remain a documented interface plan first; code may only be added after the forbidden-topic audit is kept in the verification sequence.
