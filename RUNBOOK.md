# 执行手册

更新时间：2026-06-03 16:48:31 CST

本文件记录当前仓库的可执行入口和下一步操作顺序。

## 当前阶段

阶段 2：PX4 Classic / Gazebo 11 最小链路验证。

当前只验证单机 SITL 底座，不训练 RL，不实现控制算法。

## 已确认环境

```text
Ubuntu 22.04.5 LTS
ROS 2 Humble
Gazebo Classic 11.10.2
```

## 已实测链路

PX4 release/1.14 + Gazebo Classic 11 已完成 headless 最小链路验证。
PX4 release/1.14 + `px4_msgs release/1.14` + `px4_ros_com release/v1.14` + Micro XRCE-DDS Agent v2.2.1 已完成 ROS 2 bridge 验证。
基于 `px4_ros_com` 官方 Offboard 示例派生的 `zcw_px4_baseline/offboard_hover_retry` 已完成单机 armed Offboard 悬停验证。
基于同一官方 Offboard setpoint 链路派生的 `zcw_px4_baseline/offboard_waypoint_sequence` 已完成单机 waypoint baseline 验证。
AerialCore 风机 world 上的最小风机巡检几何 waypoint baseline 已完成 headless 验证和 GUI 截图审核。
AerialCore 两塔导线 world 上的最小电缆巡检几何 waypoint baseline 已完成 headless 验证和 GUI 截图审核。
PX4 Classic `iris_foggy_lidar` + ROS2 `gazebo_ros_ray_sensor` overlay 已完成 PointCloud2 topic 验证。
`zcw_cable_perception/pointcloud_line_ransac_smoke` 已完成真实仿真 PointCloud2 到 PCL `SACMODEL_LINE` 的最小 RANSAC 烟测。
`zcw_cable_perception/pointcloud_line_ransac_batch_smoke` 已完成 ROI/滤波可配置的 5 帧 PCL RANSAC 批量烟测。
PCL Viewer 已可打开 batch 输出 PCD 并截取真实点云可视化截图，但当前截图只能证明线状候选存在，不能确认候选就是导线。
foggy lidar overlay 已通过官方 `gazebo_ros_p3d` 发布 `/zcw/foggy_lidar/pose`，PointCloud2 `frame_id` 已固定为 `foggy_lidar_link`，具备后续世界坐标叠加的基础。
`pointcloud_pose_line_ransac_world_smoke` 已把 RANSAC inlier 输出到 world 坐标；结果显示当前 foggy lidar inlier 基本在地面高度，不能作为导线识别结果。
PX4 官方 `iris_depth_camera` 已在 AerialCore 两塔导线 world + Gazebo GUI 渲染模式下发布 ROS 2 `/camera/points` PointCloud2。
`assets/gazebo/models/iris_depth_camera` overlay 已通过官方 `gazebo_ros_p3d` 发布 `/zcw/depth_camera/pose`，为 `/camera/points` world-frame 审核补齐位姿输入。
depth camera world-frame RANSAC 已完成静态地面审核；PointXYZ 兼容版本无 intensity 字段 warning，但 RANSAC inlier 呈大面积深度平面，不应视为导线识别结果。
depth camera + 电缆 waypoint 运动组合审核已完成；无人机在 armed Offboard 状态飞到电缆 corridor 后，PCL 截图显示塔架/导线状结构进入点云视场，RANSAC 能提取线候选。该结果仍是 smoke test，不等同于导线实例识别或闭环追线完成。
depth camera + 电缆 waypoint 运动多线候选审核已完成；`pointcloud_pose_multiline_ransac_world_smoke` 在 world-frame corridor ROI 内每帧抽取 6 条线候选，PCL 截图显示长连续线候选。该结果仍是 smoke test，不等同于导线实例识别、悬链线拟合或闭环追线完成。
depth camera 高空 wire-band ROI 多线候选已通过一致性审核；宽 ROI 候选因 `dir_z` 和 `z_span` 过大被拒绝，高空 ROI 候选形成 1 个跨 3 帧稳定组，可作为 catenary/spline 输入烟测的上游数据。
depth camera 高空 wire-band ROI 候选已完成高度层分组审核；`GROUP_MODE=z` 和 `GROUP_MODE=yz` 均得到 6 个稳定高度层组，推荐后续默认使用 `yz` 分组作为 catenary/spline 输入烟测。
depth camera 高空 wire-band ROI 候选已完成 Ceres/Eigen 离线拟合烟测；`Z_BIN_SIZE=2.0` 下 5 个高度层拟合通过，作为后续中心线采样和 Frenet offset path 的输入。
depth camera 高空 wire-band ROI accepted fit 已输出离线中心线采样 CSV 和 offset path CSV；默认 `PATH_STEP_M=10m`、`OFFSET_Y_M=-5m`、`OFFSET_Z_M=0m`，不接 PX4。
depth camera 高空 wire-band ROI offset path 已完成离线连续性、曲率、步长和偏移一致性审核；5 个 group 全部通过，仍不接 PX4。
电缆 lookahead/dry-run/Phase A PX4 bridge debug pipeline 已完成只读 topic、safety gate、dry-run candidate、bridge NED dry-run topic 和 RViz overlay 截图审核；当前仍未发布 `/fmu/in/*`。
PX4/Gazebo 只读坐标采样 smoke 已完成；该节点启动 PX4/Gazebo 和 Micro XRCE-DDS，只读取 `/fmu/out/vehicle_local_position`、Gazebo P3D pose、dry-run map candidate 和 bridge NED debug point，不启动 Offboard、不 arm、不发布 `/fmu/in/*`。
Offboard 接入前 Phase B gate 设计已写入 `docs/05_cable_phase_b_gate_plan.md`；显式批准前仍不得发布 `/fmu/in/*`。
`cable_offboard_gate_dry_run` 已完成 headless smoke；输出 `/zcw/cable/offboard_gate/*`，状态达到 `PHASE_B_READY_DRY_RUN`，`phase_b_allowed=false`，所有 `/fmu/in/*` publisher count 为 0。
Offboard gate dry-run RViz/debug overlay 已完成真实 PX4/Gazebo + Micro XRCE-DDS + RViz 截图审核；截图显示 offset path、lookahead target、dry-run candidate、bridge NED dry-run 和 gate approved NED dry-run debug 点，状态仍为 `phase_b_allowed=false`，所有 `/fmu/in/*` publisher count 为 0。
Phase B active bridge 前置边界审计已完成；当前没有 `cable_offboard_active_bridge`，没有 cable-specific `/fmu/in/*` publisher，脚本没有开启 `phase_b_user_approved`，本地 dry-run 证据完整。Phase B 仍未获批准。
电缆 active 前置坐标/安全阈值复核已完成；offset path 和 lookahead target 间隔约 `10.0005m`，但 gate 前 dry-run 实际水平跳变约 `0.999m`、垂直跳变约 `0.004m`，未来 active bridge 必须消费 gate-approved NED dry-run 输出，不能直接发布 raw lookahead target。
active bridge 代码审查模板已建立并通过只读模板审计；当前没有 `cable_offboard_active_bridge`，没有 cable active `/fmu/in/*` publisher，Phase B 仍未获批准。
dry-run readiness 总审计已完成；静态仓库边界、PX4 隔离、Phase B preflight、setpoint threshold 和 active bridge review template 均通过，当前仍没有 active bridge，Phase B 仍未获批准。

