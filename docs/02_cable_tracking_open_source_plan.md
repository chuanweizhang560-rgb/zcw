# 电缆巡检开源复用工作流

更新时间：2026-06-03 16:48:31 CST

本文档只定义电缆巡检从“固定 corridor waypoint”升级到“导线感知 + 几何跟踪”的执行路线。原则不变：不自研低层飞控，不从零造传感器/模型，不自研优化器，不把 RL 接到高频控制闭环。

## 1. 当前基线

当前已经完成：

1. Gazebo 11 + PX4 release/1.14 + ROS 2 Humble + Micro XRCE-DDS Agent。
2. AerialCore 两塔导线 world：`power_towers_danube_wires_rescaled_autospawn.world`。
3. 单机 `iris` 在两塔导线 world 中启动。
4. 固定几何 waypoint baseline：
   - launch：`zcw_bringup/single_vehicle_cable_inspection.launch.py`
   - 验证：`scripts/verify_cable_waypoints.sh`
   - 成功日志：`data/logs/waypoints_control_20260602_153812.log`
   - GUI 截图：`data/screenshots/px4_aerialcore_danube_wires_gui_20260602_154308_gazebo_left.png`
5. 传感器 smoke test：
   - overlay：`assets/gazebo/models/foggy_lidar`
   - 验证：`scripts/verify_foggy_lidar_pointcloud.sh`
   - topic：`/zcw/foggy_lidar/points`
   - 类型：`sensor_msgs/msg/PointCloud2`
   - 成功样本：`data/logs/foggy_lidar_sample_20260602_165359.log`
   - 频率：约 `5.43 Hz`
6. PCL RANSAC 线模型 smoke test：
   - 包：`ros2_ws/src/zcw_cable_perception`
   - 节点：`pointcloud_line_ransac_smoke`
   - 验证：`scripts/verify_foggy_lidar_ransac.sh`
   - 输入 topic：`/zcw/foggy_lidar/points`
   - 成功日志：`data/logs/foggy_lidar_ransac_node_20260602_171303.log`
   - 结果文件：`data/results/foggy_lidar_ransac_20260602_171303/foggy_lidar_line_ransac_20260602_171309.txt`
   - 本次结果：`raw_points=169`，`finite_points=169`，`ransac_inliers=66`，`ransac_inlier_ratio=0.390533`
7. PCL RANSAC 多帧 batch smoke test：
   - 节点：`pointcloud_line_ransac_batch_smoke`
   - 验证：`scripts/verify_foggy_lidar_ransac_batch.sh`
   - 成功日志：`data/logs/foggy_lidar_ransac_batch_node_20260602_172404.log`
   - 汇总文件：`data/results/foggy_lidar_ransac_batch_20260602_172404/foggy_lidar_line_ransac_batch_20260602_172410.txt`
   - CSV：`data/results/foggy_lidar_ransac_batch_20260602_172404/foggy_lidar_line_ransac_batch_20260602_172410.csv`
   - 本次结果：5 帧全部通过，`min_ransac_inliers=52`，`max_ransac_inliers=69`，`mean_ransac_inliers=62.2`，`mean_ransac_inlier_ratio=0.385583`，`failed_frames=0`
8. PCL Viewer 可视化审核：
   - 脚本：`scripts/capture_pcd_ransac_viewer.sh`
   - 输入：`data/results/foggy_lidar_ransac_batch_20260602_172404/frame_0_filtered.pcd` 和 `frame_0_line_inliers.pcd`
   - 截图：`data/screenshots/pcd_ransac_frame0_20260602_173227_pcl_viewer_left.png`
   - 结论：截图显示真实 PCD 中存在稳定线状候选；但缺少世界坐标、导线模型或 RViz 叠加，因此不能确认该候选就是导线。
9. foggy lidar pose / frame 验证：
   - overlay：`assets/gazebo/models/foggy_lidar`
   - 新增成熟插件：`libgazebo_ros_p3d.so`
   - 验证：`scripts/verify_foggy_lidar_pose.sh`
   - PointCloud2 frame：`foggy_lidar_link`
   - pose topic：`/zcw/foggy_lidar/pose`
   - pose 类型：`nav_msgs/msg/Odometry`
   - pose frame：`world`
   - 成功样本：
     - `data/logs/foggy_lidar_pose_points_sample_20260602_174037.log`
     - `data/logs/foggy_lidar_pose_pose_sample_20260602_174037.log`
   - 新 pose overlay 后重跑 batch：`data/results/foggy_lidar_ransac_batch_20260602_174118/foggy_lidar_line_ransac_batch_20260602_174125.txt`
   - 新 batch 结果：5 帧全部通过，`min_ransac_inliers=38`，`max_ransac_inliers=67`，`mean_ransac_inliers=57.6`，`mean_ransac_inlier_ratio=0.352688`，`failed_frames=0`
10. world-frame RANSAC 坐标审核：
   - 节点：`pointcloud_pose_line_ransac_world_smoke`
   - 验证：`scripts/verify_foggy_lidar_world_ransac.sh`
   - 汇总：`data/results/foggy_lidar_world_ransac_20260602_175348/foggy_lidar_line_ransac_world_20260602_175355.txt`
   - CSV：`data/results/foggy_lidar_world_ransac_20260602_175348/foggy_lidar_line_ransac_world_20260602_175355.csv`
   - 结果：5 帧全部通过，`min_ransac_inliers=39`，`max_ransac_inliers=63`，`mean_ransac_inliers=56.8`，`failed_frames=0`
   - world inlier bbox：min `(11.8229, -78.0769, -0.0829654)`，max `(22.6766, 79.8892, 0.084244)`
   - 审核结论：inlier 高度接近地面，且 y 方向跨度很大，不符合架空导线目标；当前 foggy lidar 2D ray 不能作为导线识别传感器。
11. PX4 官方 depth camera PointCloud2 验证：
   - 模型：PX4 release/1.14 `iris_depth_camera`
   - 验证：`scripts/verify_depth_camera_pointcloud.sh`
   - topic：`/camera/points`
   - 类型：`sensor_msgs/msg/PointCloud2`
   - frame：`camera_link`
   - 成功样本：`data/logs/depth_camera_pointcloud_sample_20260602_191429.log`
   - GUI 截图：`data/screenshots/depth_camera_pointcloud_gui_20260602_191429.png`
   - 样本字段：`width=848`，`height=480`，`point_step=32`
   - 审核边界：该节点只证明成熟 Gazebo ROS depth camera 点云链路可用；尚未证明点云覆盖真实架空导线。
12. PX4 官方 depth camera PointCloud2 + P3D pose 验证：
   - overlay：`assets/gazebo/models/iris_depth_camera`
   - 新增成熟插件：`libgazebo_ros_p3d.so`
   - 验证：`scripts/verify_depth_camera_pose_pointcloud.sh`
   - 点云 topic：`/camera/points`
   - 点云类型：`sensor_msgs/msg/PointCloud2`
   - 点云 frame：`camera_link`
   - pose topic：`/zcw/depth_camera/pose`
   - pose 类型：`nav_msgs/msg/Odometry`
   - pose frame：`world`
   - pose child frame：`depth_camera::link`
   - 成功样本：
     - `data/logs/depth_camera_pose_points_sample_20260602_204840.log`
     - `data/logs/depth_camera_pose_pose_sample_20260602_204840.log`
   - GUI 截图：`data/screenshots/depth_camera_pose_gui_20260602_204840.png`
