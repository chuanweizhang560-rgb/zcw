# 开源资产与上游仓库审计

更新时间：2026-06-03 16:48:31 CST

本文件记录第一阶段外部开源项目、仿真资产和算法实现候选。执行规则是：优先复用成熟开源项目，不自行从零编写核心算法或模型。

## 1. 本机基线

| 项 | 结果 |
|---|---|
| OS | Ubuntu 22.04.5 LTS |
| ROS 2 | Humble |
| Gazebo Classic | 11.10.2 |
| ros-humble-gazebo-ros-pkgs | 3.9.0 |

## 2. 关键风险

PX4 官方文档显示，Gazebo Classic 在 PX4 v1.15 文档中只支持到 Ubuntu 20.04；Ubuntu 22.04 及以后官方建议使用新 Gazebo。当前项目硬约束是 `Gazebo 11 + ROS 2 Humble + PX4 SITL`，因此第一阶段不能擅自迁移到新 Gazebo，必须做兼容性验证。

处理策略：

1. 锁定 Gazebo 11，不迁移到 Gazebo Sim。
2. 优先评估 `PX4-SITL_gazebo-classic` 和 PX4 旧版/兼容分支。
3. 如果 PX4 Classic 链路在 Ubuntu 22.04 上无法稳定运行，必须记录阻塞并反馈，不自行改底座。

参考：

- https://docs.px4.io/v1.15/en/sim_gazebo_classic/
- https://docs.px4.io/main/en/flight_modes/offboard.html
- https://docs.px4.io/main/en/ros2/offboard_control.html

## 3. 候选清单

### 3.1 PX4 / ROS 2 / Gazebo Classic

| 候选 | 来源 | 许可证 | 用途 | 初步判断 |
|---|---|---|---|---|
| `PX4/PX4-Autopilot` | https://github.com/PX4/PX4-Autopilot | BSD-3-Clause | PX4 SITL 主体 | 必选，但需版本锁定 |
| `PX4/PX4-SITL_gazebo-classic` | https://github.com/PX4/PX4-SITL_gazebo-classic | PX4 组织 BSD-3-Clause 体系，克隆后复核 LICENSE | Gazebo Classic 插件、模型、world | Gazebo 11 主候选 |
| `PX4/px4_msgs` | https://github.com/PX4/px4_msgs | BSD-3-Clause | ROS 2 消息定义 | 必选，需按 PX4 版本选分支 |
| `PX4/px4_ros_com` | https://github.com/PX4/px4_ros_com | BSD-3-Clause | ROS 2 offboard 示例和接口参考 | 必选，优先复用示例结构 |

备注：

- PX4 Offboard 要求持续 `>2 Hz` proof-of-life，项目默认 setpoint/heartbeat 使用 `20 Hz`。
- `px4_msgs` 文档列出 Humble/Ubuntu 22.04 对应分支，后续必须和 PX4-Autopilot 版本对齐。

### 3.2 轨迹生成与低层执行

| 候选 | 来源 | 许可证 | 用途 | 初步判断 |
|---|---|---|---|---|
| `ethz-asl/mav_trajectory_generation` | https://github.com/ethz-asl/mav_trajectory_generation | Apache-2.0 | minimum-snap / polynomial trajectory generation | 可作为轨迹层候选，不替代 PX4 内环 |

备注：

- 只作为航点平滑和可行性检查层，不作为自研控制器入口。
- 需要验证 ROS 2 Humble 集成成本；若集成成本过高，第一版可只保留为离线/适配候选。

### 3.3 电缆 / 导线感知

