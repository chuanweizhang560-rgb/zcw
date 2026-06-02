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

add_executable(offboard_hover_retry src/offboard_hover_retry.cpp)
ament_target_dependencies(offboard_hover_retry rclcpp px4_msgs)
install(TARGETS offboard_hover_retry DESTINATION lib/${PROJECT_NAME})

ament_package()