13. PX4 官方 depth camera world-frame RANSAC 静态审核：
   - 节点：`pointcloud_pose_line_ransac_world_smoke`
   - 验证：`scripts/verify_depth_camera_world_ransac.sh`
   - 点类型兼容：world-frame smoke 节点已改为 `PointXYZ`，适配 depth camera 的 XYZ/RGB PointCloud2，不再依赖 `intensity`
   - 汇总：`data/results/depth_camera_world_ransac_20260602_211626/depth_camera_line_ransac_world_20260602_211646.txt`
   - CSV：`data/results/depth_camera_world_ransac_20260602_211626/depth_camera_line_ransac_world_20260602_211646.csv`
   - node log：`data/logs/depth_camera_world_ransac_node_20260602_211626.log`
   - Gazebo 截图：`data/screenshots/depth_camera_world_ransac_gui_20260602_211626.png`
   - PCD 截图：`data/screenshots/pcd_ransac_frame0_20260602_211833_pcl_viewer_left.png`
   - 结果：5 帧全部通过 smoke 阈值，`mean_ransac_inliers=78700.4`，`failed_frames=0`
   - world inlier bbox：min `(-46.6904, -8.0371, 0.255494)`，max `(1.47922, 1.03503, 65.5754)`
   - 审核结论：当前静态地面状态下，depth camera RANSAC inlier 呈大面积深度平面，不符合单根架空导线几何特征；不能作为导线识别结果。
14. PX4 官方 depth camera + 电缆 waypoint 运动 RANSAC 审核：
   - 验证：`scripts/verify_depth_camera_cable_motion_ransac.sh`
   - 数据流：PX4 `iris_depth_camera` + AerialCore `danube_wires` + Micro XRCE-DDS Agent + `single_vehicle_cable_inspection.launch.py` + PCL world-frame RANSAC
   - 坐标修正：`/camera/points` 使用 optical frame，P3D pose 使用 `depth_camera::link`，默认应用 optical-to-link 旋转 `sensor_rpy_rad=(-1.5708, 0, -1.5708)`
   - capture 位置：NED 约 `(-50.0052, -35.0299, -22.0264)`
   - 汇总：`data/results/depth_camera_motion_ransac_20260602_215550/depth_camera_motion_line_ransac_world_20260602_215722.txt`
   - CSV：`data/results/depth_camera_motion_ransac_20260602_215550/depth_camera_motion_line_ransac_world_20260602_215722.csv`
   - PCD 截图：`data/screenshots/pcd_ransac_frame0_20260602_215821_pcl_viewer_left.png`
   - 结果：5 帧全部通过，`mean_ransac_inliers=4405`，`failed_frames=0`
   - world inlier bbox：min `(-95.9096, 15.8306, 6.81435)`，max `(26.2537, 17.6723, 54.0478)`
   - 审核结论：运动状态下 depth camera 点云中可见塔架/多条导线状结构，PCL RANSAC 可提取线候选；该节点仍是 smoke test，不代表已完成导线实例识别、悬链线拟合或闭环追线。
15. PX4 官方 depth camera + 电缆 waypoint 运动多线候选 RANSAC 审核：
   - 节点：`pointcloud_pose_multiline_ransac_world_smoke`
   - 验证：`scripts/verify_depth_camera_cable_motion_multiline_ransac.sh`
   - 数据流：复用 PX4 官方 `iris_depth_camera`、AerialCore `danube_wires`、Micro XRCE-DDS Agent、`single_vehicle_cable_inspection.launch.py`、Gazebo P3D pose 和 PCL
   - 处理边界：只调用 PCL `CropBox`、`SACSegmentation<SACMODEL_LINE>` 和 `ExtractIndices`，不自研线分割算法
   - world ROI：min `(-120, 5, 0)`，max `(40, 30, 65)`
   - 汇总：`data/results/depth_camera_motion_ransac_20260603_111923/depth_camera_motion_multiline_ransac_world_20260603_112105.txt`
   - frame CSV：`data/results/depth_camera_motion_ransac_20260603_111923/depth_camera_motion_multiline_ransac_world_frames_20260603_112105.csv`
   - line CSV：`data/results/depth_camera_motion_ransac_20260603_111923/depth_camera_motion_multiline_ransac_world_lines_20260603_112105.csv`
   - PCD 截图：`data/screenshots/pcd_ransac_frame0_20260603_112534_pcl_viewer_left.png`
   - 结果：3 帧全部通过，每帧抽取 6 条线候选，`failed_frames=0`，`total_candidates=18`，`mean_world_roi_points=348453`
   - 审核结论：运动状态下 depth camera 点云已能稳定产生多条线候选；该节点仍是 smoke test，不代表已完成导线实例识别、悬链线拟合或闭环追线。
16. 宽 ROI 与高空 wire-band ROI 的一致性审核：
   - 离线审核工具：`multiline_candidate_consistency_audit`
   - 验证：`scripts/audit_depth_camera_multiline_consistency.sh`
   - 宽 ROI 输入：`data/results/depth_camera_motion_ransac_20260603_111923/depth_camera_motion_multiline_ransac_world_lines_20260603_112105.csv`
   - 宽 ROI 结果：`accepted_groups=0`，`decision=rejected_for_catenary_input_smoke`
   - 宽 ROI 拒绝原因：候选 `abs(dir_z)` 约 `0.318-0.436`，`z_span` 约 `40.7-56.6m`，不适合直接作为导线中心线输入
   - 高空 ROI 参数：`world_crop_min=(-120, 10, 38)`，`world_crop_max=(40, 24, 62)`
   - 高空 ROI 汇总：`data/results/depth_camera_motion_ransac_20260603_114139/depth_camera_motion_multiline_ransac_world_20260603_114312.txt`
   - 高空 ROI line CSV：`data/results/depth_camera_motion_ransac_20260603_114139/depth_camera_motion_multiline_ransac_world_lines_20260603_114312.csv`
   - 高空 ROI 一致性：`data/results/multiline_consistency_20260603_114337/depth_camera_motion_multiline_consistency_20260603_114337.txt`
   - PCD 截图：`data/screenshots/pcd_ransac_frame0_20260603_114532_pcl_viewer_left.png`
   - 高空 ROI 结果：`geometry_gate_candidates=18`，`accepted_groups=1`，`decision=accepted_for_catenary_input_smoke`
   - 审核结论：必须使用 wire-band ROI 和一致性门限，不能把宽 ROI 的任意线候选直接送入 catenary/spline。
17. 高空 wire-band ROI 的高度层分组审核：
   - 工具：`multiline_candidate_consistency_audit`
   - 验证：`scripts/audit_depth_camera_multiline_consistency.sh`
   - 推荐分组：`GROUP_MODE=yz`，`Y_BIN_SIZE=2.0`，`Z_BIN_SIZE=3.0`
   - 输入：`data/results/depth_camera_motion_ransac_20260603_114139/depth_camera_motion_multiline_ransac_world_lines_20260603_114312.csv`
   - z 分组 summary：`data/results/multiline_consistency_z_20260603_124000/depth_camera_motion_multiline_consistency_z_20260603_123714.txt`
   - z 分组 CSV：`data/results/multiline_consistency_z_20260603_124000/depth_camera_motion_multiline_consistency_z_groups_20260603_123714.csv`
   - yz 分组 summary：`data/results/multiline_consistency_yz_20260603_124000/depth_camera_motion_multiline_consistency_yz_20260603_123719.txt`
   - yz 分组 CSV：`data/results/multiline_consistency_yz_20260603_124000/depth_camera_motion_multiline_consistency_yz_groups_20260603_123719.csv`
   - 结果：`groups=6`，`accepted_groups=6`，`decision=accepted_for_catenary_input_smoke`
   - 高度层 mean z：约 `40.77m`、`43.14m`、`47.11m`、`49.88m`、`53.02m`、`55.63m`
   - 审核结论：高空 ROI 候选已能按高度层拆成 6 个稳定导线候选组；当前场景 y 维集中，`z` 和 `yz` 分组等价，但后续推荐 `yz` 以保留横向 corridor 区分能力。
