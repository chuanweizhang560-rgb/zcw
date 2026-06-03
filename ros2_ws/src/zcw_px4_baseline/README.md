# zcw_px4_baseline

This package contains PX4 ROS 2 baseline control entry points adapted from the official
`px4_ros_com` examples.

Current node:

- `offboard_hover_retry`: keeps publishing a fixed NED position setpoint and retries
  Offboard/arm commands until PX4 reports armed Offboard state.
- `offboard_waypoint_sequence`: publishes a fixed NED waypoint sequence through PX4
  Offboard position setpoints and advances using PX4 local-position feedback.
- `cable_px4_bridge_dry_run`: Phase A cable bridge dry-run node. It converts
  `/zcw/cable/dry_run/candidate_setpoint` into a debug NED setpoint under
  `/zcw/cable/px4_bridge/*`; it does not publish `/fmu/in/*`.

This package is engineering glue for simulation verification. It must not contain wind
turbine or cable inspection algorithms.
