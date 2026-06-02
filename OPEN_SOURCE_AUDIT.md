# 开源资产与上游仓库审计

更新时间：2026-06-02 13:35:10 CST

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
| PCL `SampleConsensusModelLine` | https://pointclouds.org/documentation/classpcl_1_1_sample_consensus_model_line.html | BSD | 3D 线模型拟合、RANSAC 主线 | 必选基础库 |
| `Tury05/PowerLine-LiDAR-Detector` | https://github.com/Tury05/PowerLine-LiDAR-Detector | MIT | 导线点云检测参考 | 可复用/参考，需评估实时性和依赖 |
| PL2DM 论文方法 | https://pmc.ncbi.nlm.nih.gov/articles/PMC6515251/ | 论文方法 | LiDAR 导线检测与悬链线建模依据 | 作为算法路线依据，不直接照抄实现 |

备注：

- 电缆主线仍按 `PCL RANSAC + catenary/spline + Frenet/pure pursuit`。
- `PowerLine-LiDAR-Detector` 依赖 Conda、PDAL 和 Rust，先作为参考/离线验证候选，不能直接塞进 ROS 2 实时链路。

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