18. Ceres/Eigen catenary/spline 输入烟测：
   - 工具：`catenary_fit_audit`
   - 验证：`scripts/audit_catenary_fit.sh`
   - 输入：`data/results/depth_camera_motion_ransac_20260603_114139/depth_camera_motion_multiline_ransac_world_lines_20260603_114312.csv`
   - 默认处理：`GROUP_MODE=yz`，调用 Ceres 拟合 catenary，调用 Eigen 二次曲线做残差对照
   - `Z_BIN_SIZE=3.0` summary：`data/results/catenary_fit_yz_20260603_131800/depth_camera_motion_catenary_fit_yz_20260603_125130.txt`
   - `Z_BIN_SIZE=3.0` 结果：`fit_groups=6`，`accepted_fits=5`
   - `Z_BIN_SIZE=2.0` summary：`data/results/catenary_fit_yz_zbin2_20260603_132000/depth_camera_motion_catenary_fit_yz_zbin2_20260603_125147.txt`
   - `Z_BIN_SIZE=2.0` fits CSV：`data/results/catenary_fit_yz_zbin2_20260603_132000/depth_camera_motion_catenary_fit_yz_zbin2_fits_20260603_125147.csv`
   - `Z_BIN_SIZE=2.0` 结果：`fit_groups=5`，`accepted_fits=5`，`decision=accepted_catenary_fit_smoke`
   - 审核结论：`Z_BIN_SIZE=2.0` 更稳健，避免把相邻高度层混入同一拟合组；当前可接受 5 条高度层中心线进入后续采样/offset path 烟测。
19. 中心线采样与 Frenet offset path 烟测：
   - 工具：`catenary_fit_audit`
   - 验证：`scripts/audit_catenary_fit.sh`
   - 参数：`PATH_STEP_M=10.0`，`OFFSET_Y_M=-5.0`，`OFFSET_Z_M=0.0`
   - summary：`data/results/catenary_offset_yz_zbin2_20260603_135000/depth_camera_motion_catenary_offset_yz_zbin2_20260603_125948.txt`
   - centerline CSV：`data/results/catenary_offset_yz_zbin2_20260603_135000/depth_camera_motion_catenary_offset_yz_zbin2_centerline_20260603_125948.csv`
   - offset path CSV：`data/results/catenary_offset_yz_zbin2_20260603_135000/depth_camera_motion_catenary_offset_yz_zbin2_offset_path_20260603_125948.csv`
   - 结果：`accepted_fits=5`，centerline `65` 点，offset path `65` 点
   - 审核结论：已能从 accepted Ceres/Eigen fit 生成离线中心线和几何 offset path；该结果仍不接 PX4，不发布 ROS topic。
20. offset path 连续性、曲率和步长审核：
   - 工具：`offset_path_audit`
   - 验证：`scripts/audit_offset_path.sh`
   - 输入：`data/results/catenary_offset_yz_zbin2_20260603_135000/depth_camera_motion_catenary_offset_yz_zbin2_offset_path_20260603_125948.csv`
   - summary：`data/results/offset_path_audit_20260603_143000/depth_camera_motion_offset_path_audit_20260603_164538.txt`
   - groups CSV：`data/results/offset_path_audit_20260603_143000/depth_camera_motion_offset_path_audit_groups_20260603_164538.csv`
   - 结果：`points=65`，`groups=5`，`accepted_groups=5`，`decision=accepted_offset_path_smoke`
   - 审核结论：offset path 通过步长、曲率、x 单调性和偏移一致性审核；该结果仍不接 PX4，不发布 ROS topic。
21. 只读 lookahead target 离线审核：
   - 工具：`lookahead_target_audit`
   - 验证：`scripts/audit_lookahead_target.sh`
   - 输入：`data/results/catenary_offset_yz_zbin2_20260603_135000/depth_camera_motion_catenary_offset_yz_zbin2_offset_path_20260603_125948.csv`
   - 参数：`LOOKAHEAD_M=20.0`，`MIN_TARGET_DISTANCE_M=15.0`，`MAX_TARGET_DISTANCE_M=25.0`
   - summary：`data/results/lookahead_target_audit_20260603_165600/depth_camera_motion_lookahead_target_audit_20260603_165501.txt`
   - targets CSV：`data/results/lookahead_target_audit_20260603_165600/depth_camera_motion_lookahead_target_audit_targets_20260603_165501.csv`
   - groups CSV：`data/results/lookahead_target_audit_20260603_165600/depth_camera_motion_lookahead_target_audit_groups_20260603_165501.csv`
   - 结果：`groups=5`，`accepted_groups=5`，`targets=55`，`decision=accepted_lookahead_target_smoke`
   - 审核结论：每个导线高度组都能从 offset path 生成连续、索引单调的前视目标点；该结果仍不接 PX4，不发布 ROS topic。
21.1. lookahead 距离离线 sweep：
   - 工具：`audit_lookahead_distance_sweep`
   - 验证：`scripts/audit_lookahead_distance_sweep.sh`
   - 输入：`data/results/catenary_offset_yz_zbin2_20260603_135000/depth_camera_motion_catenary_offset_yz_zbin2_offset_path_20260603_125948.csv`
   - sweep 值：`LOOKAHEAD_M=15.0`、`20.0`、`25.0`
   - summary：`data/results/lookahead_distance_sweep_20260605_161100/lookahead_distance_sweep_20260605_161100.txt`
   - sweep CSV：`data/results/lookahead_distance_sweep_20260605_161100/lookahead_distance_sweep_20260605_161100.csv`
   - 结果：`15m` 和 `20m` 的组级 mean distance 都约 `19.1671m`，`25m` 的组级 mean distance 约 `27.5006m`
   - 审核结论：当前 10m 采样的 offset path 会让 `15m` 与 `20m` lookahead 落到几乎相同的离散目标档位；若希望 lookahead 参数产生更细分的几何差异，需要更密的路径采样或更高分辨率的中心线更新。
22. 只读 ROS topic 发布烟测：
   - 工具：`lookahead_path_publisher`
   - 验证：`scripts/verify_lookahead_topic_publish.sh`
   - 输入：
     - offset path：`data/results/catenary_offset_yz_zbin2_20260603_135000/depth_camera_motion_catenary_offset_yz_zbin2_offset_path_20260603_125948.csv`
     - targets：`data/results/lookahead_target_audit_20260603_165600/depth_camera_motion_lookahead_target_audit_targets_20260603_165501.csv`
   - 输出 topic：
     - `/zcw/cable/offset_path`
     - `/zcw/cable/lookahead_target`
   - 最新日志：
     - node：`data/logs/lookahead_path_publisher_20260603_170640.log`
     - topic list：`data/logs/lookahead_topic_list_20260603_170640.log`
     - offset path echo：`data/logs/lookahead_offset_path_echo_20260603_170640.log`
     - target echo：`data/logs/lookahead_target_echo_20260603_170640.log`
   - 结果：`group='y8_z20'`，offset path `13` 点，lookahead target `11` 点
   - 审核结论：只读 ROS topic 发布已通过；当前仍不接 PX4 setpoint。
23. RViz lookahead overlay 截图审核：
   - 工具：`rviz2` + `tf2_ros static_transform_publisher`
   - 验证：`scripts/capture_lookahead_rviz_overlay.sh`
   - 配置：`ros2_ws/src/zcw_cable_perception/rviz/lookahead_overlay.rviz`
   - 输出截图：`data/screenshots/lookahead_rviz_overlay_20260603_171401.png`
   - 最新日志：
     - publisher：`data/logs/lookahead_rviz_publisher_20260603_171401.log`
     - RViz：`data/logs/lookahead_rviz_20260603_171401.log`
     - static TF：`data/logs/lookahead_rviz_static_tf_20260603_171401.log`
   - 结果：RViz Global Status 为 OK，`Offset Path` 和 `Lookahead Target` display 均为 OK
   - 审核结论：绿色 offset path 和红色 lookahead target 点可视化证据达标；当前仍不接 PX4 setpoint。