实测成功标志：

```text
Simulator connected on TCP port 4560.
Startup script returned successfully
/fmu/out/vehicle_status
arming_state: 2
nav_state: 14
Advancing to waypoint
```

注意事项：

1. 必须使用 clean env 启动，避免继承旧 `BS` 项目的 `GAZEBO_MODEL_PATH`、`GAZEBO_PLUGIN_PATH`、`LD_LIBRARY_PATH`。
2. PX4 release/1.14 的 Python 依赖要固定 `empy==3.3.4`，不能使用 PyPI 默认拉取到的 empy 4.x；`pip` 也要固定 `<24`，否则旧 requirements 中的 `matplotlib>=3.0.*` 会解析失败。
3. Ubuntu 22.04 上构建 Classic 插件需要 `ninja-build`、`python3.10-venv`、`libgstreamer-plugins-base1.0-dev`。
4. headless 验证脚本使用 timeout 退出；只要日志中出现上述成功标志，timeout 退出不是失败。
5. Micro XRCE-DDS Agent v2.2.1 必须使用 clean build 目录和系统 `fmt`/`spdlog`，避免 conda include 路径导致 ABI/模板错误。
6. ROS 2 工作空间必须在系统 Python 3.10 环境中构建；不能继承 conda Python 3.13，否则 `px4_msgs` Python type support 会缺模块。
7. PX4 `/fmu/out/*` topic 使用 best-effort QoS；订阅 `vehicle_status` 时必须按 PX4 官方 Python 示例使用 best-effort/transient-local。
8. PX4 主日志会持续输出 `pxh>` 提示符，日志文件可能达到数百 MB；排障时只用限长 `head -c`/`tail -c` 过滤，不直接 `strings` 或全文 grep。
9. Depth camera 依赖 Gazebo 渲染；headless 下会因为 rendering disabled 无法生成点云。验证时必须使用可用 `DISPLAY`，并把 `/opt/ros/humble`、Gazebo system plugin 目录和 ROS 2 ament 前缀显式带入 clean env。
10. 传感器验证脚本只启动仿真和采样 ROS2 topic，不发 Offboard setpoint；GUI 里无人机停在地面是预期行为。要验证运动，使用 Offboard/waypoint 脚本。
11. Phase A bridge RViz 中的 `px4_local_ned_dry_run` static TF 只用于显示 debug 点，不代表 PX4 local frame 闭环坐标对齐已经通过。
12. 启动 PX4 uXRCE-DDS 后，`/fmu/in/*` 会作为 PX4 订阅 topic 出现在 ROS 图中；只读验收应检查 `Publisher count: 0`，不能简单用 topic 名存在与否判断是否发布了 setpoint。
13. Offboard gate RViz overlay 继续使用 identity `map -> px4_local_ned_dry_run` static TF 只做 debug 叠加；NED debug 点可能在 RViz 高度方向偏离 map path，不能把该截图解释为真实控制坐标闭环已完成。

