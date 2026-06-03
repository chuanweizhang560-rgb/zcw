cmake_minimum_required(VERSION 3.8)
project(zcw_cable_perception)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(sensor_msgs REQUIRED)
find_package(nav_msgs REQUIRED)
find_package(geometry_msgs REQUIRED)
find_package(pcl_conversions REQUIRED)
find_package(PCL REQUIRED COMPONENTS common filters io sample_consensus segmentation)
find_package(Ceres REQUIRED)
find_package(Eigen3 REQUIRED)

add_executable(pointcloud_line_ransac_smoke src/pointcloud_line_ransac_smoke.cpp)
target_include_directories(pointcloud_line_ransac_smoke SYSTEM PRIVATE ${PCL_INCLUDE_DIRS})
target_link_libraries(pointcloud_line_ransac_smoke ${PCL_LIBRARIES})
ament_target_dependencies(pointcloud_line_ransac_smoke
  rclcpp
  sensor_msgs
  pcl_conversions
)

add_executable(pointcloud_line_ransac_batch_smoke src/pointcloud_line_ransac_batch_smoke.cpp)
target_include_directories(pointcloud_line_ransac_batch_smoke SYSTEM PRIVATE ${PCL_INCLUDE_DIRS})
target_link_libraries(pointcloud_line_ransac_batch_smoke ${PCL_LIBRARIES})
ament_target_dependencies(pointcloud_line_ransac_batch_smoke
  rclcpp
  sensor_msgs
  pcl_conversions
)

add_executable(pointcloud_pose_line_ransac_world_smoke src/pointcloud_pose_line_ransac_world_smoke.cpp)
target_include_directories(pointcloud_pose_line_ransac_world_smoke SYSTEM PRIVATE ${PCL_INCLUDE_DIRS})
target_link_libraries(pointcloud_pose_line_ransac_world_smoke ${PCL_LIBRARIES})
ament_target_dependencies(pointcloud_pose_line_ransac_world_smoke
  rclcpp
  sensor_msgs
  nav_msgs
  pcl_conversions
)

add_executable(pointcloud_pose_multiline_ransac_world_smoke src/pointcloud_pose_multiline_ransac_world_smoke.cpp)
target_include_directories(pointcloud_pose_multiline_ransac_world_smoke SYSTEM PRIVATE ${PCL_INCLUDE_DIRS})
target_link_libraries(pointcloud_pose_multiline_ransac_world_smoke ${PCL_LIBRARIES})
ament_target_dependencies(pointcloud_pose_multiline_ransac_world_smoke
  rclcpp
  sensor_msgs
  nav_msgs
  pcl_conversions
)

add_executable(multiline_candidate_consistency_audit src/multiline_candidate_consistency_audit.cpp)

add_executable(catenary_fit_audit src/catenary_fit_audit.cpp)
target_link_libraries(catenary_fit_audit Ceres::ceres Eigen3::Eigen)

add_executable(offset_path_audit src/offset_path_audit.cpp)

add_executable(lookahead_target_audit src/lookahead_target_audit.cpp)

add_executable(lookahead_path_publisher src/lookahead_path_publisher.cpp)
ament_target_dependencies(lookahead_path_publisher
  rclcpp
  nav_msgs
  geometry_msgs
)

install(TARGETS
  pointcloud_line_ransac_smoke
  pointcloud_line_ransac_batch_smoke
  pointcloud_pose_line_ransac_world_smoke
  pointcloud_pose_multiline_ransac_world_smoke
  multiline_candidate_consistency_audit
  catenary_fit_audit
  offset_path_audit
  lookahead_target_audit
  lookahead_path_publisher
  DESTINATION lib/${PROJECT_NAME}
)

ament_package()
