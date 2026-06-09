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

## 9. Foggy LiDAR ROS IMU Bridge Audit

Command:

```bash
scripts/verify_foggy_lidar_imu_bridge.sh
```

Purpose:

- Start the existing upstream `iris_foggy_lidar` plus AerialCore `danube_wires` world.
- Inspect the ROS 2 graph exposed by the current Gazebo ROS path.
- Verify whether a native ROS 2 IMU topic exists for direct reuse by mature LIO candidates.

Observed result:

- The ROS 2 graph exposed only:
  - `/zcw/foggy_lidar/points`
  - `/zcw/foggy_lidar/pose`
- No native `/imu` topic appeared.
- No `/fmu/out/sensor_combined` topic appeared in this Gazebo ROS-only path.

Latest evidence:

- summary: `data/results/foggy_lidar_imu_bridge_20260605_093722/foggy_lidar_imu_bridge_20260605_093722.txt`
- topic list: `data/logs/foggy_lidar_imu_bridge_topics_20260605_093722.log`
- PX4/Gazebo log: `data/logs/foggy_lidar_imu_bridge_px4_20260605_093722.log`

Observed summary:

```text
decision=rejected_foggy_lidar_native_imu_bridge
reason=native_ros_imu_topic_missing
imu_topic=/imu
imu_topic_present=false
sensor_combined_topic=/fmu/out/sensor_combined
sensor_combined_present=false
```

Interpretation:

- The current foggy-lidar Gazebo ROS export path is pointcloud-plus-pose only.
- It does not provide a native ROS 2 `sensor_msgs/msg/Imu` contract.
- Combined with the earlier Micro XRCE audit, the stack now has two separate limitations:
  - Gazebo ROS path: has pointcloud and pose, but no IMU.
  - PX4 ROS 2 bridge path: exposes `px4_msgs/msg/SensorCombined`, not `sensor_msgs/msg/Imu`.

Decision:

- Reject direct use of mature LIO packages on the current foggy-lidar path.
- Continue asset search for an upstream-compatible sensor chain that exposes:
  - `sensor_msgs/msg/PointCloud2`
  - `sensor_msgs/msg/Imu`
  - and preferably lidar per-point timing fields where required.

## 10. PX4Vision Upstream Sensor Contract Audit

Command:

```bash
scripts/verify_px4vision_ros_contract.sh
```

Purpose:

- Start the upstream PX4 `px4vision` model in the existing Gazebo Classic + AerialCore cable world.
- Verify whether this model can expose a better ROS 2 sensor contract than `iris_foggy_lidar`.
- Check for native ROS 2 IMU and depth-pointcloud topics in the real running graph.

Observed result:

- No native `/imu` topic appeared in the ROS 2 graph.
- No depth camera or pointcloud topic appeared in the ROS 2 graph.
- Gazebo log showed the real blocker:
  - `Failed to load plugin libgazebo_ros_openni_kinect.so`

Local environment check:

- Present: `/opt/ros/humble/lib/libgazebo_ros_camera.so`
- Missing: `/opt/ros/humble/lib/libgazebo_ros_openni_kinect.so`

Latest evidence:

- summary: `data/results/px4vision_ros_contract_20260605_094630/px4vision_ros_contract_20260605_094630.txt`
- topic list: `data/logs/px4vision_ros_contract_topics_20260605_094630.log`
- filtered topics: `data/logs/px4vision_ros_contract_topics_filtered_20260605_094630.log`
- PX4/Gazebo log: `data/logs/px4vision_ros_contract_px4_20260605_094630.log`

Observed summary:

```text
decision=rejected_px4vision_ros_contract
reason=native_ros_imu_missing_or_no_pointcloud
native_imu_present=false
pointcloud_topics_count=0
```

Interpretation:

- `px4vision` is not a drop-in upgrade path in the current locked environment.
- The rejection is not just a topic mismatch. The upstream model references a ROS-Gazebo plugin that is unavailable in the present ROS 2 Humble installation.
- This makes `px4vision` a blocked candidate for immediate reuse under the current stack lock.

Decision:

- Reject `px4vision` as the immediate SLAM sensor-contract baseline in the current environment.
- Keep `iris_depth_camera` plus RTAB-Map as the primary visual/depth SLAM path already proven to start.

## 11. Official Camera Model Compatibility Triage

Static audit basis:

- `models/depth_camera/depth_camera.sdf`
- `models/iris_depth_camera/iris_depth_camera.sdf`
- `models/iris_downward_depth_camera/iris_downward_depth_camera.sdf`
- `models/stereo_camera/stereo_camera.sdf`
- `models/iris_stereo_camera/iris_stereo_camera.sdf`
- `models/iris_triple_depth_camera/iris_triple_depth_camera.sdf`
- local plugin inventory under `/opt/ros/humble/lib`

Observed plugin dependencies:

