# zcw_cable_perception

ROS 2 integration package for cable perception smoke tests.

This package must stay as a thin wrapper around mature geometry libraries. It can call PCL/Ceres/Eigen APIs, but it must not introduce a custom LiDAR segmentation algorithm.

Current executable:

- `pointcloud_line_ransac_smoke`: subscribes to a `sensor_msgs/msg/PointCloud2`, saves the received cloud, runs PCL `SACSegmentation` with `SACMODEL_LINE`, saves inliers, and writes a small result summary.
- `pointcloud_line_ransac_batch_smoke`: collects several PointCloud2 frames, optionally applies PCL CropBox, VoxelGrid and StatisticalOutlierRemoval, runs PCL `SACSegmentation` on each frame, and writes per-frame CSV plus a batch summary.
- `pointcloud_pose_line_ransac_world_smoke`: subscribes to PointCloud2 plus `nav_msgs/msg/Odometry`, runs PCL RANSAC, and saves sensor-frame and world-frame PCD evidence using PCL `transformPointCloud`.
