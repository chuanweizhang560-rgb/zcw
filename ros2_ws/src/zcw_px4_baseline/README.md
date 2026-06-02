# zcw_px4_baseline

This package contains PX4 ROS 2 baseline control entry points adapted from the official
`px4_ros_com` examples.

Current node:

- `offboard_hover_retry`: keeps publishing a fixed NED position setpoint and retries
  Offboard/arm commands until PX4 reports armed Offboard state.

This package is engineering glue for simulation verification. It must not contain wind
turbine or cable inspection algorithms.