## 本地第三方仓库

第一批外部候选已克隆到 `third_party/`，但不会提交进主仓库。版本和许可证见 `OPEN_SOURCE_AUDIT.md`。

PX4 主仓库当前本地落点：

```text
third_party/PX4-Autopilot-release-1.14
third_party/px4_msgs                -> release/1.14, commit ffb6e80
third_party/px4_ros_com             -> release/v1.14, commit e18248d
third_party/Micro-XRCE-DDS-Agent-v2.2.1
third_party/aerialcore_simulation
```

## 可执行入口

准备 PX4 venv：

```bash
scripts/setup_px4_venv.sh
```

构建 PX4 和 Gazebo Classic 插件：

```bash
PX4_VENV="${PWD}/.venv/px4_venv"
env PATH="${PX4_VENV}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" PYTHON_EXECUTABLE="${PX4_VENV}/bin/python" make -C third_party/PX4-Autopilot-release-1.14 px4_sitl_default sitl_gazebo-classic
```

headless 启动验证：

```bash
TIMEOUT_SEC=45 scripts/run_px4_gazebo_classic_headless.sh
```

PX4 `iris` + AerialCore world 组合 smoke test：

```bash
AERIALCORE_WORLD=wind_turbine scripts/run_px4_aerialcore_world_headless.sh
AERIALCORE_WORLD=danube_wires scripts/run_px4_aerialcore_world_headless.sh
```

构建 Micro XRCE-DDS Agent：

```bash
scripts/build_microxrce_agent.sh
```

ROS 2 bridge 验证：

```bash
scripts/verify_px4_ros2_bridge_headless.sh
```

Offboard 悬停验证：

```bash
scripts/verify_px4_offboard_hover.sh
```

单独启动 ROS 2 Offboard baseline launch：

```bash
source /opt/ros/humble/setup.bash
source install/setup.bash
ros2 launch zcw_bringup single_vehicle_offboard_hover.launch.py
```

Offboard waypoint baseline 验证：

```bash
scripts/verify_px4_offboard_waypoints.sh
```

最小风机巡检几何 waypoint 验证：

```bash
scripts/verify_wind_turbine_waypoints.sh
```

最小电缆巡检几何 waypoint 验证：

```bash
scripts/verify_cable_waypoints.sh
```

电缆传感器 PointCloud2 验证：

```bash
scripts/verify_foggy_lidar_pointcloud.sh
```

电缆传感器 PointCloud2 + P3D pose 验证：

```bash
scripts/verify_foggy_lidar_pose.sh
```

电缆点云 PCL RANSAC 线模型烟测：

```bash
source /opt/ros/humble/setup.bash
colcon build --symlink-install --base-paths ros2_ws/src --packages-select zcw_cable_perception
scripts/verify_foggy_lidar_ransac.sh
```

