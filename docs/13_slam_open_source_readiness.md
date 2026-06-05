# SLAM Open-Source Readiness

This document records the SLAM/mapping status and the first safe integration path.

It does not implement SLAM. It prevents the project from inventing a custom SLAM stack.

## 1. Current Status

SLAM is not completed.

Current repository capabilities are adjacent to SLAM, but they are not SLAM:

- Gazebo/PX4/ROS 2 sensor smoke tests.
- depth camera and LiDAR PointCloud2 capture.
- PCL RANSAC cable-line candidates.
- dry-run `map` frame debug topics.
- RViz overlays.
- PX4 local NED and Gazebo pose sampling.

Missing SLAM capabilities:

- no visual-inertial odometry.
- no lidar-inertial odometry.
- no loop closure.
- no persistent global map.
- no OctoMap or occupancy map.
- no map entropy grid.
- no multi-vehicle submap merge.
- no satellite-prior correction.
- no SLAM output feeding planning or RL state.

## 2. Candidate Audit

The project must reuse mature open-source SLAM/mapping packages where practical.

| Candidate | Source | License | ROS 2 Humble fit | Project fit | Decision |
|---|---|---|---|---|---|
| RTAB-Map ROS | https://github.com/introlab/rtabmap_ros | BSD-3-Clause | Strong. Upstream states ROS 2 Humble support and ROS binaries. | Best first mapping candidate for RGB-D/depth camera and 3D LiDAR examples. | Primary Phase S0 candidate. |
| spark-fast-lio | https://github.com/MIT-SPARK/spark-fast-lio | Local clone shows `spark_fast_lio/package.xml` license `GPL` and package-level `LICENSE` is GNU GPL v2. | Strong ROS 2 focus; README and source show direct `sensor_msgs/msg::Imu` + `sensor_msgs/msg::PointCloud2` subscriptions. | Technically the best ROS 2-oriented LIO candidate, but current project input contract and license boundary both block direct adoption. | Audit-only hold. |
| LIO-SAM ROS2 branch/fork | https://github.com/TixiaoShan/LIO-SAM, https://github.com/pixwyh/LIO-SAM-ROS2 | BSD-3-Clause reported by GitHub fork page; verify before use. | Community ROS 2/Humble support exists, but input requirements are strict. | Useful later only if lidar fields include ring/time and IMU extrinsics are credible. | Hold until sensor fields pass audit. |
| LVI-SAM | https://arxiv.org/abs/2104.10831 | Verify implementation license before use. | Original implementation is ROS 1-oriented; ROS 2/Gazebo integration cost is high. | Scientifically aligned with the proposal, but too heavy for first integration. | Defer. |
| OctoMap / occupancy mapping | ROS 2 packages/system packages, exact package to verify locally. | BSD-family upstream; verify package license before use. | Likely available through ROS 2 ecosystem. | Needed after pose source exists; not a pose estimator by itself. | Phase S2 candidate. |

## 3. Recommended Path

Phase S0: RTAB-Map read-only mapping smoke.

- Use existing depth camera PointCloud2 or RGB-D/depth streams.
- Use Gazebo/P3D pose only as a debug/reference source, not as claimed SLAM.
- Verify RTAB-Map node startup and map/database output without controlling PX4.
- Capture RViz screenshot only after real map/point cloud topics render.

Phase S1: LiDAR-inertial odometry candidate.

- Audit Gazebo LiDAR and IMU topic fields first.
- Verify timestamp, frame, ring/time fields and extrinsics.
- Prefer `spark-fast-lio` if ROS 2 build and topic remap are cleaner than LIO-SAM.
- Do not tune or rewrite the estimator core.

Phase S2: Occupancy/entropy bridge.

- Convert accepted SLAM pose/map output to occupancy evidence through existing packages.
- Add a thin entropy audit only after occupancy map exists.
- Entropy must remain a derived metric, not a replacement for SLAM.

Phase S3: Multi-vehicle mapping.

- Only after two-vehicle PX4/ROS namespace isolation and single-vehicle SLAM smoke pass.
- Start with namespaced independent maps.
- Do not attempt submap fusion until per-vehicle maps are stable.

## 4. Immediate Next Allowed Work

Allowed:

1. Add a read-only RTAB-Map smoke wrapper.
2. Use only existing Gazebo sensor topics.
3. Verify RTAB-Map nodes start without PX4 active control.
4. Capture real RViz evidence only after map/point cloud topics render.
5. Update `PROCESS_LOG.md` for every attempt.

Forbidden:

1. Writing a custom SLAM estimator.
2. Claiming PCL RANSAC line extraction is SLAM.
3. Claiming Gazebo ground truth pose is SLAM.
4. Feeding any SLAM output into active PX4 control before a separate safety review.
5. Starting multi-vehicle SLAM before single-vehicle SLAM smoke evidence exists.

## 5. Source Notes

- RTAB-Map ROS GitHub states the `ros2` branch has ROS 2 Humble support and BSD-3-Clause license.
- MIT-SPARK `spark-fast-lio` README presents ROS 2 launch/config flow and FAST-LIO2 mapping usage.
- LIO-SAM ROS2 documentation notes ROS 2 Humble testing but also strict point cloud `time` and `ring` requirements.
- The LVI-SAM paper describes tightly coupled lidar-visual-inertial odometry and robustness when one subsystem fails, but the original implementation is not the fastest ROS 2 Humble path.
- FAST-LIO2 paper reports high-rate lidar-inertial odometry/mapping and open-source implementation, supporting its candidacy for later LIO work.

## 6. RTAB-Map Installation Audit

RTAB-Map was installed from ROS 2 Humble apt packages, not cloned into `third_party/`.

Installed apt package:

```bash
sudo apt-get install -y ros-humble-rtabmap-ros
```

Observed package versions:

- `ros-humble-rtabmap`: `0.22.1-1jammy.20260414.170043`
- `ros-humble-rtabmap-ros`: `0.22.1-1jammy.20260427.161203`
- `ros-humble-rtabmap-slam`: `0.22.1-1jammy.20260427.155807`
- `ros-humble-rtabmap-odom`: `0.22.1-1jammy.20260425.083542`
- `ros-humble-rtabmap-util`: `0.22.1-1jammy.20260422.094350`

Audit command:

```bash
scripts/audit_rtabmap_installation.sh
```

Expected executables:

- `rtabmap_slam rtabmap`
- `rtabmap_odom icp_odometry`
- `rtabmap_odom rgbd_odometry`
- `rtabmap_util point_cloud_xyz`
- `rtabmap_util point_cloud_assembler`

This audit does not start ROS nodes, PX4, Gazebo or RViz. It only checks package and executable availability.

Latest evidence:

- summary: `data/results/rtabmap_installation_20260604_142246/rtabmap_installation_20260604_142246.txt`
- dpkg log: `data/results/rtabmap_installation_20260604_142246/rtabmap_dpkg_20260604_142246.log`
- ROS 2 packages: `data/results/rtabmap_installation_20260604_142246/rtabmap_ros2_packages_20260604_142246.log`
- executables: `data/results/rtabmap_installation_20260604_142246/rtabmap_executables_20260604_142246.log`

Observed result:

```text
decision=accepted_rtabmap_installation
reason=rtabmap_ros2_packages_and_required_executables_present
starts_ros=false
starts_px4=false
starts_gazebo=false
starts_rviz=false
starts_offboard=false
arms=false
publishes_fmu_in=false
missing_count=0
```

## 7. RTAB-Map Node Smoke

Command:

```bash
scripts/verify_rtabmap_node_smoke.sh
```

This smoke starts only the `rtabmap_slam/rtabmap` ROS 2 node with sensor subscriptions disabled. It proves the installed upstream node can start in this environment. It does not prove mapping quality and does not use Gazebo sensor data yet.

Expected boundaries:

- starts ROS: true
- starts PX4: false
- starts Gazebo: false
- starts RViz: false
- starts Offboard: false
- arms: false
- publishes `/fmu/in/*`: false

Next mapping evidence must connect this node or an RTAB-Map odometry/mapping launch to real Gazebo sensor topics.

Latest evidence:

- summary: `data/results/rtabmap_node_smoke_20260604_142712/rtabmap_node_smoke_20260604_142712.txt`
- RTAB-Map log: `data/logs/rtabmap_node_smoke_20260604_142712.log`
- node list: `data/logs/rtabmap_node_list_20260604_142712.log`
- topic list: `data/logs/rtabmap_topic_list_20260604_142712.log`
- database: `data/results/rtabmap_node_smoke_20260604_142712/rtabmap_node_smoke_20260604_142712.db`