| 候选 | 来源 | 许可证 | 用途 | 初步判断 |
|---|---|---|---|---|
| PCL `SampleConsensusModelLine` | https://pointclouds.org/documentation/classpcl_1_1_sample_consensus_model_line.html | BSD-3-Clause | 3D 线模型拟合、RANSAC 主线 | 必选基础库；本机已安装 `libpcl-dev 1.12.1` |
| ROS `pcl_ros` / `pcl_conversions` | https://github.com/ros-perception/perception_pcl | BSD | ROS 2 点云消息和 PCL 互转 | 必选接口；本机已安装 Humble `2.4.5` |
| Ceres Solver | https://github.com/ceres-solver/ceres-solver | BSD-3-Clause | catenary 曲线参数拟合 | 采用系统包 `libceres-dev 2.0.0`，不自研优化器 |
| Eigen Splines | https://eigen.tuxfamily.org/ | MPL2 | spline 曲线和平滑中心线 | 采用系统包 `libeigen3-dev 3.4.0` |
| ROS2 Gazebo Ray Sensor plugin | `/opt/ros/humble/lib/libgazebo_ros_ray_sensor.so` | Apache-2.0 / BSD 体系，见 `ros-humble-gazebo-plugins` | Gazebo ray -> ROS2 PointCloud2 | 已用于 `foggy_lidar` overlay，输出 `/zcw/foggy_lidar/points` |
| ROS2 Gazebo Camera plugin | `/opt/ros/humble/lib/libgazebo_ros_camera.so` | Apache-2.0 / BSD 体系，见 `ros-humble-gazebo-plugins` | Gazebo depth camera -> ROS2 image/depth/PointCloud2 | 已用于 PX4 官方 `iris_depth_camera`，输出 `/camera/points`；依赖 GUI 渲染和 Gazebo system plugin runtime path |
| ROS2 Gazebo P3D plugin | `/opt/ros/humble/lib/libgazebo_ros_p3d.so` | Apache-2.0 / BSD 体系，见 `ros-humble-gazebo-plugins` | Gazebo link pose -> ROS2 Odometry | 已用于 `foggy_lidar` 和 `iris_depth_camera` overlay，输出 `/zcw/foggy_lidar/pose`、`/zcw/depth_camera/pose` |
| 本仓库 `zcw_cable_perception` 薄封装 | `ros2_ws/src/zcw_cable_perception` | BSD-3-Clause | 订阅 PointCloud2/Odometry、调用 PCL CropBox/VoxelGrid/SOR/RANSAC/ExtractIndices/transformPointCloud、保存 PCD/结果，并做离线 CSV 一致性/高度层/Ceres-Eigen 拟合/offset path 审核 | 已完成单帧、5 帧 batch、world-frame、motion 多线候选、wire-band 一致性、`yz` 高度层、Ceres/Eigen catenary 输入、offset path 和 offset path 连续性 smoke test；不得扩展为自研 LiDAR 分割核心 |
| `Tury05/PowerLine-LiDAR-Detector` | https://github.com/Tury05/PowerLine-LiDAR-Detector | MIT | 导线点云检测参考 | 可复用/参考，需评估实时性和依赖 |
| PL2DM 论文方法 | https://pmc.ncbi.nlm.nih.gov/articles/PMC6515251/ | 论文方法 | LiDAR 导线检测与悬链线建模依据 | 作为算法路线依据，不直接照抄实现 |

备注：

- 电缆主线仍按 `PCL RANSAC + catenary/spline + Frenet/pure pursuit`。
- `PowerLine-LiDAR-Detector` 依赖 Conda、PDAL 和 Rust，先作为参考/离线验证候选，不能直接塞进 ROS 2 实时链路。
- 当前未找到可直接嵌入 ROS 2 Humble + PX4 的成熟 catenary 电缆跟踪包；允许写 Ceres/Eigen/PCL 的薄封装，但不能自研优化器或替代 PCL/Ceres 的核心算法。

### 3.3.1 电缆路径跟踪参考

