# zcw_cable_perception

ROS 2 integration package for cable perception smoke tests.

This package must stay as a thin wrapper around mature geometry libraries. It can call PCL/Ceres/Eigen APIs, but it must not introduce a custom LiDAR segmentation algorithm.

Current executable:

- `pointcloud_line_ransac_smoke`: subscribes to a `sensor_msgs/msg/PointCloud2`, saves the received cloud, runs PCL `SACSegmentation` with `SACMODEL_LINE`, saves inliers, and writes a small result summary.
