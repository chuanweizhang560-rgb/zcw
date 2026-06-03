#include <algorithm>
#include <chrono>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "geometry_msgs/msg/point_stamped.hpp"
#include "geometry_msgs/msg/pose_stamped.hpp"
#include "nav_msgs/msg/path.hpp"
#include "rclcpp/rclcpp.hpp"

namespace
{
struct PathPoint
{
  std::string group_id;
  int index{0};
  double x{0.0};
  double y{0.0};
  double z{0.0};
};

struct TargetPoint
{
  std::string group_id;
  int current_index{0};
  int target_index{0};
  double x{0.0};
  double y{0.0};
  double z{0.0};
};

std::vector<std::string> split_csv_line(const std::string & line)
{
  std::vector<std::string> out;
  std::stringstream ss(line);
  std::string item;
  while (std::getline(ss, item, ',')) {
    out.push_back(item);
  }
  return out;
}

std::vector<PathPoint> read_offset_path(const std::string & path)
{
  std::ifstream in(path);
  if (!in) {
    throw std::runtime_error("failed to open offset path csv: " + path);
  }

  std::vector<PathPoint> points;
  std::string line;
  bool first = true;
  while (std::getline(in, line)) {
    if (line.empty()) {
      continue;
    }
    if (first) {
      first = false;
      continue;
    }
    const auto cols = split_csv_line(line);
    if (cols.size() != 13) {
      throw std::runtime_error("unexpected offset path column count: " + line);
    }
    PathPoint point;
    point.group_id = cols[0];
    point.index = std::stoi(cols[1]);
    point.x = std::stod(cols[2]);
    point.y = std::stod(cols[3]);
    point.z = std::stod(cols[4]);
    points.push_back(point);
  }
  return points;
}

std::vector<TargetPoint> read_targets(const std::string & path)
{
  std::ifstream in(path);
  if (!in) {
    throw std::runtime_error("failed to open lookahead targets csv: " + path);
  }

  std::vector<TargetPoint> targets;
  std::string line;
  bool first = true;
  while (std::getline(in, line)) {
    if (line.empty()) {
      continue;
    }
    if (first) {
      first = false;
      continue;
    }
    const auto cols = split_csv_line(line);
    if (cols.size() != 13) {
      throw std::runtime_error("unexpected lookahead target column count: " + line);
    }
    TargetPoint target;
    target.group_id = cols[0];
    target.current_index = std::stoi(cols[1]);
    target.target_index = std::stoi(cols[5]);
    target.x = std::stod(cols[6]);
    target.y = std::stod(cols[7]);
    target.z = std::stod(cols[8]);
    targets.push_back(target);
  }
  return targets;
}

template<typename T>
std::vector<T> filter_group(const std::vector<T> & input, const std::string & requested_group)
{
  if (input.empty()) {
    return {};
  }
  const std::string group = requested_group.empty() ? input.front().group_id : requested_group;
  std::vector<T> out;
  std::copy_if(input.begin(), input.end(), std::back_inserter(out), [&](const T & item) {
    return item.group_id == group;
  });
  return out;
}
}  // namespace

class LookaheadPathPublisher : public rclcpp::Node
{
public:
  LookaheadPathPublisher()
  : Node("lookahead_path_publisher")
  {
    const auto offset_path_csv = declare_parameter<std::string>("offset_path_csv", "");
    const auto targets_csv = declare_parameter<std::string>("targets_csv", "");
    frame_id_ = declare_parameter<std::string>("frame_id", "map");
    group_id_ = declare_parameter<std::string>("group_id", "");
    const double publish_hz = declare_parameter<double>("publish_hz", 2.0);

    if (offset_path_csv.empty() || targets_csv.empty()) {
      throw std::runtime_error("offset_path_csv and targets_csv parameters are required");
    }
    if (publish_hz <= 0.0) {
      throw std::runtime_error("publish_hz must be positive");
    }

    path_points_ = filter_group(read_offset_path(offset_path_csv), group_id_);
    targets_ = filter_group(read_targets(targets_csv), group_id_);
    if (path_points_.empty()) {
      throw std::runtime_error("no offset path points matched the requested group");
    }
    if (targets_.empty()) {
      throw std::runtime_error("no lookahead targets matched the requested group");
    }
    group_id_ = path_points_.front().group_id;

    path_pub_ = create_publisher<nav_msgs::msg::Path>(
      "/zcw/cable/offset_path", rclcpp::QoS(1).transient_local().reliable());
    target_pub_ = create_publisher<geometry_msgs::msg::PointStamped>(
      "/zcw/cable/lookahead_target", rclcpp::QoS(10));

    timer_ = create_wall_timer(
      std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::duration<double>(1.0 / publish_hz)),
      std::bind(&LookaheadPathPublisher::publish_once, this));

    RCLCPP_INFO(
      get_logger(),
      "Loaded lookahead group '%s' with %zu path points and %zu targets",
      group_id_.c_str(),
      path_points_.size(),
      targets_.size());
  }

private:
  void publish_once()
  {
    nav_msgs::msg::Path path;
    path.header.stamp = now();
    path.header.frame_id = frame_id_;
    for (const auto & point : path_points_) {
      geometry_msgs::msg::PoseStamped pose;
      pose.header = path.header;
      pose.pose.position.x = point.x;
      pose.pose.position.y = point.y;
      pose.pose.position.z = point.z;
      pose.pose.orientation.w = 1.0;
      path.poses.push_back(pose);
    }
    path_pub_->publish(path);

    const auto & target = targets_[target_cursor_ % targets_.size()];
    geometry_msgs::msg::PointStamped msg;
    msg.header.stamp = path.header.stamp;
    msg.header.frame_id = frame_id_;
    msg.point.x = target.x;
    msg.point.y = target.y;
    msg.point.z = target.z;
    target_pub_->publish(msg);
    ++target_cursor_;
  }

  std::string frame_id_;
  std::string group_id_;
  std::vector<PathPoint> path_points_;
  std::vector<TargetPoint> targets_;
  std::size_t target_cursor_{0};
  rclcpp::Publisher<nav_msgs::msg::Path>::SharedPtr path_pub_;
  rclcpp::Publisher<geometry_msgs::msg::PointStamped>::SharedPtr target_pub_;
  rclcpp::TimerBase::SharedPtr timer_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  try {
    rclcpp::spin(std::make_shared<LookaheadPathPublisher>());
  } catch (const std::exception & e) {
    std::cerr << "lookahead_path_publisher error: " << e.what() << "\n";
    rclcpp::shutdown();
    return 1;
  }
  rclcpp::shutdown();
  return 0;
}