电缆点云 PCL RANSAC 多帧批量烟测：

```bash
source /opt/ros/humble/setup.bash
colcon build --symlink-install --base-paths ros2_ws/src --packages-select zcw_cable_perception
scripts/verify_foggy_lidar_ransac_batch.sh
```

电缆点云 world-frame RANSAC 烟测：

```bash
source /opt/ros/humble/setup.bash
colcon build --symlink-install --base-paths ros2_ws/src --packages-select zcw_cable_perception
scripts/verify_foggy_lidar_world_ransac.sh
```

PX4 depth camera PointCloud2 验证：

```bash
scripts/verify_depth_camera_pointcloud.sh
```

最新成功证据：

```text
topic: /camera/points
type: sensor_msgs/msg/PointCloud2
frame_id: camera_link
width: 848
height: 480
point_step: 32
log: data/logs/depth_camera_pointcloud_sample_20260602_191429.log
screenshot: data/screenshots/depth_camera_pointcloud_gui_20260602_191429.png
```

PX4 depth camera PointCloud2 + P3D pose 验证：

```bash
scripts/verify_depth_camera_pose_pointcloud.sh
```

最新成功证据：

```text
points_topic: /camera/points
points_type: sensor_msgs/msg/PointCloud2
points_frame_id: camera_link
pose_topic: /zcw/depth_camera/pose
pose_type: nav_msgs/msg/Odometry
pose_frame_id: world
pose_child_frame_id: depth_camera::link
points_log: data/logs/depth_camera_pose_points_sample_20260602_204840.log
pose_log: data/logs/depth_camera_pose_pose_sample_20260602_204840.log
screenshot: data/screenshots/depth_camera_pose_gui_20260602_204840.png
```

PX4 depth camera world-frame RANSAC 审核：

```bash
source /opt/ros/humble/setup.bash
colcon build --symlink-install --base-paths ros2_ws/src --packages-select zcw_cable_perception
scripts/verify_depth_camera_world_ransac.sh
```

最新审核证据：

```text
summary: data/results/depth_camera_world_ransac_20260602_211626/depth_camera_line_ransac_world_20260602_211646.txt
csv: data/results/depth_camera_world_ransac_20260602_211626/depth_camera_line_ransac_world_20260602_211646.csv
node_log: data/logs/depth_camera_world_ransac_node_20260602_211626.log
gazebo_screenshot: data/screenshots/depth_camera_world_ransac_gui_20260602_211626.png
pcd_screenshot: data/screenshots/pcd_ransac_frame0_20260602_211833_pcl_viewer_left.png
world_inlier_bbox_min: -46.6904 -8.0371 0.255494
world_inlier_bbox_max: 1.47922 1.03503 65.5754
decision: static_ground_depth_camera_ransac_not_accepted_as_cable
```

PX4 depth camera + 电缆 waypoint 运动 RANSAC 审核：

```bash
source /opt/ros/humble/setup.bash
colcon build --symlink-install --base-paths ros2_ws/src --packages-select zcw_cable_perception zcw_px4_baseline zcw_bringup
scripts/verify_depth_camera_cable_motion_ransac.sh
```

最新审核证据：

```text
summary: data/results/depth_camera_motion_ransac_20260602_215550/depth_camera_motion_line_ransac_world_20260602_215722.txt
csv: data/results/depth_camera_motion_ransac_20260602_215550/depth_camera_motion_line_ransac_world_20260602_215722.csv
node_log: data/logs/depth_camera_motion_ransac_node_20260602_215550.log
offboard_log: data/logs/depth_camera_motion_offboard_20260602_215550.log
local_position_log: data/logs/depth_camera_motion_vehicle_local_position_20260602_215550.log
gazebo_screenshot: data/screenshots/depth_camera_motion_gui_20260602_215550.png
pcd_screenshot: data/screenshots/pcd_ransac_frame0_20260602_215821_pcl_viewer_left.png
capture_local_position_ned: -50.0052 -35.0299 -22.0264
sensor_rpy_rad: -1.5708 0 -1.5708
world_inlier_bbox_min: -95.9096 15.8306 6.81435
world_inlier_bbox_max: 26.2537 17.6723 54.0478
decision: motion_depth_camera_line_candidate_visible_but_not_final_cable_tracking
```

PX4 depth camera + 电缆 waypoint 运动多线候选 RANSAC 审核：

