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
- `audit_wind_turbine_geometry_baseline.sh`：只读解析 AerialCore 风机 world、DAE 粗边界和当前风机 waypoint launch，输出当前 baseline 几何审计和待审推荐 orbit CSV；不启动 ROS/PX4/Gazebo/RViz，不发布 `/fmu/in/*`。
- `audit_wind_turbine_multilevel_orbit_launch.sh`：只读解析风机 multilevel orbit launch，检查 4 层、每层 12 点、总 49 个 waypoint、20m 半径和 yaw 指向风机中心；不启动 ROS/PX4/Gazebo/RViz，不发布 `/fmu/in/*`。
- `verify_wind_turbine_multilevel_orbit.sh`：加载 AerialCore 风机 world，并运行独立 multilevel orbit waypoint/yaw baseline；该脚本会启动 PX4 Offboard/arm，仅用于风机规则 baseline 验证，不属于电缆 Phase B active。
- `capture_wind_turbine_multilevel_orbit_gui.sh`：启动 AerialCore 风机 world 的 Gazebo GUI、Micro XRCE-DDS 和 multilevel orbit launch，等待真实 waypoint advancement 后截取 Gazebo GUI 截图。
- `verify_cable_waypoints.sh`：加载 AerialCore 两塔导线 world，并运行最小电缆巡检几何 waypoint baseline。
- `verify_foggy_lidar_pointcloud.sh`：加载 AerialCore 两塔导线 world 和 PX4 `iris_foggy_lidar`，验证 ROS2 `/zcw/foggy_lidar/points` PointCloud2 输出。
- `verify_foggy_lidar_pose.sh`：验证 foggy lidar PointCloud2 `frame_id=foggy_lidar_link`，以及官方 `gazebo_ros_p3d` 输出 `/zcw/foggy_lidar/pose` Odometry。
- `verify_foggy_lidar_ransac.sh`：加载同一电缆场景和 foggy lidar，运行 `zcw_cable_perception` 的 PCL `SACMODEL_LINE` RANSAC 线模型烟测。
- `verify_foggy_lidar_ransac_batch.sh`：运行 5 帧 PCL RANSAC 批量烟测，输出每帧 CSV、filtered PCD、line-inlier PCD 和汇总结果。
- `verify_foggy_lidar_world_ransac.sh`：订阅 foggy lidar PointCloud2 与 P3D pose，输出 sensor/world-frame PCD 并检查 world 坐标 RANSAC 结果。
- `verify_depth_camera_pointcloud.sh`：用 PX4 官方 `iris_depth_camera` + Gazebo ROS camera plugin 验证 `/camera/points` PointCloud2；默认需要 GUI 渲染和可用 `DISPLAY`。
- `verify_depth_camera_pose_pointcloud.sh`：验证 depth camera `/camera/points` PointCloud2 和官方 `gazebo_ros_p3d` 输出 `/zcw/depth_camera/pose` Odometry。
- `verify_depth_camera_world_ransac.sh`：订阅 depth camera PointCloud2 与 P3D pose，输出 sensor/world-frame PCD 并审核静态 world-frame RANSAC 结果。
- `verify_depth_camera_cable_motion_ransac.sh`：运行电缆 waypoint baseline，并在无人机运动到 corridor 后采集 depth camera world-frame RANSAC 证据。
- `verify_depth_camera_cable_motion_multiline_ransac.sh`：复用电缆 waypoint motion 链路，切换到 PCL 多线候选节点，在 world-frame corridor ROI 内抽取多条线候选。
- `audit_depth_camera_multiline_consistency.sh`：读取多线候选 CSV，按方向、跨度和跨帧分组做离线一致性审核；支持 `GROUP_MODE=y|z|yz`，用于判断候选是否可进入 catenary/spline 输入烟测。
- `audit_catenary_fit.sh`：读取高空 wire-band ROI 多线候选 CSV，调用 Ceres 做 catenary 拟合、调用 Eigen 做二次曲线残差对照，并输出离线中心线/offset path 烟测证据。
- `audit_offset_path.sh`：读取离线 offset path CSV，检查步长、曲率、x 单调性和偏移一致性。
- `audit_lookahead_target.sh`：读取已审核的 offset path CSV，生成只读 lookahead target CSV，并检查前视距离窗口和 target index 单调性。
- `verify_lookahead_topic_publish.sh`：启动只读 `lookahead_path_publisher`，验证 `/zcw/cable/offset_path` 和 `/zcw/cable/lookahead_target` ROS topic 可发布；不接 PX4 setpoint。
- `capture_lookahead_rviz_overlay.sh`：启动只读 lookahead publisher、static TF 和 RViz2，加载 overlay 配置并截取真实 RViz 截图；不启动 Gazebo/PX4。
- `verify_lookahead_safety_monitor.sh`：启动只读 lookahead publisher 和 safety monitor，验证 `/zcw/cable/tracking_state` 与 `/zcw/cable/safety_gate`；不接 PX4 setpoint。
- `verify_lookahead_dry_run_setpoint.sh`：启动只读 publisher、safety monitor 和 dry-run setpoint 节点，验证 `/zcw/cable/dry_run/*` debug topics，并确认没有 `/fmu/in/*` topic。
- `capture_lookahead_dry_run_rviz_overlay.sh`：启动只读 publisher、safety monitor、dry-run setpoint、static TF 和 RViz2，加载 dry-run overlay 配置并截取真实 RViz 截图；不启动 Gazebo/PX4。
- `audit_px4_isolation.sh`：静态检查 `zcw_cable_perception` 与 lookahead 脚本没有 `px4_msgs` 依赖、PX4 message API 或 `/fmu/in/*` 发布。
- `verify_px4_bridge_dry_run_isolation.sh`：启动只读 lookahead pipeline 和 Phase A bridge dry-run，验证 `/zcw/cable/px4_bridge/*` debug topics，并确认没有 `/fmu/in/*` topic。
- `capture_px4_bridge_dry_run_rviz_overlay.sh`：启动只读 lookahead pipeline、Phase A bridge dry-run、static TF 和 RViz2，加载 bridge overlay 配置并截取真实 RViz 截图；不启动 Gazebo/PX4，不发布 `/fmu/in/*`。
- `verify_px4_gazebo_readonly_frame_alignment.sh`：启动 PX4/Gazebo + Micro XRCE-DDS 和只读 bridge debug pipeline，采集 PX4 local position、Gazebo P3D pose、map candidate 和 bridge NED debug point；不启动 Offboard、不 arm、不发布 `/fmu/in/*`。
- `verify_cable_offboard_gate_dry_run.sh`：启动 PX4/Gazebo + Micro XRCE-DDS、只读 bridge debug pipeline 和 offboard gate dry-run，验证 `/zcw/cable/offboard_gate/*`，并确认所有 `/fmu/in/*` topic 的 publisher count 为 0。
- `capture_cable_offboard_gate_dry_run_rviz_overlay.sh`：启动 PX4/Gazebo + Micro XRCE-DDS、只读 bridge debug pipeline、offboard gate dry-run、static TF 和 RViz2，加载 gate overlay 配置并截取真实 RViz 截图；不启动 Offboard、不 arm，并确认所有 `/fmu/in/*` topic 的 publisher count 为 0。
- `audit_phase_b_active_preflight_boundary.sh`：只读静态审计 Phase B active bridge 前置边界，确认当前没有 cable active bridge、没有 cable `/fmu/in/*` publisher、没有脚本开启 `phase_b_user_approved`，并检查本地 dry-run 证据文件。
- `audit_cable_setpoint_thresholds.sh`：只读统计 offset path、lookahead target、gate state 和 approved NED dry-run 日志，复核未来 active bridge 的 setpoint 跳变阈值；不启动 ROS/PX4/Gazebo，不发布 `/fmu/in/*`。
- `audit_active_bridge_review_template.sh`：只读审计 active bridge 代码审查模板，并复用 Phase B preflight 与阈值审计确认当前仍没有 active bridge；不启动 ROS/PX4/Gazebo，不发布 `/fmu/in/*`。
- `audit_dry_run_readiness.sh`：总 dry-run readiness 审计，串行运行 PX4 隔离、Phase B preflight、阈值和 review template 审计，并检查 ignored 产物目录；不启动 ROS/PX4/Gazebo，不发布 `/fmu/in/*`。
- `audit_evidence_inventory.sh`：只读检查当前 dry-run 边界依赖的本地 ignored 证据文件是否存在、是否仍被 git 忽略，并输出再生成入口清单；不启动 ROS/PX4/Gazebo/RViz，不发布 `/fmu/in/*`。
- `audit_multi_vehicle_upstream_readiness.sh`：只读检查 PX4 release/1.14 的 Gazebo Classic 多实例脚本、实例 MAVLink 端口、`MAV_SYS_ID`、`UXRCE_DDS_KEY` 和 DDS namespace 支持；不启动 ROS/PX4/Gazebo/RViz。
- `verify_px4_gazebo_classic_multi_vehicle_readonly.sh`：按 PX4 官方 Gazebo Classic 多实例机制启动两台 `iris`、Micro XRCE-DDS 和 Gazebo headless，只验证 `/px4_1/fmu/out/*`、`/px4_2/fmu/out/*` 输出 topic 与 `/fmu/in/*` publisher count 为 0；不启动 Offboard、不 arm。
- `audit_rtabmap_installation.sh`：只读检查 `ros-humble-rtabmap-ros` 及 `rtabmap_slam`、`rtabmap_odom`、`rtabmap_util` 关键可执行节点是否可见；不启动 ROS/PX4/Gazebo/RViz。
- `verify_rtabmap_node_smoke.sh`：启动 `rtabmap_slam/rtabmap` ROS 2 节点的无传感器 read-only smoke，验证节点可启动并出现在 ROS 图中；不启动 PX4/Gazebo/RViz，不发布 `/fmu/in/*`。
- `verify_rtabmap_depth_camera_smoke.sh`：启动 Gazebo depth camera、只读 odom child-frame bridge 和 RTAB-Map scan-cloud mode，验证 `/camera/points`、桥接 odom 和 RTAB-Map 输出 topic；不启动 Offboard、不 arm、不发布 `/fmu/in/*`。
- `capture_pcd_ransac_viewer.sh`：用 PCL Viewer 打开 filtered/inlier PCD，并截取真实点云可视化截图；可通过 `FILTERED_PCD` 和 `INLIERS_PCD` 指定文件。
- `capture_px4_gazebo_classic_gui.sh`：启动 PX4 SITL + Gazebo Classic GUI，在可用 `DISPLAY` 上截取真实 Gazebo 截图，并清理仿真进程。
- `capture_px4_aerialcore_world_gui.sh`：启动 PX4 `iris` + AerialCore 风机或两塔导线 GUI 场景，并截取真实 Gazebo 截图。
- `verify_aerialcore_worlds.sh`：串行加载 AerialCore 风机和两塔导线 world，验证 Gazebo 11 headless 可运行。