24. 只读 lookahead 安全状态机 smoke：
   - 工具：`lookahead_safety_monitor`
   - 验证：`scripts/verify_lookahead_safety_monitor.sh`
   - 输入 topic：
     - `/zcw/cable/offset_path`
     - `/zcw/cable/lookahead_target`
   - 输出 topic：
     - `/zcw/cable/tracking_state`
     - `/zcw/cable/safety_gate`
   - 最新日志：
     - publisher：`data/logs/lookahead_safety_publisher_20260603_172502.log`
     - topic list：`data/logs/lookahead_safety_topic_list_20260603_172502.log`
     - tracking state：`data/logs/lookahead_tracking_state_echo_20260603_172502.log`
     - safety gate：`data/logs/lookahead_safety_gate_echo_20260603_172502.log`
   - 结果：`TRACK_READY`，`path_points=13`，`min_target_to_path_m=0`，`last_target_jump_m=10.0005`，`safety_gate=true`
   - 审核结论：只读状态机安全门限 smoke 通过；当前仍不接 PX4 setpoint。
25. 只读 dry-run candidate setpoint smoke：
   - 工具：`lookahead_dry_run_setpoint`
   - 验证：`scripts/verify_lookahead_dry_run_setpoint.sh`
   - 输入 topic：
     - `/zcw/cable/offset_path`
     - `/zcw/cable/lookahead_target`
     - `/zcw/cable/tracking_state`
     - `/zcw/cable/safety_gate`
   - 输出 topic：
     - `/zcw/cable/dry_run/state`
     - `/zcw/cable/dry_run/candidate_setpoint`
     - `/zcw/cable/dry_run/path`
   - 最新日志：
     - state：`data/logs/lookahead_dry_run_state_echo_20260603_174508.log`
     - candidate：`data/logs/lookahead_dry_run_candidate_echo_20260603_174508.log`
     - path：`data/logs/lookahead_dry_run_path_echo_20260603_174508.log`
     - topic list：`data/logs/lookahead_dry_run_topic_list_20260603_174508.log`
     - forbidden topics：`data/logs/lookahead_dry_run_forbidden_topics_20260603_174508.log`
   - 结果：`TRACK_READY`，`candidate_jump_m=1.99995`，`candidate_speed_mps=5`，`publishes_px4=false`
   - 审核结论：dry-run candidate setpoint smoke 通过；当前仍未发布任何 `/fmu/in/*` topic。
26. 只读 dry-run candidate RViz overlay 截图审核：
   - 工具：`rviz2` + `tf2_ros static_transform_publisher`
   - 验证：`scripts/capture_lookahead_dry_run_rviz_overlay.sh`
   - 配置：`ros2_ws/src/zcw_cable_perception/rviz/dry_run_overlay.rviz`
   - 输出截图：`data/screenshots/lookahead_dry_run_rviz_overlay_20260603_175512.png`
   - 最新日志：
     - publisher：`data/logs/lookahead_dry_run_rviz_publisher_20260603_175512.log`
     - RViz：`data/logs/lookahead_dry_run_rviz_20260603_175512.log`
     - topic list：`data/logs/lookahead_dry_run_rviz_topic_list_20260603_175512.log`
     - forbidden topics：`data/logs/lookahead_dry_run_rviz_forbidden_topics_20260603_175512.log`
   - 结果：RViz Global Status、`Offset Path`、`Lookahead Target`、`Dry Run Path`、`Dry Run Candidate` 均为 OK；未发现 `/fmu/in/*`
   - 审核结论：dry-run candidate 可视化证据达标；当前仍未启动 Gazebo/PX4。
27. PX4 Offboard 隔离审计：
   - 工具：`scripts/audit_px4_isolation.sh`
   - 验证：`OUTPUT_DIR=data/results/px4_isolation_audit_20260603_180400 scripts/audit_px4_isolation.sh`
   - summary：`data/results/px4_isolation_audit_20260603_180400/px4_isolation_audit_20260603_180310.txt`
   - 结果：
     - `package.xml` 不依赖 `px4_msgs`
     - CMake 不 find/link `px4_msgs`
     - cable perception source 无 PX4 message API
     - cable perception source 不发布 `/fmu/in/*`
     - lookahead scripts 不发布 `/fmu/in/*`
     - dry-run debug topics 位于 `/zcw/cable/dry_run/*`
   - 审核结论：`decision=accepted_px4_isolation_smoke`；当前仍未接 PX4 setpoint。
28. PX4 Offboard dry-run bridge 接口计划：
   - 文档：`docs/04_cable_px4_bridge_interface_plan.md`
   - 结论：
     - bridge 不能放在 `zcw_cable_perception`
     - Phase A bridge 只允许发布 `/zcw/cable/px4_bridge/*`
     - Phase A bridge 禁止发布 `/fmu/in/trajectory_setpoint`
     - Phase A bridge 禁止发布 `/fmu/in/offboard_control_mode`
     - Phase A bridge 禁止发布 `/fmu/in/vehicle_command`
     - `map.z -> ned.z=-map.z` 仅允许作为 Phase A debug transform，不能直接作为闭环飞行依据
   - 审核结论：下一步可实现 Phase A bridge dry-run，但仍不能启动 Gazebo/PX4 或发布 `/fmu/in/*`。
29. PX4 Phase A bridge dry-run isolation smoke：
   - 工具：`cable_px4_bridge_dry_run`
   - 验证：`scripts/verify_px4_bridge_dry_run_isolation.sh`
   - 输出 topic：
     - `/zcw/cable/px4_bridge/state`
     - `/zcw/cable/px4_bridge/ned_setpoint_dry_run`
   - 最新日志：
     - state：`data/logs/px4_bridge_dry_run_state_echo_20260603_190805.log`
     - NED setpoint：`data/logs/px4_bridge_dry_run_ned_echo_20260603_190805.log`
     - topic list：`data/logs/px4_bridge_dry_run_topic_list_20260603_190805.log`
     - forbidden topics：`data/logs/px4_bridge_dry_run_forbidden_topics_20260603_190805.log`
   - 结果：`DRY_RUN_READY`，`publishes_fmu_in=false`，NED frame 为 `px4_local_ned_dry_run`，未发现 `/fmu/in/*`
   - 审核结论：Phase A bridge dry-run isolation 通过；当前仍未启动 Gazebo/PX4。
30. PX4 Phase A bridge RViz overlay 截图审核：
   - 工具：`rviz2` + `tf2_ros static_transform_publisher` + `cable_px4_bridge_dry_run`
   - 验证：`scripts/capture_px4_bridge_dry_run_rviz_overlay.sh`
   - 配置：`ros2_ws/src/zcw_cable_perception/rviz/px4_bridge_dry_run_overlay.rviz`
   - 输出截图：`data/screenshots/px4_bridge_dry_run_rviz_overlay_20260603_191816.png`
   - 最新日志：
     - bridge state：`data/logs/px4_bridge_dry_run_rviz_state_echo_20260603_191816.log`
     - bridge NED：`data/logs/px4_bridge_dry_run_rviz_ned_echo_20260603_191816.log`
     - topic list：`data/logs/px4_bridge_dry_run_rviz_topic_list_20260603_191816.log`
     - forbidden topics：`data/logs/px4_bridge_dry_run_rviz_forbidden_topics_20260603_191816.log`
   - 结果：`DRY_RUN_READY`，`publishes_fmu_in=false`，NED frame 为 `px4_local_ned_dry_run`，RViz Global Status 为 OK，未发现 `/fmu/in/*`
   - 审核结论：Phase A bridge debug 可视化通过；`px4_local_ned_dry_run` static TF 只用于显示，不代表 PX4 local frame 闭环坐标对齐完成。