```bash
source /opt/ros/humble/setup.bash
colcon build --symlink-install --base-paths ros2_ws/src --packages-select zcw_cable_perception zcw_px4_baseline zcw_bringup
scripts/verify_depth_camera_cable_motion_multiline_ransac.sh
```

最新审核证据：

```text
summary: data/results/depth_camera_motion_ransac_20260603_111923/depth_camera_motion_multiline_ransac_world_20260603_112105.txt
frame_csv: data/results/depth_camera_motion_ransac_20260603_111923/depth_camera_motion_multiline_ransac_world_frames_20260603_112105.csv
line_csv: data/results/depth_camera_motion_ransac_20260603_111923/depth_camera_motion_multiline_ransac_world_lines_20260603_112105.csv
node_log: data/logs/depth_camera_motion_ransac_node_20260603_111923.log
offboard_log: data/logs/depth_camera_motion_offboard_20260603_111923.log
gazebo_screenshot: data/screenshots/depth_camera_motion_gui_20260603_111923.png
pcd_screenshot: data/screenshots/pcd_ransac_frame0_20260603_112534_pcl_viewer_left.png
frames_processed: 3
lines_per_frame: 6
failed_frames: 0
total_candidates: 18
mean_world_roi_points: 348453
world_roi_min: -120 5 0
world_roi_max: 40 30 65
decision: motion_depth_camera_multiline_candidates_visible_but_not_final_cable_tracking
```

PX4 depth camera 高空 wire-band ROI 多线候选 RANSAC 与一致性审核：

```bash
RANSAC_WORLD_CROP_MIN_Z=38.0 \
RANSAC_WORLD_CROP_MAX_Z=62.0 \
RANSAC_WORLD_CROP_MIN_Y=10.0 \
RANSAC_WORLD_CROP_MAX_Y=24.0 \
RANSAC_MIN_LINE_INLIERS=300 \
RANSAC_MIN_LINES_PER_FRAME=1 \
RANSAC_MAX_LINES=6 \
RANSAC_FRAMES=3 \
scripts/verify_depth_camera_cable_motion_multiline_ransac.sh

INPUT_CSV=data/results/depth_camera_motion_ransac_20260603_114139/depth_camera_motion_multiline_ransac_world_lines_20260603_114312.csv \
scripts/audit_depth_camera_multiline_consistency.sh
```

最新审核证据：

```text
ransac_summary: data/results/depth_camera_motion_ransac_20260603_114139/depth_camera_motion_multiline_ransac_world_20260603_114312.txt
ransac_line_csv: data/results/depth_camera_motion_ransac_20260603_114139/depth_camera_motion_multiline_ransac_world_lines_20260603_114312.csv
consistency_summary: data/results/multiline_consistency_20260603_114337/depth_camera_motion_multiline_consistency_20260603_114337.txt
consistency_groups_csv: data/results/multiline_consistency_20260603_114337/depth_camera_motion_multiline_consistency_groups_20260603_114337.csv
pcd_screenshot: data/screenshots/pcd_ransac_frame0_20260603_114532_pcl_viewer_left.png
world_roi_min: -120 10 38
world_roi_max: 40 24 62
total_candidates: 18
geometry_gate_candidates: 18
accepted_groups: 1
decision: accepted_for_catenary_input_smoke
```

PX4 depth camera 高空 wire-band ROI 高度层分组审核：

```bash
INPUT_CSV=data/results/depth_camera_motion_ransac_20260603_114139/depth_camera_motion_multiline_ransac_world_lines_20260603_114312.csv \
GROUP_MODE=yz \
Y_BIN_SIZE=2.0 \
Z_BIN_SIZE=3.0 \
MIN_ACCEPTED_GROUPS=2 \
OUTPUT_DIR=data/results/multiline_consistency_yz_20260603_124000 \
OUTPUT_PREFIX=depth_camera_motion_multiline_consistency_yz \
scripts/audit_depth_camera_multiline_consistency.sh
```

最新审核证据：

```text
summary: data/results/multiline_consistency_yz_20260603_124000/depth_camera_motion_multiline_consistency_yz_20260603_123719.txt
groups_csv: data/results/multiline_consistency_yz_20260603_124000/depth_camera_motion_multiline_consistency_yz_groups_20260603_123719.csv
group_mode: yz
z_bin_size: 3
groups: 6
accepted_groups: 6
decision: accepted_for_catenary_input_smoke
height_layers_mean_z: 40.77, 43.14, 47.11, 49.88, 53.02, 55.63
```

