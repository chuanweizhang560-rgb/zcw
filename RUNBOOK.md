# 执行手册

更新时间：2026-06-02 17:54:35 CST

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
2. PX4 release/1.14 的 Python 依赖要固定 `empy==3.3.4`，不能使用 PyPI 默认拉取到的 empy 4.x。
3. Ubuntu 22.04 上构建 Classic 插件需要 `ninja-build`、`python3.10-venv`、`libgstreamer-plugins-base1.0-dev`。
4. headless 验证脚本使用 timeout 退出；只要日志中出现上述成功标志，timeout 退出不是失败。
5. Micro XRCE-DDS Agent v2.2.1 必须使用 clean build 目录和系统 `fmt`/`spdlog`，避免 conda include 路径导致 ABI/模板错误。
6. ROS 2 工作空间必须在系统 Python 3.10 环境中构建；不能继承 conda Python 3.13，否则 `px4_msgs` Python type support 会缺模块。
7. PX4 `/fmu/out/*` topic 使用 best-effort QoS；订阅 `vehicle_status` 时必须按 PX4 官方 Python 示例使用 best-effort/transient-local。
8. PX4 主日志会持续输出 `pxh>` 提示符，日志文件可能达到数百 MB；排障时只用限长 `head -c`/`tail -c` 过滤，不直接 `strings` 或全文 grep。

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
cd third_party/PX4-Autopilot-release-1.14
env PATH=/tmp/codex_zcw_px4_venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin PYTHON_EXECUTABLE=/tmp/codex_zcw_px4_venv/bin/python make px4_sitl_default sitl_gazebo-classic
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

1. 将 foggy lidar 标记为“管线 smoke 传感器”，不再把它当作导线识别传感器。
2. 优先验证 PX4 `iris_depth_camera` 或 Gazebo ROS2 GPU ray 方案，要求能看到高处导线/电塔点云。
3. 新传感器通过后，再做带 world 坐标的 RViz 叠加，确认 RANSAC 线候选对应真实导线。
4. 在离线几何稳定后，再接 Ceres/Eigen catenary/spline 和 Frenet offset path。
5. 对风机巡检 waypoint 做更贴近覆盖验收的圆周/螺旋几何轨迹配置。
6. 在上述两个规则 baseline 稳定后，再进入双机/四机通信和角色分配，不提前接 RL。

## 不允许事项

1. 不从零写低层飞控。
2. 不从零做风机、电塔、导线模型。
3. 不把 RL 接到电机或姿态内环。
4. 不把 `third_party/` 下的上游源码提交进主仓库。
5. 不在 PX4 Classic 兼容性未确认前启动多机阶段。