31. PX4/Gazebo 只读坐标采样 smoke：
   - 工具：`px4_gazebo_frame_alignment_audit`
   - 验证：`scripts/verify_px4_gazebo_readonly_frame_alignment.sh`
   - 数据流：
     - PX4/Gazebo headless + AerialCore `danube_wires`
     - Micro XRCE-DDS Agent
     - `/fmu/out/vehicle_local_position`
     - `/zcw/depth_camera/pose`
     - `/zcw/cable/dry_run/candidate_setpoint`
     - `/zcw/cable/px4_bridge/ned_setpoint_dry_run`
   - 最新 summary：`data/results/px4_gazebo_frame_alignment_20260603_194311/px4_gazebo_frame_alignment_20260603_194311.txt`
   - 最新日志：
     - PX4/Gazebo：`data/logs/px4_gazebo_frame_alignment_px4_20260603_194311.log`
     - forbidden publishers：`data/logs/px4_gazebo_frame_alignment_forbidden_publishers_20260603_194311.log`
     - topic list：`data/logs/px4_gazebo_frame_alignment_topic_list_20260603_194311.log`
   - 结果：
     - `decision=accepted_readonly_frame_sample_smoke`
     - `px4_local_finite=true`
     - `gazebo_pose_finite=true`
     - `dry_run_ready=true`
     - `bridge_ready=true`
     - `debug_transform_smoke_ok=true`
     - 所有 `/fmu/in/*` topic 的 `Publisher count` 均为 0
   - 审核结论：已能在同一时间窗采集 PX4 local NED、Gazebo world pose、map candidate 和 bridge NED debug point；仍未启动 Offboard、未 arm、未发布 PX4 input topic。
32. Offboard 接入前 Phase B gate 设计：
   - 文档：`docs/05_cable_phase_b_gate_plan.md`
   - 结果：
     - 显式用户批准前仍禁止 `/fmu/in/*` publisher
     - gate 输出只能位于 `/zcw/cable/offboard_gate/*`
     - 第一版 gate 只能到 `PHASE_B_READY_DRY_RUN`
     - dry-run 期间车辆若意外 armed，必须进入 abort
     - 每次验证必须记录 `/fmu/in/*` publisher count
   - 审核结论：Phase B 接入边界已固化；下一步可实现 dry-run gate，但仍不能发布 setpoint。
33. Offboard gate dry-run smoke：
   - 工具：`cable_offboard_gate_dry_run`
   - 验证：`scripts/verify_cable_offboard_gate_dry_run.sh`
   - 输出 topic：
     - `/zcw/cable/offboard_gate/state`
     - `/zcw/cable/offboard_gate/phase_b_allowed`
     - `/zcw/cable/offboard_gate/ned_setpoint_approved_dry_run`
   - 最新 summary：`data/results/cable_offboard_gate_dry_run_20260604_085746/cable_offboard_gate_dry_run_20260604_085746.txt`
   - 最新日志：
     - gate state：`data/logs/cable_offboard_gate_state_echo_20260604_085746.log`
     - phase B allowed：`data/logs/cable_offboard_gate_allowed_echo_20260604_085746.log`
     - approved NED dry-run：`data/logs/cable_offboard_gate_approved_ned_echo_20260604_085746.log`
     - forbidden publishers：`data/logs/cable_offboard_gate_forbidden_publishers_20260604_085746.log`
   - 结果：
     - `decision=accepted_cable_offboard_gate_dry_run_smoke`
     - `PHASE_B_READY_DRY_RUN`
     - `phase_b_allowed=false`
     - `publishes_fmu_in=false`
     - 所有 `/fmu/in/*` topic 的 `Publisher count` 均为 0
   - 审核结论：Offboard gate dry-run 通过；仍未启动 Offboard、未 arm、未发布 PX4 input topic。
34. Offboard gate dry-run RViz/debug overlay：
   - 工具：`scripts/capture_cable_offboard_gate_dry_run_rviz_overlay.sh`
   - RViz 配置：`ros2_ws/src/zcw_cable_perception/rviz/offboard_gate_dry_run_overlay.rviz`
   - 最新 summary：`data/results/cable_offboard_gate_rviz_overlay_20260604_090442/cable_offboard_gate_rviz_overlay_20260604_090442.txt`
   - 最新截图：`data/screenshots/cable_offboard_gate_dry_run_rviz_overlay_20260604_090442.png`
   - 最新日志：
     - gate state：`data/logs/cable_offboard_gate_rviz_state_echo_20260604_090442.log`
     - phase B allowed：`data/logs/cable_offboard_gate_rviz_allowed_echo_20260604_090442.log`
     - approved NED dry-run：`data/logs/cable_offboard_gate_rviz_approved_ned_echo_20260604_090442.log`
     - forbidden publishers：`data/logs/cable_offboard_gate_rviz_forbidden_publishers_20260604_090442.log`
   - 结果：
     - `decision=accepted_cable_offboard_gate_rviz_overlay_capture`
     - `PHASE_B_READY_DRY_RUN`
     - `phase_b_allowed=false`
     - `publishes_fmu_in=false`
     - 所有 `/fmu/in/*` topic 的 `Publisher count` 均为 0
   - 审核结论：Offboard gate RViz/debug overlay 通过；截图只证明 debug topic 与 gate 状态可视化正常，不代表已进入 active Offboard 控制。
35. Phase B active bridge 前置边界审计：
   - 文档：`docs/06_cable_phase_b_active_bridge_preflight.md`
   - 工具：`scripts/audit_phase_b_active_preflight_boundary.sh`
   - 最新 summary：`data/results/phase_b_active_preflight_boundary_20260604_091412/phase_b_active_preflight_boundary_20260604_091412.txt`
   - 最新日志：
     - static checks：`data/results/phase_b_active_preflight_boundary_20260604_091412/static_checks_20260604_091412.log`
     - evidence checks：`data/results/phase_b_active_preflight_boundary_20260604_091412/evidence_checks_20260604_091412.log`
   - 结果：
     - `decision=accepted_phase_b_active_preflight_boundary`
     - `phase_b_approved=false`
     - `active_bridge_present=false`
     - `publishes_fmu_in=false`
   - 审核结论：当前仓库边界仍是 dry-run-only；没有 cable active bridge，没有 cable-specific `/fmu/in/*` publisher，脚本没有开启 `phase_b_user_approved`。这不是 Phase B 批准。
36. 电缆 active 前置坐标/安全阈值复核：
   - 文档：`docs/07_cable_active_threshold_review.md`
   - 工具：`scripts/audit_cable_setpoint_thresholds.sh`
   - 最新 summary：`data/results/cable_setpoint_thresholds_20260604_094125/cable_setpoint_thresholds_20260604_094125.txt`
   - 最新日志：
     - offset path stats：`data/results/cable_setpoint_thresholds_20260604_094125/offset_path_stats_20260604_094125.txt`
     - lookahead target stats：`data/results/cable_setpoint_thresholds_20260604_094125/lookahead_target_stats_20260604_094125.txt`
     - gate state stats：`data/results/cable_setpoint_thresholds_20260604_094125/gate_state_stats_20260604_094125.txt`
     - approved NED stats：`data/results/cable_setpoint_thresholds_20260604_094125/approved_ned_stats_20260604_094125.txt`
   - 结果：
     - `decision=accepted_cable_setpoint_threshold_audit`
     - `max_offset_step_m=10.000504`
     - `max_target_jump_m=10.000504`
     - `observed_gate_horizontal_jump_m=0.999247`
     - `observed_gate_vertical_jump_m=0.004447`
     - `publishes_fmu_in=false`
   - 审核结论：raw lookahead target 相邻间隔约 `10m`，不能直接进入 PX4；未来 active bridge 只能消费 gate-approved NED dry-run 输出，并保留 active horizontal jump `<=2.5m`、vertical jump `<=0.5m` 的门限。