PX4 depth camera 高空 wire-band ROI Ceres/Eigen catenary/spline 输入烟测：

```bash
OUTPUT_DIR=data/results/catenary_fit_yz_zbin2_20260603_132000 \
OUTPUT_PREFIX=depth_camera_motion_catenary_fit_yz_zbin2 \
GROUP_MODE=yz \
Y_BIN_SIZE=2.0 \
Z_BIN_SIZE=2.0 \
scripts/audit_catenary_fit.sh
```

最新审核证据：

```text
summary: data/results/catenary_fit_yz_zbin2_20260603_132000/depth_camera_motion_catenary_fit_yz_zbin2_20260603_125147.txt
fits_csv: data/results/catenary_fit_yz_zbin2_20260603_132000/depth_camera_motion_catenary_fit_yz_zbin2_fits_20260603_125147.csv
samples_csv: data/results/catenary_fit_yz_zbin2_20260603_132000/depth_camera_motion_catenary_fit_yz_zbin2_samples_20260603_125147.csv
group_mode: yz
z_bin_size: 2
fit_groups: 5
accepted_fits: 5
decision: accepted_catenary_fit_smoke
max_catenary_rmse_observed: 0.52019
max_quadratic_rmse_observed: 0.51178
```

PX4 depth camera 高空 wire-band ROI 中心线采样与 offset path 烟测：

```bash
OUTPUT_DIR=data/results/catenary_offset_yz_zbin2_20260603_135000 \
OUTPUT_PREFIX=depth_camera_motion_catenary_offset_yz_zbin2 \
GROUP_MODE=yz \
Y_BIN_SIZE=2.0 \
Z_BIN_SIZE=2.0 \
PATH_STEP_M=10.0 \
OFFSET_Y_M=-5.0 \
OFFSET_Z_M=0.0 \
scripts/audit_catenary_fit.sh
```

最新审核证据：

```text
summary: data/results/catenary_offset_yz_zbin2_20260603_135000/depth_camera_motion_catenary_offset_yz_zbin2_20260603_125948.txt
fits_csv: data/results/catenary_offset_yz_zbin2_20260603_135000/depth_camera_motion_catenary_offset_yz_zbin2_fits_20260603_125948.csv
centerline_csv: data/results/catenary_offset_yz_zbin2_20260603_135000/depth_camera_motion_catenary_offset_yz_zbin2_centerline_20260603_125948.csv
offset_path_csv: data/results/catenary_offset_yz_zbin2_20260603_135000/depth_camera_motion_catenary_offset_yz_zbin2_offset_path_20260603_125948.csv
accepted_fits: 5
centerline_points: 65
offset_path_points: 65
path_step_m: 10
offset_y_m: -5
offset_z_m: 0
```

PX4 depth camera 高空 wire-band ROI offset path 连续性审核：

```bash
OUTPUT_DIR=data/results/offset_path_audit_20260603_143000 \
OUTPUT_PREFIX=depth_camera_motion_offset_path_audit \
EXPECTED_STEP_M=10.0 \
MAX_STEP_ERROR_M=1.0 \
MAX_CURVATURE=0.02 \
MAX_OFFSET_ERROR_M=0.05 \
scripts/audit_offset_path.sh
```

最新审核证据：

```text
summary: data/results/offset_path_audit_20260603_143000/depth_camera_motion_offset_path_audit_20260603_164538.txt
groups_csv: data/results/offset_path_audit_20260603_143000/depth_camera_motion_offset_path_audit_groups_20260603_164538.csv
points: 65
groups: 5
accepted_groups: 5
decision: accepted_offset_path_smoke
max_step_error_observed_m: 0.00064
max_curvature_observed: 0.000101
max_offset_error_observed_m: 0
```

PX4 depth camera 高空 wire-band ROI lookahead target 离线审核：

```bash
OUTPUT_DIR=data/results/lookahead_target_audit_20260603_165600 \
OUTPUT_PREFIX=depth_camera_motion_lookahead_target_audit \
LOOKAHEAD_M=20.0 \
MIN_TARGET_DISTANCE_M=15.0 \
MAX_TARGET_DISTANCE_M=25.0 \
scripts/audit_lookahead_target.sh
```

最新审核证据：

