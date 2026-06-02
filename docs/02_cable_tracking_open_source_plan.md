# 电缆巡检开源复用工作流

更新时间：2026-06-02 17:24:36 CST

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

当前 baseline 只证明 PX4 Offboard setpoint 链路和电塔导线场景可跑，不代表已经具备导线感知和追踪能力。
当前 RANSAC smoke test 只证明真实仿真 PointCloud2 能进入成熟 PCL 线模型并产生候选线，不代表已经完成导线实例识别、悬链线拟合或闭环跟踪。
当前 batch smoke test 进一步证明线模型在短时多帧中稳定存在，但仍未证明该线候选就是导线，下一步必须做可视化或几何方向一致性确认。

## 2. 采用的成熟开源组件

| 层 | 组件 | 来源/版本 | 许可证 | 采用方式 |
|---|---|---|---|---|
| 仿真机体/传感器 | PX4 Gazebo Classic `iris_foggy_lidar` + ROS2 ray sensor overlay | PX4 release/1.14 自带模型 + `ros-humble-gazebo-plugins 3.9.0` | BSD-3-Clause / Apache-2.0 体系 | 已验证 PointCloud2 topic；不重做机体和传感器几何 |
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
Gazebo/PX4 iris_rplidar or iris_depth_camera
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

1. 复用 PX4 Classic 自带 `iris_foggy_lidar` airframe。
2. 通过 `assets/gazebo/models/foggy_lidar` overlay 保持 PX4 ray sensor 参数，只替换为 ROS2 Humble `gazebo_ros_ray_sensor`。
3. 如果后续发现 2D ray 点云不足以分割导线，再评估 depth/GPU ray 方案；不得直接自研 Gazebo 传感器插件。
4. 不修改 AerialCore 电塔/导线 mesh；只允许通过 launch/env 选择 PX4 模型和 world。

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

## 6. 处理参数初值

第一版参数只作为默认值，必须放入配置文件，不写死在算法代码里：

| 参数 | 初值 | 说明 |
|---|---:|---|
| ROI 横向宽度 | `80 m` | 覆盖两塔导线 corridor |
| ROI 高度范围 | `0-80 m` | 过滤地面和过高噪声 |
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
2. PX4 `iris_rplidar` 或替代模型启动成功。
3. ROS/Gazebo topic 中能看到 LiDAR/Depth 数据。
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

1. 用 GUI/RViz 或 PCD 可视化确认线候选是否对应真实导线，而不是地面线或 2D 雷达扫描线。
2. 增加导线方向一致性/高度范围判据，避免把稳定扫描线误认为电缆。
3. 如果 2D ray 点云不足，记录失败证据后再切换 depth/GPU ray 方案。
4. 确认导线候选可靠后，再进入 Ceres/Eigen catenary/spline 拟合节点。