37. active bridge 代码审查模板：
   - 文档：`docs/08_cable_active_bridge_code_review.md`
   - 工具：`scripts/audit_active_bridge_review_template.sh`
   - 最新 summary：`data/results/active_bridge_review_template_20260604_094724/active_bridge_review_template_20260604_094724.txt`
   - 最新日志：
     - template checks：`data/results/active_bridge_review_template_20260604_094724/template_checks_20260604_094724.log`
     - boundary checks：`data/results/active_bridge_review_template_20260604_094724/boundary_checks_20260604_094724.log`
   - 结果：
     - `decision=accepted_active_bridge_review_template_audit`
     - `phase_b_approved=false`
     - `active_bridge_present=false`
     - `publishes_fmu_in=false`
   - 审核结论：未来 active bridge 必须作为独立 executable 和独立 diff 审查；当前只建立审查模板，没有创建 active bridge。
38. dry-run readiness 总审计：
   - 文档：`docs/09_dry_run_readiness_matrix.md`
   - 工具：`scripts/audit_dry_run_readiness.sh`
   - 最新 summary：`data/results/dry_run_readiness_20260604_100331/dry_run_readiness_20260604_100331.txt`
   - 最新日志：
     - static checks：`data/results/dry_run_readiness_20260604_100331/static_repo_checks_20260604_100331.log`
     - PX4 isolation：`data/results/dry_run_readiness_20260604_100331/px4_isolation_20260604_100331.log`
     - Phase B preflight：`data/results/dry_run_readiness_20260604_100331/phase_b_preflight_20260604_100331.log`
     - thresholds：`data/results/dry_run_readiness_20260604_100331/thresholds_20260604_100331.log`
     - review template：`data/results/dry_run_readiness_20260604_100331/review_template_20260604_100331.log`
   - 结果：
     - `decision=accepted_dry_run_readiness`
     - `phase_b_approved=false`
     - `active_bridge_present=false`
     - `publishes_fmu_in=false`
   - 审核结论：当前 dry-run-only 仓库边界通过总审计；仍不能创建 active bridge 或发布 `/fmu/in/*`。

当前 baseline 只证明 PX4 Offboard setpoint 链路和电塔导线场景可跑，不代表已经具备导线感知和追踪能力。
当前 RANSAC smoke test 只证明真实仿真 PointCloud2 能进入成熟 PCL 线模型并产生候选线，不代表已经完成导线实例识别、悬链线拟合或闭环跟踪。
当前 batch smoke test 进一步证明线模型在短时多帧中稳定存在；PCL Viewer 截图证明可视化链路可复跑；foggy lidar pose/topic 验证补齐了世界坐标基础。world-frame 审核已经证明 foggy lidar 线候选基本处于地面高度，不应视为导线。PX4 官方 depth camera 已输出 `/camera/points` 和 `/zcw/depth_camera/pose`；静态 world-frame RANSAC 不通过导线可见性验收，但运动状态组合验证已经显示塔架/导线状结构进入点云视场。宽 ROI 多线候选被一致性门限拒绝，高空 wire-band ROI 多线候选已通过一致性、高度层分组、Ceres/Eigen 拟合输入烟测，并生成通过连续性和 lookahead 审核的离线中心线/offset path。只读 ROS topic、RViz overlay、只读安全状态机、dry-run candidate setpoint、dry-run RViz overlay、PX4 隔离审计、Phase A bridge dry-run isolation、Phase A bridge RViz overlay、PX4/Gazebo 只读坐标采样、Offboard gate dry-run、gate RViz/debug overlay、Phase B active preflight boundary、active 前置阈值复核、active bridge 代码审查模板和 dry-run readiness 总审计均已完成。下一步仍不能直接发布 PX4 setpoint；必须获得显式批准后才能创建 active bridge。

## 2. 采用的成熟开源组件

| 层 | 组件 | 来源/版本 | 许可证 | 采用方式 |
|---|---|---|---|---|
| 仿真机体/传感器 | PX4 Gazebo Classic `iris_foggy_lidar` + ROS2 ray sensor overlay | PX4 release/1.14 自带模型 + `ros-humble-gazebo-plugins 3.9.0` | BSD-3-Clause / Apache-2.0 体系 | 已验证 PointCloud2 topic；world-frame 审核显示不适合作为导线识别主线 |
| 仿真机体/传感器 | PX4 Gazebo Classic `iris_depth_camera` + ROS2 camera plugin | PX4 release/1.14 自带模型 + `ros-humble-gazebo-plugins 3.9.0` | BSD-3-Clause / Apache-2.0 体系 | 已验证 `/camera/points` + P3D pose；静态地面 world-frame RANSAC 不满足导线可见性验收，运动状态已可见单线和多线候选 |
| 传感器位姿 | Gazebo ROS `p3d` plugin | `/opt/ros/humble/lib/libgazebo_ros_p3d.so` | Apache-2.0 / BSD 体系，见 `ros-humble-gazebo-plugins` | 输出 `/zcw/foggy_lidar/pose` 和 `/zcw/depth_camera/pose`，用于后续点云 world 坐标叠加 |
| 点云接口 | `sensor_msgs/PointCloud2` + `pcl_conversions` + `pcl_ros` | `ros-humble-pcl-ros 2.4.5`，`ros-humble-pcl-conversions 2.4.5` | BSD | ROS2 点云消息与 PCL 互转 |
| 几何分割 | PCL `SampleConsensusModelLine` / `SACSegmentation` | `libpcl-dev 1.12.1` | BSD-3-Clause | RANSAC 线模型分割导线候选点 |
| 曲线拟合 | Ceres Solver + Eigen Splines | `libceres-dev 2.0.0`，`libeigen3-dev 3.4.0` | BSD-3-Clause / MPL2 | 用成熟优化和样条库拟合 catenary/spline，不写自研优化器 |
| 路径跟踪参考 | Nav2 Regulated Pure Pursuit | `third_party/navigation2-humble`, commit `e9caa42`, package `1.1.20` | Apache-2.0 | 只复用 lookahead/curvature/速度约束思想；不直接用其 `cmd_vel` 控制 PX4 |
| 离线导线检测参考 | `Tury05/PowerLine-LiDAR-Detector` | `third_party/PowerLine-LiDAR-Detector`, commit `1f3d7b7` | MIT | 只做离线方法参考；不直接进入实时 ROS2 闭环 |

重要边界：

1. PCL/Ceres/Eigen/Nav2 是成熟开源基础，不允许替换成自写核心算法。
2. 若要写代码，只能是 ROS2 节点封装、参数读取、消息转换、调用 PCL/Ceres/Eigen 的薄适配层。
3. catenary 残差可以使用公开标准模型，但不能自研优化流程；求解必须交给 Ceres。
4. Nav2 RPP 是地面机器人控制器，输出 `geometry_msgs/Twist`，不直接控制 PX4。PX4 仍通过 `TrajectorySetpoint` 或后续成熟 trajectory/offboard 接口执行。

## 3. 数据流

目标数据流：

```text
Gazebo/PX4 iris_depth_camera or Gazebo ROS2 GPU ray overlay
  -> sensor_msgs/PointCloud2
  -> ROI crop around cable corridor
  -> PCL outlier filtering / voxel filtering
  -> PCL RANSAC line candidate extraction
  -> Ceres catenary fit or Eigen spline fit
  -> cable centerline + Frenet frame
  -> offset inspection path
  -> pure-pursuit style lookahead target
  -> PX4 Offboard TrajectorySetpoint
```

第一版不接 RL。规则 baseline 先稳定后，策略层只能选择“跟踪哪段导线/是否重捕获/是否返航”，不能直接输出电机或姿态。

## 4. ROS2 包划分

计划新增以下包：

| 包 | 责任 | 是否包含核心算法 |
|---|---|---|
| `zcw_cable_perception` | 点云订阅、PCL 分割、候选导线点发布 | 否，只调用 PCL |
| `zcw_cable_geometry` | Ceres/Eigen 拟合、中心线、Frenet frame 和 offset path 发布 | 否，只封装 Ceres/Eigen |
| `zcw_cable_tracking` | lookahead 目标选择、速度/曲率限制、PX4 setpoint 生成 | 否，参考 Nav2 RPP 思路，输出 PX4 setpoint |
| `zcw_cable_bringup` 或继续放入 `zcw_bringup` | launch、参数、仿真组合入口 | 否 |