| Model | Upstream sensor plugin path | Local plugin availability | Current decision |
|---|---|---|---|
| `iris_depth_camera` | inherits `depth_camera`, which uses `libgazebo_ros_camera.so` | Present | Keep |
| `iris_downward_depth_camera` | inherits `depth_camera`, which uses `libgazebo_ros_camera.so` | Present | Keep |
| `iris_stereo_camera` | inherits `stereo_camera`, which uses `libgazebo_ros_multicamera.so` | Missing | Reject for now |
| `iris_triple_depth_camera` | embeds three depth sensors using `libgazebo_ros_openni_kinect.so` | Missing | Reject for now |
| `px4vision` | embeds depth sensor using `libgazebo_ros_openni_kinect.so` | Missing | Reject for now |

Implication:

- Under the current stack lock, the only official PX4 camera family already aligned with installed Gazebo ROS plugins is the `depth_camera` line.
- This reinforces the current single-vehicle SLAM priority:
  - `iris_depth_camera` first
  - `iris_downward_depth_camera` optional follow-up variant
  - RTAB-Map as the first mature upstream mapping package

Non-priority candidates:

- `px4vision`
- `iris_triple_depth_camera`
- `iris_stereo_camera`

They are not rejected because the idea is bad. They are rejected because the required Gazebo ROS plugins are absent in the current locked environment, and the project rules do not allow drifting into custom sensor/plugin work just to resurrect them.

## 12. Depth Camera RGB-D Contract Audit

Command:

```bash
scripts/verify_depth_camera_rgbd_imu_contract.sh
```

Purpose:

- Re-check the `iris_depth_camera` line using the already proven direct-model launch path.
- Verify whether the current environment exposes a standard RGB-D input contract.
- Verify whether a native ROS 2 `/imu` topic is part of that contract.

Observed result:

- Present:
  - `/camera/image_raw` as `sensor_msgs/msg/Image`
  - `/camera/camera_info` as `sensor_msgs/msg/CameraInfo`
  - `/camera/depth/image_raw` as `sensor_msgs/msg/Image`
  - `/camera/depth/camera_info` as `sensor_msgs/msg/CameraInfo`
  - `/camera/points` as `sensor_msgs/msg/PointCloud2`
- Missing:
  - `/imu`

Latest evidence:

- summary: `data/results/depth_camera_rgbd_imu_contract_20260605_095527/depth_camera_rgbd_imu_contract_20260605_095527.txt`
- topic list: `data/logs/depth_camera_rgbd_imu_contract_topics_20260605_095527.log`
- PX4/Gazebo log: `data/logs/depth_camera_rgbd_imu_contract_px4_20260605_095527.log`

Observed summary:

```text
decision=rejected_depth_camera_rgbd_imu_contract
reason=required_rgbd_or_imu_topics_missing
/camera/image_raw=[sensor_msgs/msg/Image]
/camera/camera_info=[sensor_msgs/msg/CameraInfo]
/camera/depth/image_raw=[sensor_msgs/msg/Image]
/camera/depth/camera_info=[sensor_msgs/msg/CameraInfo]
/camera/points=[sensor_msgs/msg/PointCloud2]
/imu=missing
```

Interpretation:

- The `iris_depth_camera` line is a strong RGB-D contract.
- It is not a stable RGB-D-plus-IMU contract in the current environment.
- This means the immediate mapping path should prefer mature RGB-D SLAM modes that do not require IMU input.

Decision:

- Keep `iris_depth_camera` as the primary sensor baseline.
- Narrow the next SLAM path to RTAB-Map RGB-D or scan-cloud modes, without assuming IMU availability.

## 13. RTAB-Map RGB-D Smoke

Command:

```bash
scripts/verify_rtabmap_depth_camera_rgbd_smoke.sh
```

Purpose:

- Use the already accepted `iris_depth_camera` RGB-D contract.
- Reuse the existing odom child-frame bridge.
- Start upstream RTAB-Map in standard RGB-D subscription mode, not scan-cloud mode.

Observed result:

- RTAB-Map started in SLAM mode.
- RTAB-Map reported:
  - `subscribe_depth = true`
  - `subscribe_rgb = true`
  - `subscribe_scan_cloud = false`
- RTAB-Map subscribed to:
  - `/zcw/rtabmap/odom_camera_link`
  - `/camera/image_raw`
  - `/camera/depth/image_raw`
  - `/camera/camera_info`
- Output topics appeared, including:
  - `/map`
  - `/mapData`
  - `/mapGraph`
  - `/cloud_map`
  - `/octomap_*`

Latest evidence:

- summary: `data/results/rtabmap_depth_camera_rgbd_smoke_20260605_100320/rtabmap_depth_camera_rgbd_smoke_20260605_100320.txt`
- RTAB-Map log: `data/logs/rtabmap_depth_camera_rgbd_node_20260605_100320.log`
- topic list: `data/logs/rtabmap_depth_camera_rgbd_topics_20260605_100320.log`
- RGB sample: `data/logs/rtabmap_depth_camera_rgbd_rgb_sample_20260605_100320.log`
- depth sample: `data/logs/rtabmap_depth_camera_rgbd_depth_sample_20260605_100320.log`
- odom sample: `data/logs/rtabmap_depth_camera_rgbd_odom_sample_20260605_100320.log`
- database: `data/results/rtabmap_depth_camera_rgbd_smoke_20260605_100320/rtabmap_depth_camera_rgbd_20260605_100320.db`

Observed summary:

```text
decision=accepted_rtabmap_depth_camera_rgbd_smoke
reason=rtabmap_rgbd_mode_started_with_depth_camera_contract
starts_offboard=false
arms=false
publishes_fmu_in=false
rtabmap_rgbd_mode=true
```

Interpretation:

- The project now has two accepted single-vehicle RTAB-Map entry paths on mature upstream code:
  - scan-cloud mode
  - RGB-D mode
- Under the current locked environment, RGB-D mode is the cleaner primary path because its sensor contract is explicit and already validated.
- `/imu` may appear in broader topic graphs during some runs, but it has not passed a stable standalone contract audit and must not be assumed as a required input.

Decision:

- Promote RTAB-Map RGB-D to the primary single-vehicle SLAM smoke baseline.
- Keep RTAB-Map scan-cloud as a secondary fallback path.

## 14. RTAB-Map RGB-D RViz Evidence

Command:

```bash
scripts/capture_rtabmap_depth_camera_rgbd_rviz_overlay.sh
```

Purpose:

- Capture a real RViz screenshot for the promoted RGB-D baseline.
- Verify that map/cloud/octomap topics are not only present in the graph, but also render with meaningful visible structure.

Observed result:

- The capture succeeded.
- RTAB-Map ran in RGB-D mode.
- RViz rendered:
  - `/cloud_map`
  - `/octomap_occupied_space`
  - `/map`
- The screenshot shows visible line-like overhead structure plus a localized fan-shaped depth-derived cloud near the camera pose.

Latest evidence:

- summary: `data/results/rtabmap_depth_camera_rgbd_rviz_overlay_20260605_100717/rtabmap_depth_camera_rgbd_rviz_overlay_20260605_100717.txt`
- screenshot: `data/screenshots/rtabmap_depth_camera_rgbd_rviz_overlay_20260605_100717.png`
- RTAB-Map log: `data/logs/rtabmap_depth_camera_rgbd_rviz_node_20260605_100717.log`
- topic list: `data/logs/rtabmap_depth_camera_rgbd_rviz_topics_20260605_100717.log`

Observed summary:

```text
decision=accepted_rtabmap_depth_camera_rgbd_rviz_overlay
reason=rtabmap_rgbd_map_cloud_octomap_rendered_in_rviz_capture
starts_offboard=false
arms=false
publishes_fmu_in=false
```

Visual assessment:

- Accepted as real visual evidence.
- Better than the earlier static scan-cloud capture because the rendered structure is easier to interpret.
- Still smoke-grade only:
  - the mapped structure is sparse
  - the visible geometry is local
  - this is not yet a high-quality persistent global inspection map

Decision:

- Keep this screenshot as the first accepted RViz evidence for the RGB-D baseline.
- Use RGB-D mode as the main single-vehicle SLAM smoke path going forward.

Supplemental re-check on 2026-06-08:

- command: `SETTLE_SEC=10 scripts/capture_rtabmap_depth_camera_rgbd_rviz_overlay.sh`
- summary: `data/results/rtabmap_depth_camera_rgbd_rviz_overlay_20260608_104629/rtabmap_depth_camera_rgbd_rviz_overlay_20260608_104629.txt`
- screenshot: `data/screenshots/rtabmap_depth_camera_rgbd_rviz_overlay_20260608_104629.png`
- RTAB-Map log: `data/logs/rtabmap_depth_camera_rgbd_rviz_node_20260608_104629.log`
- RViz log: `data/logs/rtabmap_depth_camera_rgbd_rviz_20260608_104629.log`
- topics log: `data/logs/rtabmap_depth_camera_rgbd_rviz_topics_20260608_104629.log`
- result: `decision=accepted_rtabmap_depth_camera_rgbd_rviz_overlay`
- `rtabmap_ok=true`
- `outputs_ok=true`
- `screenshot_ok=1`
- boundary: starts ROS/PX4/Gazebo/RViz for RGB-D mapping visualization, does not start Offboard, does not arm, and publishes no `/fmu/in/*`.

Manual screenshot review: RViz Global Status is OK; `Cloud Map`, `Octomap Occupied Space` and `Map` displays are OK; the screenshot is non-empty and shows visible cloud/octomap/map structure. This is still plumbing and visualization evidence, not a quantitative SLAM accuracy certificate.

## 15. RTAB-Map RGB-D Consistency Audit

Command:

```bash
RUNS=3 scripts/audit_rtabmap_depth_camera_rgbd_consistency.sh
```

Purpose:

- Check whether the promoted RGB-D smoke baseline is repeatable.
- Avoid treating a one-off successful run as a stable mainline.

Observed result:

- All 3 runs succeeded.
- All 3 runs produced accepted RGB-D smoke summaries.
- No run required Offboard or arm.

Latest evidence:

- summary: `data/results/rtabmap_depth_camera_rgbd_consistency_20260605_101709/rtabmap_depth_camera_rgbd_consistency_20260605_101709.txt`
- run 1: `data/results/rtabmap_depth_camera_rgbd_smoke_20260605_101709/rtabmap_depth_camera_rgbd_smoke_20260605_101709.txt`
- run 2: `data/results/rtabmap_depth_camera_rgbd_smoke_20260605_101737/rtabmap_depth_camera_rgbd_smoke_20260605_101737.txt`
- run 3: `data/results/rtabmap_depth_camera_rgbd_smoke_20260605_101804/rtabmap_depth_camera_rgbd_smoke_20260605_101804.txt`

