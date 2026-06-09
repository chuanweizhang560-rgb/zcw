# Current Status And Next Steps

This document is the current handoff summary for the repository.

It does not approve cable Phase B active control. It records what is currently runnable, what evidence exists, and what remains open.

## 1. Global Boundary

- Stack remains Gazebo 11 + ROS 2 Humble + PX4 SITL.
- The repository scope remains wind turbine inspection and cable inspection only.
- The project still follows the rule-baseline-first path.
- Mature upstream components remain preferred. Current SLAM baseline is RTAB-Map RGB-D from ROS Humble packages.
- Cable Phase B active bridge is still not implemented and not approved.
- Cable lookahead/gate outputs are still dry-run only.

## 2. Cable Status

Current cable geometry candidate:

- offset path: `data/results/catenary_offset_yz_zbin2_step5_20260608_000000/depth_camera_motion_catenary_offset_yz_zbin2_step5_offset_path_20260608_085655.csv`
- lookahead targets: `data/results/lookahead_target_step5_20m_strict_20260608_090000/depth_camera_motion_lookahead_step5_20m_strict_targets_20260608_085945.csv`
- group: `y8_z20`

Accepted evidence:

- geometry and Frenet consistency accepted.
- ROS topic and RViz overlay accepted.
- safety monitor and dry-run candidate accepted.
- Phase A bridge dry-run isolation accepted.
- PX4/Gazebo offboard gate dry-run accepted with `phase_b_allowed=false`.
- gate RViz/debug overlay accepted.
- dry-run readiness accepted.

Important boundary:

- `/fmu/in/*` topics may appear when PX4 uXRCE-DDS is running, but current cable gate evidence requires their publisher count to be `0`.
- No cable active bridge exists.
- No cable lookahead/gate setpoint is published to PX4 active input topics.

Next cable work:

- Do not implement active bridge without explicit approval.
- Useful safe next nodes are better dry-run evidence, stricter coordinate-frame audits, or offline tracking/coverage analysis.

## 3. Wind Status

Current wind rule candidates:

- default accepted baseline: `single_vehicle_wind_turbine_multilevel_orbit.launch.py` at 20m radius.
- preferred observation candidate: `single_vehicle_wind_turbine_multilevel_orbit_r15.launch.py` at 15m radius.

Accepted evidence:

- multilevel orbit static geometry audit accepted.
- headless and GUI motion evidence accepted.
- 15m useful-depth audit accepted and modestly better than 20m.
- 15m static clearance accepted: minimum static clearance `3.119593m`.
- 15m static visibility accepted: best frame-fill ratio `0.109478`, better than 20m `0.092567`.
- 15m RTAB-Map RGB-D motion-backed RViz evidence accepted.
- static mesh-vertex frustum coverage upper-bound accepted for both 20m and 15m.

Important boundary:

- Static visibility/frustum coverage does not model occlusion, surface normals, dynamic collision, or useful depth.
- RTAB-Map screenshots are SLAM plumbing evidence, not inspection coverage certificates.
- 15m is preferred for observation experiments, but not final coverage readiness.

Next wind work:

- Implement a stricter offline coverage audit that combines frustum, depth usefulness, and surface-normal/view-angle checks.
- Keep 20m as the conservative accepted rule baseline until dynamic safety and coverage evidence justify promotion.

## 4. SLAM Status

Current SLAM baseline:

- RTAB-Map RGB-D is the primary single-vehicle SLAM smoke baseline.
- scan-cloud mode remains fallback/comparison only.

Accepted evidence:

- RTAB-Map installation audit accepted.
- RGB-D smoke accepted.
- RGB-D consistency accepted.
- RGB-D RViz overlay accepted.
- cable motion-backed RGB-D RViz accepted.
- wind 15m motion-backed RGB-D RViz accepted.

Important boundary:

- Gazebo pose / P3D odometry is used as debug/reference odometry in current smoke tests.
- SLAM output is not used for PX4 control.
- No quantitative SLAM accuracy, loop-closure quality, or map-to-ground-truth metric is complete.

Next SLAM work:

- Add map quality metrics before claiming SLAM completion.
- Keep RTAB-Map output out of active control until a separate safety review exists.

## 5. Multi-Vehicle Status

Current status:

- PX4/Gazebo Classic multi-vehicle readiness has been audited separately.
- Multi-vehicle task planning/RL is not implemented.
- Current reliable evidence is mostly single-vehicle baseline, mapping, and dry-run control-gate evidence.

Next multi-vehicle work:

- Keep first multi-vehicle node read-only or dry-run.
- Validate namespaces, DDS keys, and topic isolation before any multi-vehicle control.
- Do not combine multi-vehicle, SLAM feedback, and active cable setpoint publication in one step.

## 6. Immediate Next Recommended Node

Recommended next node:

1. Add a wind coverage-quality audit that combines:
   - frustum visibility,
   - useful depth statistics,
   - surface-normal/view-angle filtering if mesh normals can be recovered from the Collada asset,
   - per-height-band and per-orbit-level coverage summaries.

Reason:

- The project now has enough wind geometry and RTAB-Map smoke evidence.
- The largest remaining wind gap is not movement; it is coverage validity.

Safety boundary for that node:

- It should be offline/read-only first.
- It should not start PX4, Gazebo, RViz, Offboard or arm.
- It should not publish `/fmu/in/*`.
