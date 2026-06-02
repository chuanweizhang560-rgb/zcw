# scripts

启动、检查、评估和训练入口脚本放在这里。

脚本只能做工程编排，不能隐藏核心算法实现。

## 当前脚本

- `setup_px4_venv.sh`：基于系统 Python 3.10 建立 PX4 release/1.14 专用 venv，并固定 `empy==3.3.4`。
- `run_px4_gazebo_classic_headless.sh`：用 clean env 启动 PX4 SITL + Gazebo Classic headless，并把运行日志写入 `data/logs/`。
- `run_px4_aerialcore_world_headless.sh`：用 PX4 `iris` 加载 AerialCore 风机或两塔导线 world，做组合 smoke test。
- `build_microxrce_agent.sh`：用 eProsima Micro-XRCE-DDS-Agent v2.2.1 和系统 FastDDS/FastCDR 构建 `MicroXRCEAgent`。
- `verify_px4_ros2_bridge_headless.sh`：启动 Micro XRCE-DDS Agent、PX4/Gazebo headless，并验证 ROS 2 中出现 `/fmu/out/vehicle_status`。
- `verify_px4_offboard_hover.sh`：通过 `zcw_bringup/single_vehicle_offboard_hover.launch.py` 运行 Offboard baseline，验证单机进入 armed Offboard 悬停状态。
- `verify_px4_offboard_waypoints.sh`：通过 `zcw_bringup/single_vehicle_waypoint_sequence.launch.py` 运行 waypoint baseline，验证单机可按位置 setpoint 前进。
- `verify_wind_turbine_waypoints.sh`：加载 AerialCore 风机 world，并运行最小风机巡检几何 waypoint baseline。
- `verify_cable_waypoints.sh`：加载 AerialCore 两塔导线 world，并运行最小电缆巡检几何 waypoint baseline。
- `verify_foggy_lidar_pointcloud.sh`：加载 AerialCore 两塔导线 world 和 PX4 `iris_foggy_lidar`，验证 ROS2 `/zcw/foggy_lidar/points` PointCloud2 输出。
- `verify_foggy_lidar_pose.sh`：验证 foggy lidar PointCloud2 `frame_id=foggy_lidar_link`，以及官方 `gazebo_ros_p3d` 输出 `/zcw/foggy_lidar/pose` Odometry。
- `verify_foggy_lidar_ransac.sh`：加载同一电缆场景和 foggy lidar，运行 `zcw_cable_perception` 的 PCL `SACMODEL_LINE` RANSAC 线模型烟测。
- `verify_foggy_lidar_ransac_batch.sh`：运行 5 帧 PCL RANSAC 批量烟测，输出每帧 CSV、filtered PCD、line-inlier PCD 和汇总结果。
- `verify_foggy_lidar_world_ransac.sh`：订阅 foggy lidar PointCloud2 与 P3D pose，输出 sensor/world-frame PCD 并检查 world 坐标 RANSAC 结果。
- `verify_depth_camera_pointcloud.sh`：用 PX4 官方 `iris_depth_camera` + Gazebo ROS camera plugin 验证 `/camera/points` PointCloud2；默认需要 GUI 渲染和可用 `DISPLAY`。
- `capture_pcd_ransac_viewer.sh`：用 PCL Viewer 打开 batch 输出的 filtered/inlier PCD，并截取真实点云可视化截图。
- `capture_px4_gazebo_classic_gui.sh`：启动 PX4 SITL + Gazebo Classic GUI，在可用 `DISPLAY` 上截取真实 Gazebo 截图，并清理仿真进程。
- `capture_px4_aerialcore_world_gui.sh`：启动 PX4 `iris` + AerialCore 风机或两塔导线 GUI 场景，并截取真实 Gazebo 截图。
- `verify_aerialcore_worlds.sh`：串行加载 AerialCore 风机和两塔导线 world，验证 Gazebo 11 headless 可运行。