Observed summary:

```text
decision=accepted_rtabmap_depth_camera_rgbd_consistency
reason=all_rgbd_smoke_runs_succeeded_and_were_accepted
runs=3
success_count=3
failure_count=0
accepted_count=3
```

Interpretation:

- The current RGB-D smoke baseline is repeatable enough to serve as the default single-vehicle SLAM mainline in this repository.
- This does not mean mapping quality is solved.
- It means the integration path itself is now stable enough for downstream work.

Decision:

- Treat RTAB-Map RGB-D as the repository's primary single-vehicle SLAM smoke baseline.
- Keep scan-cloud mode as fallback and comparison path only.

Supplemental re-check on 2026-06-08:

- command: `RUNS=2 scripts/audit_rtabmap_depth_camera_rgbd_consistency.sh`
- summary: `data/results/rtabmap_depth_camera_rgbd_consistency_20260608_104242/rtabmap_depth_camera_rgbd_consistency_20260608_104242.txt`
- run 1: `data/results/rtabmap_depth_camera_rgbd_smoke_20260608_104242/rtabmap_depth_camera_rgbd_smoke_20260608_104242.txt`
- run 2: `data/results/rtabmap_depth_camera_rgbd_smoke_20260608_104312/rtabmap_depth_camera_rgbd_smoke_20260608_104312.txt`
- result: `decision=accepted_rtabmap_depth_camera_rgbd_consistency`
- `runs=2`
- `success_count=2`
- `failure_count=0`
- `accepted_count=2`
- boundary: starts ROS/PX4/Gazebo for depth-camera input, does not start RViz, does not start Offboard, does not arm, and publishes no `/fmu/in/*`.

This supplemental run keeps the earlier 3-run evidence valid and confirms that RTAB-Map RGB-D remains the primary single-vehicle SLAM smoke baseline.

## 16. RTAB-Map RGB-D Motion RViz Evidence

Command:

```bash
scripts/capture_rtabmap_depth_camera_rgbd_motion_rviz_overlay.sh
```

Purpose:

- Verify the promoted RGB-D baseline under real cable-waypoint flight motion.
- Require both:
  - actual PX4 Offboard motion evidence
  - actual RViz rendering evidence

Observed result:

- The run was accepted.
- PX4 entered armed Offboard flight.
- Cable waypoint baseline advanced through multiple waypoints and held the final waypoint.
- RTAB-Map RGB-D mode stayed active.
- RViz rendered:
  - `/cloud_map`
  - `/map`
  - `/octomap_occupied_space`

Latest evidence:

- summary: `data/results/rtabmap_depth_camera_rgbd_motion_rviz_overlay_20260605_102654/rtabmap_depth_camera_rgbd_motion_rviz_overlay_20260605_102654.txt`
- screenshot: `data/screenshots/rtabmap_depth_camera_rgbd_motion_rviz_overlay_20260605_102654.png`
- RTAB-Map log: `data/logs/rtabmap_depth_camera_rgbd_motion_rviz_rtabmap_20260605_102654.log`
- waypoint motion log: `data/logs/rtabmap_depth_camera_rgbd_motion_rviz_offboard_20260605_102654.log`
- topic list: `data/logs/rtabmap_depth_camera_rgbd_motion_rviz_topics_20260605_102654.log`

Observed summary:

```text
decision=accepted_rtabmap_depth_camera_rgbd_motion_rviz_overlay
reason=rtabmap_rgbd_motion_backed_rviz_capture_completed
starts_offboard=true
arms=true
rtabmap_ok=true
outputs_ok=true
motion_ok=true
screenshot_ok=1
```

Visual assessment:

- Accepted as motion-backed visual evidence.
- The screenshot shows a more extended, trajectory-linked structure than the static RGB-D RViz capture.
- It is still not a production-grade global map. It is a stronger smoke artifact proving that the RGB-D baseline remains externally visible during real baseline motion.

Decision:

- Promote this as the strongest current single-vehicle SLAM evidence in the repository.
- Use it as the default reference when evaluating later coupling between inspection trajectory and mapping coverage.

Supplemental re-check on 2026-06-08:

- command: `SETTLE_SEC=10 scripts/capture_rtabmap_depth_camera_rgbd_motion_rviz_overlay.sh`
- summary: `data/results/rtabmap_depth_camera_rgbd_motion_rviz_overlay_20260608_104943/rtabmap_depth_camera_rgbd_motion_rviz_overlay_20260608_104943.txt`
- screenshot: `data/screenshots/rtabmap_depth_camera_rgbd_motion_rviz_overlay_20260608_104943.png`
- RTAB-Map log: `data/logs/rtabmap_depth_camera_rgbd_motion_rviz_rtabmap_20260608_104943.log`
- waypoint motion log: `data/logs/rtabmap_depth_camera_rgbd_motion_rviz_offboard_20260608_104943.log`
- vehicle status log: `data/logs/rtabmap_depth_camera_rgbd_motion_rviz_vehicle_status_20260608_104943.log`
- local position log: `data/logs/rtabmap_depth_camera_rgbd_motion_rviz_vehicle_local_position_20260608_104943.log`
- topics log: `data/logs/rtabmap_depth_camera_rgbd_motion_rviz_topics_20260608_104943.log`
- result: `decision=accepted_rtabmap_depth_camera_rgbd_motion_rviz_overlay`
- `rtabmap_ok=true`
- `outputs_ok=true`
- `motion_ok=true`
- `screenshot_ok=1`
- boundary: this uses the existing cable waypoint rule baseline, so it starts Offboard, arms, and publishes PX4 input topics for that baseline; it is not the cable Phase B active bridge and does not consume cable lookahead/gate setpoints.