Observed result:

```text
decision=accepted_rtabmap_node_smoke
reason=rtabmap_slam_node_started_in_readonly_no_sensor_smoke
starts_ros=true
starts_px4=false
starts_gazebo=false
starts_rviz=false
starts_offboard=false
arms=false
publishes_fmu_in=false
node_ok=true
slam_mode_ok=true
topic_list_ok=true
```

Observed node:

```text
/rtabmap
```

Important limitation:

- This is not mapping evidence.
- It proves only that the RTAB-Map upstream ROS 2 node can start and register in the ROS graph.
- The next accepted SLAM milestone must use real Gazebo sensor topics.

## 8. Gazebo Sensor Input Candidate

Existing depth-camera evidence provides the first RTAB-Map input candidate:

| Topic | Type | Observed frame |
|---|---|---|
| `/camera/points` | `sensor_msgs/msg/PointCloud2` | `camera_link` |
| `/zcw/depth_camera/pose` | `nav_msgs/msg/Odometry` | `frame_id=world`, `child_frame_id=depth_camera::link` |

Evidence from previous sensor smoke:

- point cloud sample: `data/logs/depth_camera_pose_points_sample_20260602_204840.log`
- pose sample: `data/logs/depth_camera_pose_pose_sample_20260602_204840.log`

Integration risk:

- The point cloud uses `camera_link`.
- The odometry child frame uses `depth_camera::link`.
- RTAB-Map needs consistent frame/TF semantics.
- A direct RTAB-Map hookup may fail until a read-only TF/frame bridge is added.

Next accepted milestone:

1. start Gazebo depth camera.
2. start RTAB-Map in scan-cloud mode or an RTAB-Map utility path using `/camera/points`.
3. provide only read-only static/dynamic TF needed for frame consistency.
4. verify map/cloud topics appear.
5. capture RViz evidence if map/cloud topics render.

Still forbidden:

- using Gazebo ground-truth pose as claimed SLAM output.
- feeding RTAB-Map output into PX4 active control.
- treating a static TF workaround as real localization.

## 9. RTAB-Map Depth Camera Smoke

Command:

```bash
scripts/verify_rtabmap_depth_camera_smoke.sh
```

This smoke starts Gazebo depth camera topics, the read-only odometry child-frame bridge and RTAB-Map scan-cloud mode.

Acceptance target:

- `/camera/points` exists and has `frame_id=camera_link`.
- `/zcw/depth_camera/pose` exists.
- `/zcw/rtabmap/odom_camera_link` exists and has `child_frame_id=camera_link`.
- RTAB-Map starts with `subscribe_scan_cloud=true`.
- RTAB-Map output topics appear in the ROS graph.

Boundary:

- starts PX4/Gazebo only to provide sensor topics.
- does not start Offboard.
- does not arm.
- does not publish `/fmu/in/*`.
- uses Gazebo pose only as debug odometry to check RTAB-Map plumbing.
- does not claim SLAM quality or localization accuracy.

Latest evidence:

- summary: `data/results/rtabmap_depth_camera_smoke_20260604_144241/rtabmap_depth_camera_smoke_20260604_144241.txt`
- database: `data/results/rtabmap_depth_camera_smoke_20260604_144241/rtabmap_depth_camera_20260604_144241.db`
- RTAB-Map log: `data/logs/rtabmap_depth_camera_node_20260604_144241.log`
- topic list: `data/logs/rtabmap_depth_camera_topics_20260604_144241.log`
- point cloud sample: `data/logs/rtabmap_depth_camera_points_sample_20260604_144241.log`
- bridged odom sample: `data/logs/rtabmap_depth_camera_odom_sample_20260604_144241.log`

Observed result:

```text
decision=accepted_rtabmap_depth_camera_smoke
reason=rtabmap_started_with_gazebo_depth_camera_topics_and_frame_bridge
starts_ros=true
starts_px4=true
starts_gazebo=true
starts_rviz=false
starts_offboard=false
arms=false
publishes_fmu_in=false
uses_gazebo_sensor_topics=true
uses_gazebo_pose_as_debug_odom=true
claims_slam_quality=false
rtabmap_ok=true
outputs_ok=true
points_ok=true
```

Observed sensor input:

```text
/camera/points
frame_id: camera_link
height: 480
width: 848
```

Observed debug odometry bridge:

```text
/zcw/rtabmap/odom_camera_link
frame_id: world
child_frame_id: camera_link
```

Observed RTAB-Map outputs included:

- `/map`
- `/mapData`
- `/mapGraph`
- `/cloud_map`
- `/octomap_binary`
- `/octomap_full`
- `/octomap_grid`
- `/local_grid_obstacle`

Interpretation:

- Accepted as a Phase S0 open-source plumbing smoke.
- RTAB-Map can start in scan-cloud SLAM mode and consume Gazebo depth-camera PointCloud2 with a consistent odometry child frame.
- This is still not accepted as final SLAM quality evidence because odometry is Gazebo debug pose, loop closure is disabled in scan-cloud-only mode and no independent trajectory/map accuracy metric has been run.

Next SLAM work:

1. Add RViz evidence for RTAB-Map map/cloud topics if visual inspection is needed.
2. Audit Gazebo LiDAR and IMU topic fields for an open-source LIO candidate.
3. Prefer `spark-fast-lio` only if required LiDAR/IMU timing and frame assumptions can be satisfied without rewriting the estimator core.

## 10. RTAB-Map RViz Overlay Review

Static read-only RViz capture was attempted first with no active motion baseline.

Observed result:

- screenshot: `data/screenshots/rtabmap_depth_camera_rviz_overlay_20260605_090748.png`
- issue: RViz showed `Fixed Frame [map] does not...`
- decision: rejected as visual evidence

Interpretation:

- Topic and node startup were valid.
- The screenshot was not valid evidence because the fixed frame was unresolved and the view was effectively empty.

Corrective action:

- RViz fixed frame changed from `map` to `world`.
- Added a read-only static TF `world -> map`.

Second static capture after the fix:

- screenshot: `data/screenshots/rtabmap_depth_camera_rviz_overlay_20260605_090935.png`
- review result: TF issue removed, but the view still contained only sparse TF-scale content and no useful map/cloud structure.

Interpretation:

- Static depth-camera RTAB-Map startup is not enough to produce a useful visual map review in this scenario.
- The missing ingredient is motion, not another custom mapping algorithm.

## 11. RTAB-Map Motion RViz Overlay

Command:

```bash
scripts/capture_rtabmap_depth_camera_motion_rviz_overlay.sh
```

This capture reuses the existing open-source PX4 cable waypoint baseline to create motion while RTAB-Map runs in scan-cloud mode.

Important boundary:

- starts PX4/Gazebo/ROS/RViz.
- starts Offboard and arms through the existing waypoint baseline.
- does not start the cable Phase B active bridge.
- does not use RTAB-Map output for control.
- still uses Gazebo pose only as debug odometry for plumbing.
- does not claim SLAM accuracy or final mapping quality.

Latest evidence:

- summary: `data/results/rtabmap_depth_camera_motion_rviz_overlay_20260605_091350/rtabmap_depth_camera_motion_rviz_overlay_20260605_091350.txt`
- screenshot: `data/screenshots/rtabmap_depth_camera_motion_rviz_overlay_20260605_091350.png`
- vehicle status: `data/logs/rtabmap_depth_camera_motion_vehicle_status_20260605_091350.log`
- Offboard log: `data/logs/rtabmap_depth_camera_motion_offboard_20260605_091350.log`
- RTAB-Map log: `data/logs/rtabmap_depth_camera_motion_rtabmap_20260605_091350.log`

Observed result:

```text
decision=accepted_rtabmap_depth_camera_motion_rviz_overlay
starts_rviz=true
starts_offboard=true
arms=true
publishes_fmu_in=true
rtabmap_ok=true
outputs_ok=true
motion_ok=true
screenshot_ok=1
```

Observed motion evidence:

- `arming_state: 2`
- `nav_state: 14`
- waypoint log advanced through waypoints 1 to 5 and then held the final waypoint

Screenshot review:

- The RViz frame is no longer blank.
- A sparse line-like structure is visible in the main view, aligned with the cable corridor.
- This is acceptable as a motion-backed visual smoke, but it is still sparse and not a dense final map product.

Interpretation:

- RTAB-Map plus real Gazebo depth-camera input plus a mature waypoint baseline can produce non-empty mapping evidence in motion.
- This is the first acceptable visual proof that the open-source mapping chain is alive in a moving inspection scenario.
- It is still not a final SLAM completion milestone because odometry is debug pose, the rendered structure is sparse and no quantitative map or trajectory accuracy metric has been run.

## 12. LIO Input Readiness Audit

Command:

```bash
scripts/audit_lio_input_readiness.sh
```

This audit checks whether the current foggy-lidar simulation inputs are already compatible with mature open-source LIO candidates without rewriting their estimator cores.

Audit scope:

- starts PX4/Gazebo and MicroXRCE.
- inspects `/zcw/foggy_lidar/points`.
- inspects `/fmu/out/sensor_combined`.
- does not start Offboard.
- does not arm.
- does not publish `/fmu/in/*`.

Latest evidence:

- summary: `data/results/lio_input_readiness_20260605_092427/lio_input_readiness_20260605_092427.txt`
- topics: `data/logs/lio_input_topics_20260605_092427.log`
- point cloud sample: `data/logs/lio_input_points_sample_20260605_092427.log`
- IMU candidate sample: `data/logs/lio_input_sensor_combined_sample_20260605_092427.log`

Observed result:

```text
decision=rejected_lio_input_readiness
reason=foggy_lidar_pointcloud_missing_ring_time_and_only_px4_sensor_combined_imu
pointcloud_fields=x,y,z,intensity
pointcloud_has_ring=false
pointcloud_has_time=false
imu_topic=/fmu/out/sensor_combined
imu_topic_type=px4_msgs/msg/SensorCombined
imu_is_native_ros_imu=false
spark_fast_lio_direct_ready=false
lio_sam_direct_ready=false
```

Observed input facts:

- `sensor_msgs/msg/PointCloud2` exists on `/zcw/foggy_lidar/points`.
- The point cloud fields are only `x,y,z,intensity`.
- No `ring` field was observed.
- No `time` field was observed.
- The only IMU-like bridge output found for this audit path is `/fmu/out/sensor_combined`.
- That topic is `px4_msgs/msg/SensorCombined`, not `sensor_msgs/msg/Imu`.

Interpretation:

- Current foggy-lidar ROS inputs are not accepted as direct-feed inputs for `spark-fast-lio`.
- Current foggy-lidar ROS inputs are not accepted as direct-feed inputs for `LIO-SAM`.
- The immediate blocker is not algorithm quality. It is input contract mismatch.
- `spark-fast-lio` remains the better later candidate because it is more ROS 2 native, but it still needs a credible IMU path and likely a clearer point timestamp story before adoption.
- `LIO-SAM` stays on hold because the current point cloud does not expose the `ring/time` style fields that LIO-SAM class integrations typically depend on.

Next allowed work:

1. Audit whether a mature ROS-side IMU bridge to `sensor_msgs/Imu` can be introduced without inventing estimator logic.
2. Audit whether another existing PX4/Gazebo lidar model in the current stack exposes timestamp or ring-like fields.
3. Clone and license-review `spark-fast-lio` locally in `third_party/` before any build attempt.

## 13. SPARK-FAST-LIO Upstream Audit

Local clone:

- path: `third_party/spark-fast-lio`
- commit: `17b36d293a14df37d57e1751a337a32e2f164692`

Observed upstream facts:

- README presents a ROS 2 workflow and custom config files for Velodyne/Ouster-style setups.
- `spark_fast_lio/src/spark_fast_lio.cpp` subscribes directly to `sensor_msgs/msg/PointCloud2` and `sensor_msgs/msg/Imu`.
- `spark_fast_lio/package.xml` declares `<license>GPL</license>`.
- `spark_fast_lio/LICENSE` is GNU GPL version 2.
- The repository root does not currently expose a separate top-level `LICENSE` file in this clone.

Interpretation:

- From a technical integration perspective, `spark-fast-lio` is aligned with ROS 2 and cleaner than LIO-SAM.
- From a project-governance perspective, it is not a drop-in default choice here because:
  - current foggy-lidar inputs do not meet the direct subscription contract, and
  - package licensing is GPL v2, so it must be treated as a separately reviewed candidate rather than an automatically acceptable dependency.

Current decision:

- keep `spark-fast-lio` in `third_party/` for audit only.
- do not build or wire it into the main repository flow yet.
