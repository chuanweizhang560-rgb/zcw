# zcw_cable_perception

ROS 2 integration package for cable perception smoke tests.

This package must stay as a thin wrapper around mature geometry libraries. It can call PCL/Ceres/Eigen APIs, but it must not introduce a custom LiDAR segmentation algorithm.

Current executable:

- `pointcloud_line_ransac_smoke`: subscribes to a `sensor_msgs/msg/PointCloud2`, saves the received cloud, runs PCL `SACSegmentation` with `SACMODEL_LINE`, saves inliers, and writes a small result summary.
- `pointcloud_line_ransac_batch_smoke`: collects several PointCloud2 frames, optionally applies PCL CropBox, VoxelGrid and StatisticalOutlierRemoval, runs PCL `SACSegmentation` on each frame, and writes per-frame CSV plus a batch summary.
- `pointcloud_pose_line_ransac_world_smoke`: subscribes to PointCloud2 plus `nav_msgs/msg/Odometry`, runs PCL RANSAC, and saves sensor-frame and world-frame PCD evidence using PCL `transformPointCloud`.
- `pointcloud_pose_multiline_ransac_world_smoke`: subscribes to PointCloud2 plus `nav_msgs/msg/Odometry`, applies PCL CropBox in sensor/world frames, iteratively runs PCL `SACSegmentation` with `SACMODEL_LINE`, saves multiple line candidate PCDs, and writes frame/line CSV evidence.
- `multiline_candidate_consistency_audit`: offline CSV audit for multiline candidates. It checks direction/span gates and cross-frame grouping before a candidate set can be used as catenary/spline input evidence. It supports `y`, `z`, and `yz` grouping modes.
- `catenary_fit_audit`: offline CSV audit that groups accepted line candidates, fits catenary curves with Ceres, computes a quadratic reference with Eigen, and writes fit/sample/centerline/offset-path CSV evidence.
- `offset_path_audit`: offline CSV audit for offset paths. It checks group size, monotonic x ordering, segment length, curvature, and offset consistency before lookahead target generation.
- `lookahead_target_audit`: offline CSV audit for read-only lookahead target generation. It checks target distance bounds and monotonic target index before any ROS topic or PX4 setpoint integration.