Manual screenshot review: RViz Global Status is OK, `Cloud Map` is OK, and the screenshot is non-empty with visible motion-backed cloud/map structure. It remains smoke evidence for SLAM plumbing during motion, not a final SLAM accuracy or mapping-quality certificate.

## 17. RTAB-Map RGB-D Wind Motion RViz Evidence

Command:

```bash
scripts/capture_rtabmap_depth_camera_rgbd_wind_rviz_overlay.sh
```

Purpose:

- Verify the same promoted RGB-D mapping baseline in the wind turbine task world.
- Require actual PX4 Offboard motion and an actual RViz screenshot.
- Keep the evidence scoped to SLAM plumbing and visualization. It does not claim turbine surface coverage completion.

Observed result:

- The run was accepted.
- PX4 entered armed Offboard flight.
- The wind turbine waypoint baseline advanced through waypoints 1 to 5 and then held the final waypoint.
- RTAB-Map RGB-D mode stayed active.
- RViz rendered:
  - `/cloud_map`
  - `/map`
  - `/octomap_occupied_space`

Latest evidence:

- summary: `data/results/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260605_141134/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260605_141134.txt`
- screenshot: `data/screenshots/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260605_141134.png`
- RTAB-Map log: `data/logs/rtabmap_depth_camera_rgbd_wind_rviz_rtabmap_20260605_141134.log`
- waypoint motion log: `data/logs/rtabmap_depth_camera_rgbd_wind_rviz_offboard_20260605_141134.log`
- topic list: `data/logs/rtabmap_depth_camera_rgbd_wind_rviz_topics_20260605_141134.log`

Observed summary:

```text
decision=accepted_rtabmap_depth_camera_rgbd_wind_rviz_overlay
reason=rtabmap_rgbd_wind_motion_backed_rviz_capture_completed
world=wind_turbine
model=iris_depth_camera
launch=single_vehicle_wind_turbine_inspection.launch.py
rtabmap_ok=true
outputs_ok=true
motion_ok=true
screenshot_ok=1
```

Visual assessment:

- Accepted as wind-task motion-backed SLAM smoke evidence.
- The screenshot is non-empty and shows cloud map, octomap and trajectory-linked strip structures.
- The current wind waypoint baseline does not yet prove dense turbine surface coverage.
- The RTAB-Map log contains repeated depth NaN warnings, so the next wind-side improvement should focus on camera viewing geometry, waypoint orbit/yaw, and useful depth returns rather than changing the SLAM algorithm.

Decision:

- Keep RTAB-Map RGB-D as the shared single-vehicle SLAM smoke baseline for both cable and wind tasks.
- Treat the wind evidence as integration readiness, not final inspection coverage readiness.

## 18. RTAB-Map RGB-D Wind Multilevel Orbit RViz Evidence

Command:

```bash
OFFBOARD_LAUNCH_FILE=single_vehicle_wind_turbine_multilevel_orbit.launch.py \
MIN_WAYPOINT_ADVANCEMENTS=8 \
MOTION_SETTLE_SEC=115 \
scripts/capture_rtabmap_depth_camera_rgbd_wind_rviz_overlay.sh
```

Purpose:

- Re-run the wind RGB-D mapping evidence with the more inspection-like wind multilevel orbit baseline.
- Prefer a mature rule baseline that keeps yaw pointed at the turbine center instead of the earlier simple waypoint baseline with fixed yaw.
- Keep this as SLAM/visualization evidence only, not a turbine surface coverage certificate.

Observed result:

- The run was accepted.
- PX4 entered armed Offboard flight.
- The multilevel orbit baseline advanced through 41 waypoints before capture, exceeding the threshold of 8.
- RTAB-Map RGB-D mode stayed active.
- RViz rendered `/cloud_map`, `/map` and `/octomap_occupied_space`.

Latest evidence:

- summary: `data/results/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260605_141641/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260605_141641.txt`
- screenshot: `data/screenshots/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260605_141641.png`
- RTAB-Map log: `data/logs/rtabmap_depth_camera_rgbd_wind_rviz_rtabmap_20260605_141641.log`
- waypoint motion log: `data/logs/rtabmap_depth_camera_rgbd_wind_rviz_offboard_20260605_141641.log`
- topic list: `data/logs/rtabmap_depth_camera_rgbd_wind_rviz_topics_20260605_141641.log`

Observed summary:

```text
decision=accepted_rtabmap_depth_camera_rgbd_wind_rviz_overlay
launch=single_vehicle_wind_turbine_multilevel_orbit.launch.py
min_waypoint_advancements=8
waypoint_advancements=41
rtabmap_ok=true
outputs_ok=true
motion_ok=true
screenshot_ok=1
```