| 候选 | 来源 | 许可证 | 用途 | 初步判断 |
|---|---|---|---|---|
| Nav2 Regulated Pure Pursuit | https://github.com/ros-navigation/navigation2/tree/humble/nav2_regulated_pure_pursuit_controller | Apache-2.0 | lookahead、曲率限速、跟踪稳定性参考 | 只做参考/可借鉴实现边界；其输出是地面机器人 `Twist`，不直接控制 PX4 |
| PX4 Offboard `TrajectorySetpoint` | https://docs.px4.io/main/en/ros2/offboard_control.html | PX4 BSD-3-Clause 体系 | 飞机实际 setpoint 执行接口 | 继续使用，不被 Nav2 替代 |

备注：

- Nav2 RPP 本地 sparse clone：`third_party/navigation2-humble`，branch `humble`，commit `e9caa42`，package 版本 `1.1.20`。
- 本机 apt 可安装 `ros-humble-nav2-regulated-pure-pursuit-controller 1.1.20-1jammy.20260425.081712`，但当前尚未安装。
- Nav2 RPP README 标注其控制器可在现代 Intel CPU 上超过 `1 kHz` 运行；该实时性结论只能作为路径跟踪参考，不能直接推断 PX4 闭环实时性。

### 3.4 多机 / 风机巡检参考

| 候选 | 来源 | 许可证 | 用途 | 初步判断 |
|---|---|---|---|---|
| `aerostack2/aerostack2` | https://github.com/aerostack2/aerostack2 | BSD-3-Clause | ROS 2 多无人机框架、风机巡检经验参考 | 可参考，不作为第一版主底座 |
| Aerostack2 文档 | https://aerostack2.github.io/_13_about_and_contact/index.html | 文档 | 风机巡检应用背景参考 | 只做参考 |

备注：

- Aerostack2 面向 ROS 2 Humble，多机能力成熟，但仿真侧偏新 Gazebo/自有框架。
- 当前项目锁定 PX4 SITL + Gazebo 11，因此不直接把 Aerostack2 作为主框架。

### 3.5 强化学习

| 候选 | 来源 | 许可证 | 用途 | 初步判断 |
|---|---|---|---|---|
| `marlbenchmark/on-policy` | https://github.com/marlbenchmark/on-policy | MIT | MAPPO 官方实现参考 | 主候选，需现代化适配 |
| Ray RLlib | https://docs.ray.io/en/latest/rllib/index.html | Apache-2.0 | PPO baseline / 训练工程候选 | 可作为 PPO baseline 工具 |

备注：

- `marlbenchmark/on-policy` 默认环境较旧，不能直接假设可在当前 Python/ROS 2 环境运行。
- 第一版先规则 baseline，再 PPO，再 MAPPO。

### 3.6 模型与场景资产

| 候选 | 来源 | 许可证 | 用途 | 初步判断 |
|---|---|---|---|---|
| Gazebo Fuel | https://gazebosim.org/docs/latest/fuel/ | 单模型独立许可证 | 查找风机、电塔、地形模型 | 必查来源 |
| Gazebo Fuel 插入/下载机制 | https://gazebosim.org/docs/latest/fuel_insert/ | 文档 | Fuel 模型下载与 SDF 引用 | 可用作资产获取流程 |
| `osrf/gazebo_models` | https://github.com/osrf/gazebo_models | 仓库级 license 需逐项复核 | Gazebo Classic SDF 模型库 | 可查通用模型/地形，仓库较大 |
| `PX4/PX4-gazebo-models` | https://github.com/PX4/PX4-gazebo-models | 需克隆后复核 | PX4 Gazebo 模型资源 | 偏新 Gazebo，Gazebo 11 兼容性待定 |

备注：

- 目前尚未确认可直接用于 Gazebo 11 的高质量风机、电塔、导线模型。
- 若公开模型不足，允许采用“公开塔架/风机模型 + 参数化导线几何”，但导线几何和安全走廊必须可物理验证。

## 4. 初步采用建议

第一批应优先克隆和评估：

