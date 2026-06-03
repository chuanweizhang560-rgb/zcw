cmake_minimum_required(VERSION 3.8)
project(zcw_px4_baseline)

if(NOT CMAKE_CXX_STANDARD)
  set(CMAKE_CXX_STANDARD 14)
endif()

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

find_package(ament_cmake REQUIRED)
find_package(px4_msgs REQUIRED)
find_package(rclcpp REQUIRED)
find_package(geometry_msgs REQUIRED)
find_package(std_msgs REQUIRED)

add_executable(offboard_hover_retry src/offboard_hover_retry.cpp)
ament_target_dependencies(offboard_hover_retry rclcpp px4_msgs)

add_executable(offboard_waypoint_sequence src/offboard_waypoint_sequence.cpp)
ament_target_dependencies(offboard_waypoint_sequence rclcpp px4_msgs)

add_executable(cable_px4_bridge_dry_run src/cable_px4_bridge_dry_run.cpp)
ament_target_dependencies(cable_px4_bridge_dry_run rclcpp geometry_msgs std_msgs)

install(TARGETS
  offboard_hover_retry
  offboard_waypoint_sequence
  cable_px4_bridge_dry_run
  DESTINATION lib/${PROJECT_NAME}
)

ament_package()