Visual assessment:

- Accepted as the current best wind-task motion-backed SLAM smoke evidence.
- Compared with the simple wind waypoint screenshot, this view shows a larger and more coherent local cloud/octomap structure.
- RTAB-Map still reports repeated depth NaN warnings, so this does not close the wind coverage problem.

Decision:

- Prefer the multilevel orbit launch for later wind-side SLAM visual checks.
- Next wind-side work should quantify useful depth returns and view/frustum coverage around the turbine before moving to any learning policy.

## 19. Wind Depth Image Useful Return Audit

Command:

```bash
scripts/audit_wind_depth_image_stats.sh
```

Purpose:

- Quantify whether wind-task depth images contain useful, non-saturated returns during multilevel orbit motion.
- Avoid over-reading RTAB-Map screenshots when the depth stream may be dominated by far-range values.
- Keep this as a sensor audit only. It does not change SLAM, trajectory generation or control.

Implementation:

- `zcw_cable_perception/depth_image_stats_audit` subscribes to `/camera/depth/image_raw`.
- It records per-frame CSV statistics:
  - finite positive depth pixels
  - useful depth pixels below `saturation_depth_m`
  - far or saturated pixels
  - mean and max useful ratios
- The current wind audit defaults to `saturation_depth_m=65.0` because the depth camera frequently reports values around `65.535m`.

Latest evidence:

- summary: `data/results/wind_depth_image_stats_20260605_142952/wind_depth_image_stats_20260605_142952.txt`
- depth stats summary: `data/results/wind_depth_image_stats_20260605_142952/depth_image_stats_20260605_143034.txt`
- frame CSV: `data/results/wind_depth_image_stats_20260605_142952/depth_image_stats_frames_20260605_143034.csv`
- Offboard log: `data/logs/wind_depth_stats_offboard_20260605_142952.log`

Observed summary:

```text
decision=accepted_wind_depth_image_stats
launch=single_vehicle_wind_turbine_multilevel_orbit.launch.py
waypoint_advancements=20
mean_valid_ratio=1
max_valid_ratio=1
mean_useful_ratio=0.0947751
max_useful_ratio=0.207139
saturation_depth_m=65.0
```

Interpretation:

- The wind depth stream is not blank.
- Counting only finite positive pixels is misleading because many pixels sit at far/saturation range.
- With a `65.0m` useful-depth cutoff, the current multilevel orbit produces about 9.5% useful pixels on average and about 20.7% in the best sampled frame.
- This supports the earlier visual evidence, but it also explains why RTAB-Map still logs depth NaN/far-depth warnings and why the current path is not a finished turbine coverage solution.

Decision:

- Keep the multilevel orbit as the current best wind baseline, but mark wind observation geometry as still open.
- Next wind work should tune orbit radius, altitude bands and camera orientation, then rerun this depth audit before claiming coverage progress.

## 20. Wind 15m Orbit Useful Depth Comparison

Command:

```bash
OFFBOARD_LAUNCH_FILE=single_vehicle_wind_turbine_multilevel_orbit_r15.launch.py \
scripts/audit_wind_depth_image_stats.sh
```

Purpose:

- Compare a closer 15m wind multilevel orbit candidate against the accepted 20m rule baseline.
- Use the same useful-depth metric and thresholding from the wind depth audit.
- Keep the comparison as an observation-quality audit, not a final coverage claim.

Static geometry evidence:

- summary: `data/results/wind_turbine_multilevel_orbit_launch_20260605_143524/wind_turbine_multilevel_orbit_launch_20260605_143524.txt`
- result: `decision=accepted_wind_turbine_multilevel_orbit_static_audit`
- radius: `15.000000m`
- waypoint count: `49`
- yaw errors: `0`

Depth evidence:

- summary: `data/results/wind_depth_image_stats_20260605_143754/wind_depth_image_stats_20260605_143754.txt`
- depth stats summary: `data/results/wind_depth_image_stats_20260605_143754/depth_image_stats_20260605_143837.txt`
- frame CSV: `data/results/wind_depth_image_stats_20260605_143754/depth_image_stats_frames_20260605_143837.csv`

Observed summary:

```text
decision=accepted_wind_depth_image_stats
launch=single_vehicle_wind_turbine_multilevel_orbit_r15.launch.py
waypoint_advancements=24
mean_valid_ratio=1
mean_useful_ratio=0.11667
max_useful_ratio=0.225683
```

Comparison:

- 20m multilevel orbit:
  - `mean_useful_ratio=0.0947751`
  - `max_useful_ratio=0.207139`
- 15m candidate:
  - `mean_useful_ratio=0.11667`
  - `max_useful_ratio=0.225683`

Interpretation:

- Moving from 20m to 15m improves useful depth return, but only modestly.
- The candidate should stay available for later wind SLAM/RViz and coverage checks.
- This is not enough to claim turbine coverage readiness because useful depth is still low and the available clearance/visibility audits are static upper-bound checks, not dynamic collision or full coverage certificates.

Decision:

- Keep 20m as the accepted default rule baseline for now.
- Keep 15m as the preferred next candidate for wind-side observation-quality experiments.