1. `PX4/PX4-SITL_gazebo-classic`
2. `PX4/px4_msgs`
3. `PX4/px4_ros_com`
4. `ethz-asl/mav_trajectory_generation`
5. `Tury05/PowerLine-LiDAR-Detector`
6. `marlbenchmark/on-policy`

暂缓完整克隆：

1. `PX4/PX4-Autopilot`：体积较大，先确定 Classic 兼容分支再克隆。
2. `osrf/gazebo_models`：体积较大，先用网页/Fuel/必要子目录评估模型，再决定是否克隆。
3. `PX4/PX4-gazebo-models`：偏新 Gazebo，先确认 Gazebo 11 可用性。

## 5. 下一步

1. 建立 `third_party/` 外部仓库落点和忽略规则。
2. 克隆第一批轻量候选仓库。
3. 为每个克隆仓库补充版本、commit、许可证复核结果。
4. 开始建立 `ros2_ws` 最小骨架，不写核心算法。

## 6. 本地克隆复核结果

第一批轻量候选已经克隆到 `third_party/`。这些上游源码被 `third_party/.gitignore` 忽略，不提交进本仓库；本仓库只提交来源、commit 和判断结果。

| 仓库 | 分支 | commit | LICENSE 复核 | 初步集成结论 |
|---|---|---|---|---|
| `third_party/px4_msgs` | `main` | `18405d6` | BSD-3-Clause | 可进入 ROS 2 Humble 工作空间，但后续应按 PX4 版本切到 `release/1.14` 或 `release/1.15` |
| `third_party/px4_ros_com` | `main` | `86e9aeb` | BSD-3-Clause | 可作为 ROS 2 Offboard 示例和接口参考 |
| `third_party/PX4-SITL_gazebo-classic` | `main` | `00ac441` | `package.xml` 标注 BSD，未找到根目录 LICENSE | Gazebo 11 主候选，但许可证文件和 Ubuntu 22.04 兼容性都需继续实测 |
| `third_party/mav_trajectory_generation` | `master` | `7aeebd9` | Apache-2.0 | ROS1/catkin 生态，不能直接作为 ROS 2 Humble 主依赖；可做算法参考或离线轨迹层候选 |
| `third_party/PowerLine-LiDAR-Detector` | `main` | `1f3d7b7` | MIT | 适合做电力线点云检测参考/离线验证；依赖 Conda、PDAL、Rust，不直接进入实时链路 |
| `third_party/on-policy` | `main` | `de66d7a` | MIT | MAPPO 官方实现参考；默认 Python 3.6 环境，需要隔离或现代化适配 |
| `third_party/PX4-Autopilot-release-1.14` | `release/1.14` | `1555f2b` | BSD-3-Clause | 已实测可在本机 Gazebo Classic 11 headless 启动，作为当前 PX4 SITL 主底座 |
| `third_party/px4_msgs` | `release/1.14` | `ffb6e80` | BSD-3-Clause | 已在 ROS 2 Humble 下构建成功，与 PX4 release/1.14 对齐 |
| `third_party/px4_ros_com` | `release/v1.14` | `e18248d` | BSD-3-Clause | 已在 ROS 2 Humble 下构建成功，作为 Offboard 示例/接口参考 |
| `third_party/Micro-XRCE-DDS-Agent-v2.2.1` | tag `v2.2.1` | `f984380` | Apache-2.0 | 已用系统 FastDDS/FastCDR 构建成功，并完成 PX4 ROS 2 bridge 验证 |
| `third_party/aerialcore_simulation` | `master` | `edd912e` | `package.xml` 标注 BSD 3-Clause | 包含风机、电塔、两塔带导线等 Gazebo 资产；已完成 Gazebo 11 headless world 加载验证 |
| `third_party/navigation2-humble` | `humble` | `e9caa42` | `nav2_regulated_pure_pursuit_controller/package.xml` 标注 Apache-2.0 | sparse clone 仅用于 RPP 路径跟踪参考；不直接作为 PX4 控制器 |