```text
summary: data/results/lookahead_target_audit_20260603_165600/depth_camera_motion_lookahead_target_audit_20260603_165501.txt
targets_csv: data/results/lookahead_target_audit_20260603_165600/depth_camera_motion_lookahead_target_audit_targets_20260603_165501.csv
groups_csv: data/results/lookahead_target_audit_20260603_165600/depth_camera_motion_lookahead_target_audit_groups_20260603_165501.csv
groups: 5
accepted_groups: 5
targets: 55
decision: accepted_lookahead_target_smoke
target_distance_range_m: 20 to 20.0012
monotonic_target_index: true
```

只读 lookahead ROS topic 发布烟测：

```bash
scripts/verify_lookahead_topic_publish.sh
```

最新审核证据：

```text
node_log: data/logs/lookahead_path_publisher_20260603_170640.log
topic_list_log: data/logs/lookahead_topic_list_20260603_170640.log
offset_path_echo: data/logs/lookahead_offset_path_echo_20260603_170640.log
lookahead_target_echo: data/logs/lookahead_target_echo_20260603_170640.log
topics:
  /zcw/cable/offset_path
  /zcw/cable/lookahead_target
loaded_group: y8_z20
path_points: 13
targets: 11
first_path_point: x=-95.8193, y=11.7591, z=41.3862
sample_target: x=-65.8193, y=11.7591, z=41.4078
```

RViz lookahead overlay 截图审核：

```bash
scripts/capture_lookahead_rviz_overlay.sh
```

最新审核证据：

```text
publisher_log: data/logs/lookahead_rviz_publisher_20260603_171401.log
rviz_log: data/logs/lookahead_rviz_20260603_171401.log
static_tf_log: data/logs/lookahead_rviz_static_tf_20260603_171401.log
screenshot: data/screenshots/lookahead_rviz_overlay_20260603_171401.png
screenshot_size: 2490x1522
rviz_global_status: OK
offset_path_display: OK
lookahead_target_display: OK
visual_check: green offset path and red lookahead target points visible
```

只读 lookahead 安全状态机 smoke：

```bash
scripts/verify_lookahead_safety_monitor.sh
```

最新审核证据：

```text
publisher_log: data/logs/lookahead_safety_publisher_20260603_172502.log
topic_list_log: data/logs/lookahead_safety_topic_list_20260603_172502.log
tracking_state_echo: data/logs/lookahead_tracking_state_echo_20260603_172502.log
safety_gate_echo: data/logs/lookahead_safety_gate_echo_20260603_172502.log
tracking_state: TRACK_READY
path_points: 13
target_received: true
min_target_to_path_m: 0
last_target_jump_m: 10.0005
safety_gate: true
```

只读 dry-run candidate setpoint smoke：

```bash
scripts/verify_lookahead_dry_run_setpoint.sh
```

最新审核证据：

```text
state_echo: data/logs/lookahead_dry_run_state_echo_20260603_174508.log
candidate_echo: data/logs/lookahead_dry_run_candidate_echo_20260603_174508.log
path_echo: data/logs/lookahead_dry_run_path_echo_20260603_174508.log
topic_list: data/logs/lookahead_dry_run_topic_list_20260603_174508.log
forbidden_topics: data/logs/lookahead_dry_run_forbidden_topics_20260603_174508.log
dry_run_state: TRACK_READY
target_to_path_m: 0
candidate_jump_m: 1.99995
candidate_vertical_jump_m: 0.0105846
candidate_speed_mps: 5
publishes_px4: false
candidate_sample: x=-41.816705134089204, y=11.7591, z=41.52087241063747
forbidden_fmu_in_topics: none
```

只读 dry-run candidate RViz overlay 截图审核：

```bash
scripts/capture_lookahead_dry_run_rviz_overlay.sh
```

最新审核证据：

```text
publisher_log: data/logs/lookahead_dry_run_rviz_publisher_20260603_175512.log
rviz_log: data/logs/lookahead_dry_run_rviz_20260603_175512.log
topic_list: data/logs/lookahead_dry_run_rviz_topic_list_20260603_175512.log
forbidden_topics: data/logs/lookahead_dry_run_rviz_forbidden_topics_20260603_175512.log
screenshot: data/screenshots/lookahead_dry_run_rviz_overlay_20260603_175512.png
screenshot_size: 2490x1522
rviz_global_status: OK
offset_path_display: OK
lookahead_target_display: OK
dry_run_path_display: OK
dry_run_candidate_display: OK
forbidden_fmu_in_topics: none
visual_check: green offset path, red lookahead target, blue dry-run path, yellow dry-run candidate visible
```

