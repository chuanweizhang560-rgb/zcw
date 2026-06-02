cmake_minimum_required(VERSION 3.8)
project(zcw_cable_perception)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(sensor_msgs REQUIRED)
find_package(pcl_conversions REQUIRED)
find_package(PCL REQUIRED COMPONENTS common filters io sample_consensus segmentation)

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

install(TARGETS
  pointcloud_line_ransac_smoke
  pointcloud_line_ransac_batch_smoke
  DESTINATION lib/${PROJECT_NAME}
)

ament_package()