## 21. Wind 15m Orbit RTAB-Map RGB-D RViz Evidence

Command:

```bash
OFFBOARD_LAUNCH_FILE=single_vehicle_wind_turbine_multilevel_orbit_r15.launch.py \
MIN_WAYPOINT_ADVANCEMENTS=8 \
MOTION_SETTLE_SEC=115 \
scripts/capture_rtabmap_depth_camera_rgbd_wind_rviz_overlay.sh
```

Purpose:

- Verify that the 15m close-orbit candidate also produces RTAB-Map RGB-D RViz evidence.
- Compare it qualitatively against the 20m wind multilevel RTAB-Map screenshot.

Latest evidence:

- summary: `data/results/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260605_144439/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260605_144439.txt`
- screenshot: `data/screenshots/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260605_144439.png`
- RTAB-Map log: `data/logs/rtabmap_depth_camera_rgbd_wind_rviz_rtabmap_20260605_144439.log`
- waypoint motion log: `data/logs/rtabmap_depth_camera_rgbd_wind_rviz_offboard_20260605_144439.log`

Observed summary:

```text
decision=accepted_rtabmap_depth_camera_rgbd_wind_rviz_overlay
launch=single_vehicle_wind_turbine_multilevel_orbit_r15.launch.py
waypoint_advancements=46
rtabmap_ok=true
outputs_ok=true
motion_ok=true
screenshot_ok=1
```

Visual assessment:

- Accepted as the current strongest wind-side RTAB-Map RGB-D RViz smoke evidence.
- The screenshot shows a clearer localized cloud/octomap structure than the earlier 20m multilevel run.
- RTAB-Map still reports depth NaN/far-depth warnings, so this does not close the wind coverage problem.

Decision:

- Keep 15m as the preferred wind-side candidate for subsequent observation and coverage experiments.
- Do not claim final wind turbine coverage until dynamic collision checking and view/frustum coverage auditing are added.

Supplemental 15m motion-backed RGB-D RViz re-check on 2026-06-08:

- command: `OFFBOARD_LAUNCH_FILE=single_vehicle_wind_turbine_multilevel_orbit_r15.launch.py MIN_WAYPOINT_ADVANCEMENTS=8 MOTION_SETTLE_SEC=115 scripts/capture_rtabmap_depth_camera_rgbd_wind_rviz_overlay.sh`
- summary: `data/results/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260608_105840/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260608_105840.txt`
- screenshot: `data/screenshots/rtabmap_depth_camera_rgbd_wind_rviz_overlay_20260608_105840.png`
- RTAB-Map log: `data/logs/rtabmap_depth_camera_rgbd_wind_rviz_rtabmap_20260608_105840.log`
- waypoint motion log: `data/logs/rtabmap_depth_camera_rgbd_wind_rviz_offboard_20260608_105840.log`
- vehicle status log: `data/logs/rtabmap_depth_camera_rgbd_wind_rviz_vehicle_status_20260608_105840.log`
- local position log: `data/logs/rtabmap_depth_camera_rgbd_wind_rviz_vehicle_local_position_20260608_105840.log`
- topics log: `data/logs/rtabmap_depth_camera_rgbd_wind_rviz_topics_20260608_105840.log`
- result: `decision=accepted_rtabmap_depth_camera_rgbd_wind_rviz_overlay`
- `launch=single_vehicle_wind_turbine_multilevel_orbit_r15.launch.py`
- `waypoint_advancements=46`
- `rtabmap_ok=true`
- `outputs_ok=true`
- `motion_ok=true`
- `screenshot_ok=1`
- boundary: this uses the wind rule baseline, so it starts Offboard, arms, and publishes PX4 input topics for that baseline. It does not use RL or a cable active bridge.

Manual screenshot review: RViz Global Status is OK; `Cloud Map` and `Octomap Occupied Space` displays are OK; the screenshot is non-empty and shows localized cloud/octomap structure. It remains wind-task SLAM plumbing evidence, not a final turbine coverage certificate.

Static clearance follow-up:

- script: `scripts/audit_wind_orbit_clearance.sh`
- 20m baseline summary: `data/results/wind_clearance_20m_20260608_105400/wind_orbit_clearance_20260608_105417/wind_orbit_clearance_20260608_105417.txt`
- 15m candidate summary: `data/results/wind_clearance_r15_20260608_105400/wind_orbit_clearance_20260608_105424/wind_orbit_clearance_20260608_105424.txt`
- conservative mesh radius: `11.880407m`
- 20m minimum clearance: `8.119593m`
- 15m minimum clearance: `3.119593m`
- both pass the static `1.0m` clearance threshold.

Static visibility follow-up:

- script: `scripts/audit_wind_orbit_visibility.sh`
- 20m baseline summary: `data/results/wind_visibility_20m_20260608_105400/wind_orbit_visibility_20260608_105405/wind_orbit_visibility_20260608_105405.txt`
- 15m candidate summary: `data/results/wind_visibility_r15_20260608_105400/wind_orbit_visibility_20260608_105411/wind_orbit_visibility_20260608_105411.txt`
- 20m best_view_frame_fill_ratio: `0.092567`
- 15m best_view_frame_fill_ratio: `0.109478`
- 20m union_visible_ratio: `1.000000`
- 15m union_visible_ratio: `1.000000`