PX4 Offboard 隔离审计：

```bash
OUTPUT_DIR=data/results/px4_isolation_audit_20260603_180400 scripts/audit_px4_isolation.sh
```

最新审核证据：

```text
summary: data/results/px4_isolation_audit_20260603_180400/px4_isolation_audit_20260603_180310.txt
package_xml_px4_msgs_dependency: PASS
cmake_px4_msgs_reference: PASS
source_px4_message_api: PASS
source_fmu_in_publish: PASS
lookahead_script_fmu_in_publish: PASS
dry_run_debug_topics_under_zcw_cable_dry_run: PASS
decision: accepted_px4_isolation_smoke
```

PX4 Phase A bridge dry-run isolation smoke：

```bash
scripts/verify_px4_bridge_dry_run_isolation.sh
```

最新审核证据：

```text
bridge_state_echo: data/logs/px4_bridge_dry_run_state_echo_20260603_190805.log
ned_setpoint_echo: data/logs/px4_bridge_dry_run_ned_echo_20260603_190805.log
topic_list: data/logs/px4_bridge_dry_run_topic_list_20260603_190805.log
forbidden_topics: data/logs/px4_bridge_dry_run_forbidden_topics_20260603_190805.log
bridge_state: DRY_RUN_READY
phase: PHASE_A_DRY_RUN
publishes_fmu_in: false
map_to_ned: debug_x_y_neg_z
ned_frame: px4_local_ned_dry_run
ned_sample: x=-48.8198330876827, y=11.7591, z=-41.4620108793388
forbidden_fmu_in_topics: none
```

电缆点云 PCL Viewer 截图审核：

```bash
RESULT_DIR=data/results/foggy_lidar_ransac_batch_20260602_172404 FRAME_INDEX=0 scripts/capture_pcd_ransac_viewer.sh
```

最小风机巡检 GUI 截图审核：

```bash
AERIALCORE_WORLD=wind_turbine GUI_SETTLE_SEC=12 scripts/capture_px4_aerialcore_world_gui.sh
```

最小电缆巡检 GUI 截图审核：

```bash
AERIALCORE_WORLD=danube_wires GUI_SETTLE_SEC=12 VERIFY_TIMEOUT_SEC=120 scripts/capture_px4_aerialcore_world_gui.sh
```

Gazebo Classic GUI 截图：

```bash
scripts/capture_px4_gazebo_classic_gui.sh
```

截图脚本要求当前 shell 存在可用 `DISPLAY`。截图和运行日志分别写入 `data/screenshots/`、`data/logs/`，这两个目录只作本地证据保存，不提交进 git。

AerialCore GUI 截图：

```bash
AERIALCORE_WORLD=wind_turbine scripts/capture_px4_aerialcore_world_gui.sh
AERIALCORE_WORLD=danube_wires scripts/capture_px4_aerialcore_world_gui.sh
```

AerialCore 风机/两塔导线 world 验证：

```bash
scripts/verify_aerialcore_worlds.sh
```

当前 AerialCore world 会报告缺少 MRS RViz camera synchronizer plugin；该警告不影响静态模型 world 的 headless 加载，但进入正式任务 world 前需要决定是安装 MRS 插件还是使用不依赖该插件的引用 world。

## 下一步执行顺序

1. 为 Phase A bridge dry-run 增加 RViz overlay 截图，不启动 Gazebo/PX4。
2. RViz bridge 证据通过后，再设计带 PX4/Gazebo 的只读坐标系对齐验证；仍不能发布 setpoint。
3. 如果 depth camera 高空 ROI 后续不稳定，再评估 Gazebo ROS2 GPU ray sensor overlay，但必须复用官方 `gazebo_ros_ray_sensor`，不自写传感器插件。
4. 对风机巡检 waypoint 做更贴近覆盖验收的圆周/螺旋几何轨迹配置。
5. 在上述两个规则 baseline 稳定后，再进入双机/四机通信和角色分配，不提前接 RL。

## 不允许事项

1. 不从零写低层飞控。
2. 不从零做风机、电塔、导线模型。
3. 不把 RL 接到电机或姿态内环。
4. 不把 `third_party/` 下的上游源码提交进主仓库。
5. 不在 PX4 Classic 兼容性未确认前启动多机阶段。