立即可用结论：

1. ROS 2/PX4 消息和 Offboard 示例链路可以作为第一版主接口。
2. PX4 Classic 插件库已克隆，但必须先做 Gazebo 11 实测，不能假设已稳定。
3. `mav_trajectory_generation` 不适合直接进 ROS 2 Humble 主链路，第一版轨迹层应先保留为可选候选。
4. MAPPO 和电力线检测仓库都不应直接嵌入实时仿真主链路，应先作为离线参考和实验基线。

## 7. PX4 Classic / Gazebo 11 实测记录

本机已完成 PX4 release/1.14 的最小编译和 headless 启动验证。

实测范围：

1. `make px4_sitl_default`：成功。
2. `make px4_sitl_default sitl_gazebo-classic`：成功。
3. clean env 下 `HEADLESS=1 make px4_sitl gazebo-classic`：成功连接 Gazebo，并在 timeout 前完成 PX4 启动。

关键版本：

| 项 | 结果 |
|---|---|
| PX4-Autopilot | `release/1.14`, commit `1555f2b` |
| Gazebo Classic plugin submodule | `Tools/simulation/gazebo-classic/sitl_gazebo-classic`, commit `2e3ed9b` |
| Python venv | `/tmp/codex_zcw_px4_venv` |
| Python | system Python 3.10 venv |
| empy | fixed to `3.3.4` |

依赖处理：

1. 安装 `python3.10-venv`、`ninja-build`。
2. 安装 `libgstreamer-plugins-base1.0-dev`，解决 Gazebo Classic 插件构建中的 `gstreamer-app-1.0` 缺失。
3. 对浅克隆的 NuttX 子模块执行 `git fetch --tags --force`，解决 PX4 git version header 生成失败。
4. 构建时允许 PX4 下载/构建其上游 Micro-CDR 依赖。

结论：

PX4 Classic 虽然不是 Ubuntu 22.04 的官方推荐路线，但在本机 `Gazebo 11.10.2 + ROS 2 Humble` 下具备可运行的最小链路。下一阶段可以基于该版本固定 ROS 2 bridge 和 Offboard 入口。

## 8. PX4 ROS 2 Bridge 实测记录

版本固定：

| 项 | 结果 |
|---|---|
| `px4_msgs` | `release/1.14`, commit `ffb6e80` |
| `px4_ros_com` | `release/v1.14`, commit `e18248d` |
| Micro XRCE-DDS Agent | `v2.2.1`, commit `f984380` |
| Micro XRCE-DDS Client | PX4 内置 client version `2.2.1` |

实测范围：

1. `colcon build --symlink-install --base-paths ros2_ws/src third_party/px4_msgs third_party/px4_ros_com --packages-select px4_msgs px4_ros_com zcw_bringup zcw_sim_assets`：成功。
2. `scripts/build_microxrce_agent.sh` 对 Agent v2.2.1 clean build：成功。
3. `scripts/verify_px4_ros2_bridge_headless.sh`：成功。

bridge 成功证据：

```text
MicroXRCEAgent udp4 port: 8888 running
uxrce_dds_client synchronized
/fmu/out/vehicle_status
```

注意：

1. Agent v2.2.1 使用系统 `fmt`/`spdlog` 构建；不能让 conda 的 `fmt` 头文件进入 include path。
2. `px4_msgs main` 不用于当前链路，当前固定 `release/1.14`。
3. `px4_ros_com main` 不用于当前链路，当前固定 `release/v1.14`。

## 9. PX4 Offboard Baseline 实测记录

采用来源：

| 项 | 结果 |
|---|---|
| 上游代码来源 | `third_party/px4_ros_com/src/examples/offboard/offboard_control.cpp` |
| 上游分支 | `release/v1.14` |
| 上游 commit | `e18248d` |
| 许可证 | BSD-3-Clause |
| 本仓库派生包 | `ros2_ws/src/zcw_px4_baseline` |
| 已派生节点 | `offboard_hover_retry`、`offboard_waypoint_sequence` |