Interpretation:

- The 15m candidate is not obviously invalid under the conservative static mesh-radius check.
- The 15m candidate keeps the full-view upper bound and improves frame-fill ratio over the 20m baseline.
- This still does not prove dynamic collision safety or coverage completeness.

Static frustum coverage upper-bound follow-up:

- script: `scripts/audit_wind_orbit_frustum_coverage.sh`
- 20m baseline summary: `data/results/wind_frustum_coverage_20m_20260609_000000/wind_orbit_frustum_coverage_20260609_092332.txt`
- 15m candidate summary: `data/results/wind_frustum_coverage_r15_20260609_000000/wind_orbit_frustum_coverage_20260609_092324.txt`
- 20m vertex_coverage_ratio: `1.000000`
- 15m vertex_coverage_ratio: `1.000000`
- 20m double_observed_ratio: `1.000000`
- 15m double_observed_ratio: `1.000000`
- 20m min_band_coverage_ratio_observed: `1.000000`
- 15m min_band_coverage_ratio_observed: `1.000000`

Interpretation: the wind orbit geometry passes a static mesh-vertex frustum coverage upper-bound audit. This is still weaker than inspection coverage because it omits occlusion, surface normals, useful-depth validity and dynamic collision safety.

Static quality coverage follow-up:

- script: `scripts/audit_wind_orbit_quality_coverage.sh`
- 20m baseline summary: `data/results/wind_quality_coverage_20m_20260609_000000/wind_orbit_quality_coverage_20260609_093420.txt`
- 15m candidate summary: `data/results/wind_quality_coverage_r15_20260609_000000/wind_orbit_quality_coverage_20260609_093420.txt`
- 20m normal_filtered_coverage_ratio: `0.723701`
- 15m normal_filtered_coverage_ratio: `0.715221`
- 20m min_band_normal_coverage_ratio_observed: `0.613346`
- 15m min_band_normal_coverage_ratio_observed: `0.582924`
- 20m mean_useful_ratio: `0.094775`
- 15m mean_useful_ratio: `0.116670`

Interpretation: the 20m baseline is slightly stronger under the offline surface-normal/view-angle filter, while the 15m candidate remains stronger under real useful-depth image statistics. This is useful coverage-quality context for the wind task, but it is not SLAM accuracy evidence and not a final turbine inspection certificate.

Dynamic 15m wind orbit follow-up:

- script: `scripts/verify_wind_dynamic_orbit_audit.sh`
- wrapper summary: `data/results/wind_dynamic_orbit_audit_20260609_094838/wind_dynamic_orbit_audit_wrapper_20260609_094838.txt`
- node summary: `data/results/wind_dynamic_orbit_audit_20260609_094838/wind_dynamic_orbit_audit_20260609_094921.txt`
- launch: `single_vehicle_wind_turbine_multilevel_orbit_r15.launch.py`
- waypoint_advancements: `23`
- pose_samples: `350`
- depth_frames: `101`
- min_conservative_clearance_m: `2.8703362146`
- mean_useful_ratio: `0.0854219693785`
- max_useful_ratio: `0.218219339623`

Interpretation: this is real-motion wind task evidence from PX4/Gazebo and the depth camera. It supports the 15m observation candidate, but it is not SLAM accuracy evidence, loop-closure evidence, or final turbine coverage completion.

Dynamic 15m wind coverage progression follow-up:

- script: `scripts/audit_wind_dynamic_coverage_progression.sh`
- summary: `data/results/wind_dynamic_coverage_progression_r15_20260609_000000/wind_dynamic_coverage_progression_20260609_095332.txt`
- pose source: `data/results/wind_dynamic_orbit_audit_20260609_094838/wind_dynamic_orbit_pose_20260609_094921.csv`
- pose_samples_used: `350`
- final_normal_filtered_coverage_ratio: `0.637935`
- min_band_normal_coverage_ratio_observed: `0.410206`

Interpretation: this connects the accepted real-motion pose samples to mesh/frustum/normal coverage progression. It is useful task coverage context, not SLAM accuracy evidence, and the top band remains the weakest part of the partial dynamic run.

Longer dynamic 15m wind follow-up:

- dynamic wrapper summary: `data/results/wind_dynamic_orbit_audit_20260609_095652/wind_dynamic_orbit_audit_wrapper_20260609_095652.txt`
- dynamic node summary: `data/results/wind_dynamic_orbit_audit_20260609_095652/wind_dynamic_orbit_audit_20260609_095734.txt`
- progression summary: `data/results/wind_dynamic_coverage_progression_r15_full_20260609_000000/wind_dynamic_coverage_progression_20260609_100000.txt`
- waypoint_advancements: `48`
- pose_samples: `1200`
- depth_frames: `315`
- min_conservative_clearance_m: `2.72578086707`
- mean_useful_ratio: `0.232852213737`
- final_normal_filtered_coverage_ratio: `0.688708`
- min_band_normal_coverage_ratio_observed: `0.546614`

Interpretation: this is the strongest current wind task dynamic evidence. It still is not SLAM accuracy evidence and still omits occlusion-aware coverage.

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