不新增独立低层控制包。PX4 内环继续承担位置/速度/姿态稳定。

## 5. 传感器与仿真入口

优先顺序：

1. `foggy_lidar` 已降级为 PointCloud2 管线 smoke 传感器，不能作为导线识别主线。
2. 当前主候选转为 PX4 Classic 自带 `iris_depth_camera`，通过官方 ROS 2 `gazebo_ros_camera` 输出 `/camera/points`。
3. depth camera 静态地面 world-frame RANSAC 不满足导线可见性验收；运动状态采集已通过 smoke 验证。
4. depth camera 运动点云上已完成宽 ROI 与高空 wire-band ROI 对比；宽 ROI 被拒绝，高空 ROI 通过一致性审核。
5. 如果 depth camera 后续 ROI/多线候选仍不稳定，再评估 GPU ray 方案；不得直接自研 Gazebo 传感器插件。
6. 不修改 AerialCore 电塔/导线 mesh；只允许通过 launch/env 选择 PX4 模型和 world。

下一步先做传感器 smoke test：

```bash
scripts/verify_foggy_lidar_pointcloud.sh
```

当前脚本已支持 `PX4_MODEL` 透传，并默认保持 clean env，不继承宿主旧项目的 Gazebo/LD 路径。

已新增单帧 PCL RANSAC 烟测入口：

```bash
scripts/verify_foggy_lidar_ransac.sh
```

该入口只调用 PCL `SACSegmentation` 的 `SACMODEL_LINE`，并输出 raw PCD、RANSAC inlier PCD 和文本结果；后续仍需补 ROI、多帧稳定性和导线方向一致性判据。

已新增多帧 PCL RANSAC 烟测入口：

```bash
scripts/verify_foggy_lidar_ransac_batch.sh
```

该入口在同一仿真场景中采集 5 帧 PointCloud2，调用 PCL CropBox、VoxelGrid、StatisticalOutlierRemoval 和 `SACSegmentation`，输出每帧 CSV、filtered PCD、line-inlier PCD 和 batch 汇总。

已新增 PCD 可视化截图入口：

```bash
RESULT_DIR=data/results/foggy_lidar_ransac_batch_20260602_172404 FRAME_INDEX=0 scripts/capture_pcd_ransac_viewer.sh
```

该入口只用于证据截图，不参与算法闭环。当前截图提示 2D foggy lidar 点云存在扫描线误判风险。

已新增传感器 pose 验证入口：

```bash
scripts/verify_foggy_lidar_pose.sh
```

该入口验证 PointCloud2 `frame_id=foggy_lidar_link`，并验证 `/zcw/foggy_lidar/pose` 为 `nav_msgs/msg/Odometry`、`frame_id=world`。

已新增 world-frame RANSAC 验证入口：

```bash
scripts/verify_foggy_lidar_world_ransac.sh
```

该入口会保存 sensor-frame 与 world-frame PCD。当前结果显示 foggy lidar RANSAC inlier 不是导线，后续不能再把该传感器作为电缆识别主线。

已新增 depth camera PointCloud2 验证入口：

```bash
scripts/verify_depth_camera_pointcloud.sh
```

该入口使用 PX4 direct model 模式启动官方 `iris_depth_camera`，并强制 clean env 带入 ROS 2 Humble / Gazebo system plugin runtime path。depth camera 依赖 Gazebo 渲染，默认使用 GUI 模式；headless 下不会生成深度点云。当前验证只证明 `/camera/points` 可用；位姿和运动状态 RANSAC 已由后续入口补齐。

已新增 depth camera PointCloud2 + pose 验证入口：

```bash
scripts/verify_depth_camera_pose_pointcloud.sh
```

该入口使用 `assets/gazebo/models/iris_depth_camera` overlay。overlay 保留 PX4 官方 `iris` 和 `depth_camera` include，只增加官方 `gazebo_ros_p3d` 位姿插件；不自建机体、相机或传感器插件。当前验证只证明点云和位姿 topic 同时可用；导线状候选可见性由 motion 组合入口审核。

已新增 depth camera world-frame RANSAC 审核入口：

```bash
scripts/verify_depth_camera_world_ransac.sh
```

该入口复用 PX4 官方 `iris_depth_camera`、AerialCore 两塔导线 world、Gazebo ROS camera plugin、Gazebo P3D pose 和 PCL `SACMODEL_LINE`。当前静态审核不通过导线可见性验收；后续应优先使用 motion 组合入口。

已新增 depth camera + 电缆 waypoint 运动 RANSAC 审核入口：

```bash
scripts/verify_depth_camera_cable_motion_ransac.sh
```

该入口复用已有电缆 waypoint baseline，先让无人机飞到电缆 corridor，再采集 `/camera/points` 和 `/zcw/depth_camera/pose` 做 world-frame RANSAC。当前审核显示线候选可见，但仍需 ROI、多线候选、悬链线/样条拟合与追踪状态机。

已新增 depth camera + 电缆 waypoint 运动多线候选 RANSAC 审核入口：

```bash
scripts/verify_depth_camera_cable_motion_multiline_ransac.sh
```

该入口在 motion 组合审核基础上切换到 `pointcloud_pose_multiline_ransac_world_smoke`，使用 world-frame corridor ROI，并迭代调用 PCL `SACSegmentation<SACMODEL_LINE>` / `ExtractIndices` 抽取多条线候选。当前审核已通过 3 帧、每帧 6 条候选的 smoke 阈值；仍需做候选合并、方向一致性、跨帧稳定性与后续 catenary/spline 拟合。

已新增 depth camera 多线候选一致性离线审核入口：

```bash
scripts/audit_depth_camera_multiline_consistency.sh
```

该入口读取多线候选 CSV，按 `dir_x/dir_y/dir_z`、`x/y/z` span 和跨帧候选组数量做安全门限审核。默认读取最新宽 ROI CSV 会得到 `rejected_for_catenary_input_smoke`；用高空 wire-band ROI CSV 运行时得到 `accepted_for_catenary_input_smoke`。脚本支持 `GROUP_MODE=y|z|yz`，推荐后续高空导线候选使用 `GROUP_MODE=yz`。该入口只做审核，不输出飞控 setpoint。

已新增 Ceres/Eigen catenary/spline 输入烟测入口：

```bash
scripts/audit_catenary_fit.sh
```

该入口读取高空 wire-band ROI 多线候选 CSV，复用一致性审核中的几何门限和 `GROUP_MODE=yz` 分组，调用 Ceres 拟合 catenary，并用 Eigen 二次曲线计算对照残差。它也可输出中心线采样 CSV 和 offset path CSV。该入口只输出离线文件，不发布 ROS setpoint。

已新增 offset path 连续性审核入口：

```bash
scripts/audit_offset_path.sh
```

该入口读取 offset path CSV，检查每个 group 的点数、x 单调性、单段步长、曲率和 offset 一致性。该入口只输出 summary 和 group CSV，不发布 ROS setpoint。

已新增只读 lookahead target 离线审核入口：

```bash
scripts/audit_lookahead_target.sh
```

该入口读取通过连续性审核的 offset path CSV，按每个路径点寻找前视距离目标点，并检查 target 距离窗口和 target index 单调性。该入口只输出 summary、target CSV 和 group CSV，不发布 ROS setpoint。

已新增只读 lookahead ROS topic 发布入口：

```bash
scripts/verify_lookahead_topic_publish.sh
```

该入口启动 `lookahead_path_publisher`，读取已审核 CSV，并发布 `/zcw/cable/offset_path` 与 `/zcw/cable/lookahead_target`。该入口不接 PX4、不发布 setpoint。