适配边界：

1. 保留 PX4 官方 BSD 许可头。
2. 不改 PX4 飞控内环，不写风机/电缆巡检算法。
3. 只增加状态订阅、Offboard/arm 命令重试、PX4 官方 Python 示例同款 QoS 和固定 waypoint setpoint 序列。

实测范围：

1. `zcw_px4_baseline/offboard_hover_retry` 构建成功。
2. `scripts/verify_px4_offboard_hover.sh` 启动 Micro XRCE-DDS Agent、PX4 SITL、Gazebo Classic headless 和 Offboard 节点。
3. 验证通过，最终 `/fmu/out/vehicle_status` 显示 `arming_state: 2`、`nav_state: 14`。

注意：

1. `px4_ros_com` 官方 C++ 示例只发一次 arm 命令；本机实测可进入 Offboard，但可能保持 `arming_state: 1`。
2. `vehicle_status` 订阅必须使用 best-effort QoS，否则 ROS 2 会报告 `RELIABILITY_QOS_POLICY` 不兼容。
3. Offboard setpoint 当前只用于悬停/waypoint baseline 验证，不代表风机巡检或电缆巡检策略。

## 10. AerialCore Gazebo Asset 实测记录

采用来源：

| 项 | 结果 |
|---|---|
| 上游仓库 | `ctu-mrs/aerialcore_simulation` |
| 来源 | https://github.com/ctu-mrs/aerialcore_simulation |
| 分支 | `master` |
| commit | `edd912e` |
| 许可证证据 | `package.xml` 标注 `BSD 3-Clause` |
| 本地引用清单 | `ros2_ws/src/zcw_sim_assets/config/open_source_assets.yaml` |

已选资产：

1. 风机 world：`worlds/wind_turbine_autospawn.world`
2. 风机 mesh：`models/wind_turbine/wind_turbine_scaled.dae`
3. 两塔带导线 world：`worlds/power_towers_danube_wires_rescaled_autospawn.world`
4. 两塔带导线 mesh：`models/power_tower_danube_2towers_wires/meshes/power_tower_danube_2tower_and_wires.dae`

实测范围：

1. `scripts/verify_aerialcore_worlds.sh` 串行加载风机 world 和两塔导线 world。
2. 两个 world 均在 Gazebo 11 headless 下连接 master 并加载 world 文件。
3. `scripts/run_px4_aerialcore_world_headless.sh` 已验证 PX4 `iris` 可在风机 world 和两塔导线 world 中启动。
4. 退出后未发现 Gazebo/PX4 残留进程。

传感器 overlay：

1. `assets/gazebo/models/foggy_lidar` 基于 PX4 release/1.14 `foggy_lidar`，保留 ray sensor 几何、range、scan pattern 和 noise。
2. 仅将插件从 PX4 MAVLink lidar plugin 替换为 ROS2 Humble `libgazebo_ros_ray_sensor.so`。
3. `scripts/verify_foggy_lidar_pointcloud.sh` 已验证 `/zcw/foggy_lidar/points` 为 `sensor_msgs/msg/PointCloud2`，样本 `width: 180`，发布频率约 `5.43 Hz`。
4. PX4 release/1.14 官方 `iris_depth_camera` 已通过 `scripts/verify_depth_camera_pointcloud.sh` 验证 `/camera/points` 为 `sensor_msgs/msg/PointCloud2`，样本 `width: 848`、`height: 480`、`point_step: 32`。
5. `assets/gazebo/models/iris_depth_camera` overlay 保留 PX4 官方 `iris` 与 `depth_camera` include，只增加官方 `gazebo_ros_p3d` 位姿插件。
6. `scripts/verify_depth_camera_pose_pointcloud.sh` 已验证 `/camera/points` 和 `/zcw/depth_camera/pose` 同时可用，pose 样本 `frame_id: world`、`child_frame_id: depth_camera::link`。
7. `scripts/verify_depth_camera_world_ransac.sh` 已完成静态 world-frame RANSAC 审核；该审核只证明成熟 PCL 管线可跑，不证明当前静态地面视角已经识别导线。
8. `scripts/verify_depth_camera_cable_motion_ransac.sh` 已完成 motion smoke 审核；该入口复用 PX4 官方 depth camera、AerialCore 导线 world、Micro XRCE-DDS Agent、现有 waypoint baseline、Gazebo ROS camera/P3D 和 PCL RANSAC。
9. depth camera 不是自建模型；当前只修正 clean env 的 ROS2/Gazebo runtime path，并使用官方 `gazebo_ros_camera` 与 `gazebo_ros_p3d` 插件。

