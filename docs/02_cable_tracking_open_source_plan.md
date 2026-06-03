# 电缆巡检开源复用工作流

更新时间：2026-06-03 12:18:27 CST

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

当前 baseline 只证明 PX4 Offboard setpoint 链路和电塔导线场景可跑，不代表已经具备导线感知和追踪能力。
当前 RANSAC smoke test 只证明真实仿真 PointCloud2 能进入成熟 PCL 线模型并产生候选线，不代表已经完成导线实例识别、悬链线拟合或闭环跟踪。
当前 batch smoke test 进一步证明线模型在短时多帧中稳定存在；PCL Viewer 截图证明可视化链路可复跑；foggy lidar pose/topic 验证补齐了世界坐标基础。world-frame 审核已经证明 foggy lidar 线候选基本处于地面高度，不应视为导线。PX4 官方 depth camera 已输出 `/camera/points` 和 `/zcw/depth_camera/pose`；静态 world-frame RANSAC 不通过导线可见性验收，但运动状态组合验证已经显示塔架/导线状结构进入点云视场。宽 ROI 多线候选被一致性门限拒绝，高空 wire-band ROI 多线候选已通过一致性审核。下一步不是换传感器，而是做高度层/线路编号分组，再接 Ceres/Eigen 拟合。

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

该入口读取多线候选 CSV，按 `dir_x/dir_y/dir_z`、`x/y/z` span 和跨帧候选组数量做安全门限审核。默认读取最新宽 ROI CSV 会得到 `rejected_for_catenary_input_smoke`；用高空 wire-band ROI CSV 运行时得到 `accepted_for_catenary_input_smoke`。该入口只做审核，不输出飞控 setpoint。

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
| lookahead distance | `8-15 m` | 初始纯跟踪前视距离 |
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

1. 在高空 wire-band ROI 结果上增加高度层分组或线路编号分组，避免多根导线被 y-bin 合并成一个组。
2. 输出可复查的高度层候选 CSV、RViz/PCD 截图和失败阈值记录。
3. 高度层候选稳定后，接 Ceres/Eigen catenary/spline 与 Frenet offset path。
4. 如果 depth camera 高空 ROI 后续不稳定，再评估 Gazebo ROS2 GPU ray sensor overlay，但必须复用官方 `gazebo_ros_ray_sensor`，不自写传感器插件。