已新增 RViz lookahead overlay 截图入口：

```bash
scripts/capture_lookahead_rviz_overlay.sh
```

该入口启动只读 publisher、static TF 和 RViz2，加载 `lookahead_overlay.rviz`，并保存真实 RViz 截图。该入口不启动 Gazebo、不接 PX4、不发布 setpoint。

已新增只读 lookahead 安全状态机 smoke 入口：

```bash
scripts/verify_lookahead_safety_monitor.sh
```

该入口启动只读 publisher 和 `lookahead_safety_monitor`，验证 `/zcw/cable/tracking_state` 与 `/zcw/cable/safety_gate`。该入口不启动 Gazebo、不接 PX4、不发布 setpoint。

已新增只读 dry-run candidate setpoint smoke 入口：

```bash
scripts/verify_lookahead_dry_run_setpoint.sh
```

该入口启动只读 publisher、safety monitor 和 `lookahead_dry_run_setpoint`，验证 `/zcw/cable/dry_run/*` debug topics，并检查没有 `/fmu/in/*` forbidden topics。该入口不启动 Gazebo、不接 PX4、不发布 setpoint。

已新增只读 dry-run RViz overlay 截图入口：

```bash
scripts/capture_lookahead_dry_run_rviz_overlay.sh
```

该入口启动只读 publisher、safety monitor、dry-run setpoint、static TF 和 RViz2，加载 `dry_run_overlay.rviz`，并保存真实 RViz 截图。该入口不启动 Gazebo、不接 PX4、不发布 setpoint。

已新增 PX4 隔离审计入口：

```bash
scripts/audit_px4_isolation.sh
```

该入口静态检查 `zcw_cable_perception` 和 lookahead 脚本，确认当前 dry-run 管线不依赖 `px4_msgs`、不引用 PX4 message API、不发布 `/fmu/in/*`，并确认 dry-run debug topics 位于 `/zcw/cable/dry_run/*`。

已新增 PX4 Phase A bridge RViz overlay 截图入口：

```bash
scripts/capture_px4_bridge_dry_run_rviz_overlay.sh
```

该入口启动只读 lookahead pipeline、Phase A bridge dry-run、static TF 和 RViz2，加载 `px4_bridge_dry_run_overlay.rviz`，并保存真实 RViz 截图。该入口不启动 Gazebo/PX4，不发布 `/fmu/in/*`。RViz 中的 `px4_local_ned_dry_run` static TF 仅用于显示 debug 点，不是闭环坐标验证。

已新增 PX4/Gazebo 只读坐标采样入口：

```bash
scripts/verify_px4_gazebo_readonly_frame_alignment.sh
```

该入口启动 PX4/Gazebo headless、Micro XRCE-DDS Agent、只读 lookahead pipeline 和 Phase A bridge dry-run，运行 `px4_gazebo_frame_alignment_audit` 输出 summary。它不启动 Offboard、不 arm、不发布 `/fmu/in/*`。PX4 uXRCE-DDS 会让 `/fmu/in/*` 订阅 topic 出现在 ROS 图中，因此脚本逐个检查这些 topic 的 `Publisher count: 0`。

## 6. 处理参数初值

第一版参数只作为默认值，必须放入配置文件，不写死在算法代码里：

| 参数 | 初值 | 说明 |
|---|---:|---|
| ROI 横向宽度 | `80 m` | 覆盖两塔导线 corridor |
| ROI 高度范围 | `38-62 m` | 当前 AerialCore 两塔导线 world 的 wire-band smoke 初值；宽 ROI 会误收塔架斜边 |
| voxel leaf size | `0.2-0.5 m` | 降低点云密度 |
| RANSAC distance threshold | `0.2-0.5 m` | 按 Gazebo 点云噪声调整 |
| 最小导线内点数 | `50` | 少于该值触发重捕获 |
| catenary/spline 更新频率 | `1-2 Hz` | 任务级几何更新 |
| tracking setpoint 频率 | `20 Hz` | 维持 PX4 Offboard |
| 导线侧向巡检偏移 | `5 m` | 与工作流默认一致 |
| 导线上方/下方偏移 | `2-5 m` | 按传感器可见性调整 |
| lookahead distance | `20 m` | 当前离线 offset path 的 10m 采样步长下，使用 20m 前视距离通过 smoke 审核 |
| 最大 setpoint 步长 | `2-5 m` | 限制离散航点跳变 |

## 7. 验证顺序

### 7.1 传感器可用性

目标：证明复用 PX4/Gazebo 现成传感器能在 AerialCore 两塔导线 world 中输出可用数据。

验收：

1. Gazebo world 加载成功。
2. PX4 `iris_depth_camera` 或官方 Gazebo ROS2 GPU ray overlay 启动成功。
3. ROS/Gazebo topic 中能看到 Depth/PointCloud2 数据。
4. GUI 截图显示机体、导线、电塔同场景存在。

### 7.2 离线点云分割

目标：先录一段点云 bag，再离线跑 PCL 分割，避免直接把未验证感知塞进闭环。

验收：

1. bag 中有点云 topic。
2. PCL RANSAC 至少能提取一组线候选；后续必须继续验证该线候选与真实导线方向一致，而不是地面或传感器扫描线。
3. 输出调试文件：
   - 原始点云数量
   - ROI 后点数
   - RANSAC 内点数
   - line/catenary/spline 参数

### 7.3 在线几何发布

目标：把离线分割封装为 ROS2 节点，但不控制飞机。

验收：

1. 节点发布 `nav_msgs/Path` 或自定义最小消息表示导线中心线。
2. RViz 可显示原始点云、RANSAC 内点、拟合中心线、offset path。
3. 失败时能发布 `tracking_lost` 状态，不输出错误 setpoint。

### 7.4 只读跟踪目标

目标：根据中心线和当前位置计算 lookahead target，但不发 PX4 setpoint。

验收：

1. RViz 显示 lookahead point。
2. lookahead point 沿导线连续推进。
3. 导线丢失时进入重捕获或保持模式。

### 7.5 PX4 闭环接入

目标：把 lookahead target 接到已有 `offboard_waypoint_sequence` 同类 setpoint 链路。

验收：

1. PX4 保持 `arming_state: 2`、`nav_state: 14`。
2. setpoint 频率保持 `20 Hz`。
3. 机体沿导线 offset path 前进。
4. GUI/RViz 截图确认机体、导线和跟踪路径一致。

## 8. 重捕获机制

必须保留重捕获，不允许导线丢失后继续盲飞。

触发条件：

1. RANSAC 内点数低于阈值。
2. 拟合残差超过阈值。
3. lookahead point 跳变超过最大 setpoint 步长。
4. 连续 `N` 帧没有有效导线。

动作：

1. 停止更新前进 setpoint。
2. 回到最近有效中心线点或安全 hover 点。
3. 执行小范围左右/上下扫描。
4. 恢复足够内点后继续巡检。

## 9. 当前不做

1. 不做 RL 策略接入。
2. 不做多机电缆协同。
3. 不做自定义 Gazebo 传感器插件。
4. 不做自研 LiDAR 分割算法。
5. 不做视觉识别和缺陷检测。
6. 不把 Nav2 RPP 直接作为 PX4 控制器。

## 10. 下一个执行节点

1. 为 Offboard gate dry-run 增加 RViz/debug overlay，或先写 Phase B active bridge 方案评审文档。
2. 若未来接 PX4，必须先经过状态机安全门限，不直接从 topic 接 setpoint。
3. 任何 active bridge 都必须作为独立 executable，不能修改 dry-run gate 变成 active publisher。
4. 如果 depth camera 高空 ROI 后续不稳定，再评估 Gazebo ROS2 GPU ray sensor overlay，但必须复用官方 `gazebo_ros_ray_sensor`，不自写传感器插件。