已知警告：

1. AerialCore world 引用了本机未安装的 MRS RViz camera synchronizer plugin。
2. 该 plugin 对静态风机/导线模型可见性不是核心依赖；当前先记录为警告，不自行改上游 world。

## 11. 电缆几何离线管线实测记录

采用来源：

| 项 | 结果 |
|---|---|
| 点云线模型 | PCL `SACSegmentation<SACMODEL_LINE>` / `ExtractIndices` |
| 曲线拟合 | Ceres Solver + Eigen |
| 路径跟踪思想 | Nav2 Regulated Pure Pursuit lookahead 思路 |
| 本仓库边界 | 只做离线 CSV 审核和薄封装，不发布 PX4 setpoint |

最新实测范围：

1. 高空 wire-band ROI 多线 RANSAC 已通过真实仿真 motion smoke。
2. 多线候选已通过 `GROUP_MODE=yz` 与 `Z_BIN_SIZE=2.0` 分组、Ceres/Eigen catenary 输入烟测。
3. offset path 已通过步长、曲率、x 单调性和偏移一致性审核。
4. lookahead target 已通过离线审核：`groups=5`、`accepted_groups=5`、`targets=55`、`decision=accepted_lookahead_target_smoke`。
5. 只读 ROS topic 发布已通过：`/zcw/cable/offset_path` 与 `/zcw/cable/lookahead_target` 可被 `ros2 topic echo` 读取。
6. RViz overlay 截图已通过：Global Status、`Offset Path`、`Lookahead Target` 均为 OK，绿色路径和红色目标点可见。
7. 只读安全状态机已通过：`tracking_state=TRACK_READY`，`safety_gate=true`。

最新证据：

1. lookahead summary：`data/results/lookahead_target_audit_20260603_165600/depth_camera_motion_lookahead_target_audit_20260603_165501.txt`
2. lookahead target CSV：`data/results/lookahead_target_audit_20260603_165600/depth_camera_motion_lookahead_target_audit_targets_20260603_165501.csv`
3. lookahead group CSV：`data/results/lookahead_target_audit_20260603_165600/depth_camera_motion_lookahead_target_audit_groups_20260603_165501.csv`
4. topic node log：`data/logs/lookahead_path_publisher_20260603_170640.log`
5. offset path echo：`data/logs/lookahead_offset_path_echo_20260603_170640.log`
6. lookahead target echo：`data/logs/lookahead_target_echo_20260603_170640.log`
7. RViz screenshot：`data/screenshots/lookahead_rviz_overlay_20260603_171401.png`
8. RViz log：`data/logs/lookahead_rviz_20260603_171401.log`
9. safety state echo：`data/logs/lookahead_tracking_state_echo_20260603_172502.log`
10. safety gate echo：`data/logs/lookahead_safety_gate_echo_20260603_172502.log`

注意：

1. 当前 lookahead target 是只读离线证据，不代表无人机已经沿导线运动。
2. 下一步只能先做 PX4 Offboard dry-run 方案和验收门限，不能直接跳到完整闭环。
