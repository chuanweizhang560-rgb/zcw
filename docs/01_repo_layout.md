# 仓库目录规划

这个文件定义 `codex_zcw` 第一阶段的目标目录结构。它不是实现代码，只是执行前的结构约定。

## 1. 预期目录

```text
codex_zcw/
├── README.md
├── PROCESS_LOG.md
├── docs/
│   ├── 00_workflow.md
│   └── 01_repo_layout.md
├── scripts/
├── configs/
├── assets/
├── third_party/
├── data/
├── ros2_ws/
└── .gitignore
```

## 2. 目录职责

### `docs/`

放工作流、设计说明、实验记录、接口说明、阶段确认单。

### `scripts/`

放启动脚本、检查脚本、评估脚本、训练入口脚本。

### `configs/`

放场景配置、飞控参数、任务参数、奖励参数、训练参数。

### `assets/`

放公开模型下载后的整理结果，或者模型引用说明。

### `third_party/`

放外部克隆的公开开源仓库、固定版本的第三方实现和可直接复用的上游项目。这里的每个条目都要记录来源和许可证。

### `data/`

放日志、评估输出、实验结果、训练缓存。
建议至少预留：

- `data/screenshots/`
- `data/logs/`
- `data/results/`
- `data/training/`

### `ros2_ws/`

放 ROS 2 工作空间本体。

当前包：

- `zcw_bringup`：launch/config 入口，只做编排。
- `zcw_sim_assets`：Gazebo world/model 引用入口，只整理资产引用。
- `zcw_px4_baseline`：基于 PX4 官方 `px4_ros_com` 示例派生的 Offboard baseline，只用于仿真控制链路验证，不放风机/电缆巡检核心算法。
- `zcw_cable_perception`：电缆点云感知薄封装，只调用 PCL 等成熟库，不自研 LiDAR 分割核心算法。

## 3. 约束

1. 不把实现代码直接堆在仓库根目录。
2. 启动脚本和配置必须分离。
3. 资产和配置要分开管理。
4. 文档要先行，代码跟着文档走。
5. 进程记录文件固定放根目录，文件名为 `PROCESS_LOG.md`。
6. 外部开源仓库统一放入 `third_party/`，不要散落在根目录。
