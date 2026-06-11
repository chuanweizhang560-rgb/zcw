#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>

#include <geometry_msgs/msg/point_stamped.hpp>
#include <px4_msgs/msg/vehicle_local_position.hpp>
#include <px4_msgs/msg/vehicle_status.hpp>
#include <rclcpp/rclcpp.hpp>
#include <std_msgs/msg/string.hpp>
#include <visualization_msgs/msg/marker.hpp>
#include <visualization_msgs/msg/marker_array.hpp>

class FourVehicleDryRunPlanner : public rclcpp::Node
{
public:
  FourVehicleDryRunPlanner()
  : Node("four_vehicle_dry_run_planner")
  {
    publish_hz_ = declare_parameter<double>("publish_hz", 2.0);
    base_x_ = declare_parameter<double>("base_x", 0.0);
    base_y_ = declare_parameter<double>("base_y", 0.0);
    relay_radius_m_ = declare_parameter<double>("relay_radius_m", 800.0);
    goal_acceptance_radius_m_ = declare_parameter<double>("goal_acceptance_radius_m", 5.0);
    max_state_age_sec_ = declare_parameter<double>("max_state_age_sec", 2.0);

    const std::array<std::array<double, 3>, 4> default_goals{{
      {{-25.0, -10.0, -20.0}},
      {{-35.0, 20.0, -18.0}},
      {{-12.5, -5.0, -12.0}},
      {{-17.5, 10.0, -12.0}},
    }};
    for (std::size_t i = 0; i < vehicles_.size(); ++i) {
      const auto index = i + 1;
      vehicles_[i].goal_x = declare_parameter<double>(
        "vehicle_" + std::to_string(index) + "_goal_x", default_goals[i][0]);
      vehicles_[i].goal_y = declare_parameter<double>(
        "vehicle_" + std::to_string(index) + "_goal_y", default_goals[i][1]);
      vehicles_[i].goal_z = declare_parameter<double>(
        "vehicle_" + std::to_string(index) + "_goal_z", default_goals[i][2]);
    }

    if (publish_hz_ <= 0.0 || relay_radius_m_ <= 0.0 ||
      goal_acceptance_radius_m_ < 0.0 || max_state_age_sec_ <= 0.0)
    {
      throw std::runtime_error("invalid four_vehicle_dry_run_planner parameter");
    }

    const auto qos = rclcpp::SensorDataQoS();
    const std::array<std::string, 4> px4_prefixes{{
      "/px4_1/fmu/out/",
      "/px4_2/fmu/out/",
      "/px4_3/fmu/out/",
      "/px4_4/fmu/out/",
    }};
    const std::array<std::string, 4> goal_topics{{
      "/zcw/multi_vehicle/four_vehicle_dry_run/vehicle_1_goal",
      "/zcw/multi_vehicle/four_vehicle_dry_run/vehicle_2_goal",
      "/zcw/multi_vehicle/four_vehicle_dry_run/vehicle_3_goal",
      "/zcw/multi_vehicle/four_vehicle_dry_run/vehicle_4_goal",
    }};

    for (std::size_t i = 0; i < vehicles_.size(); ++i) {
      vehicles_[i].position_sub = create_subscription<px4_msgs::msg::VehicleLocalPosition>(
        px4_prefixes[i] + "vehicle_local_position", qos,
        [this, i](px4_msgs::msg::VehicleLocalPosition::SharedPtr msg) {
          vehicles_[i].position = msg;
          vehicles_[i].position_time = now();
        });
      vehicles_[i].status_sub = create_subscription<px4_msgs::msg::VehicleStatus>(
        px4_prefixes[i] + "vehicle_status", qos,
        [this, i](px4_msgs::msg::VehicleStatus::SharedPtr msg) {
          vehicles_[i].status = msg;
          vehicles_[i].status_time = now();
        });
      vehicles_[i].goal_pub = create_publisher<geometry_msgs::msg::PointStamped>(
        goal_topics[i], 10);
    }

    topology_pub_ = create_publisher<std_msgs::msg::String>(
      "/zcw/multi_vehicle/four_vehicle_dry_run/topology_state", 10);
    safety_pub_ = create_publisher<std_msgs::msg::String>(
      "/zcw/multi_vehicle/four_vehicle_dry_run/safety_state", 10);
    assignment_pub_ = create_publisher<std_msgs::msg::String>(
      "/zcw/multi_vehicle/four_vehicle_dry_run/assignment_state", 10);
    scoring_pub_ = create_publisher<std_msgs::msg::String>(
      "/zcw/multi_vehicle/four_vehicle_dry_run/scoring_state", 10);
    score_markers_pub_ = create_publisher<visualization_msgs::msg::MarkerArray>(
      "/zcw/multi_vehicle/four_vehicle_dry_run/score_markers", 10);

    timer_ = create_wall_timer(
      std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::duration<double>(1.0 / publish_hz_)),
      [this]() { publish_dry_run(); });
  }

private:
  struct VehicleState
  {
    double goal_x{0.0};
    double goal_y{0.0};
    double goal_z{0.0};
    rclcpp::Time position_time{0, 0, RCL_ROS_TIME};
    rclcpp::Time status_time{0, 0, RCL_ROS_TIME};
    px4_msgs::msg::VehicleLocalPosition::SharedPtr position;
    px4_msgs::msg::VehicleStatus::SharedPtr status;
    rclcpp::Subscription<px4_msgs::msg::VehicleLocalPosition>::SharedPtr position_sub;
    rclcpp::Subscription<px4_msgs::msg::VehicleStatus>::SharedPtr status_sub;
    rclcpp::Publisher<geometry_msgs::msg::PointStamped>::SharedPtr goal_pub;
  };

  bool fresh(const rclcpp::Time & stamp, const rclcpp::Time & t) const
  {
    return stamp.nanoseconds() > 0 && (t - stamp).seconds() <= max_state_age_sec_;
  }

  static bool valid_position(const px4_msgs::msg::VehicleLocalPosition & msg)
  {
    return msg.xy_valid && msg.z_valid &&
           std::isfinite(msg.x) && std::isfinite(msg.y) && std::isfinite(msg.z);
  }

  static double distance_xy(double ax, double ay, double bx, double by)
  {
    const double dx = ax - bx;
    const double dy = ay - by;
    return std::sqrt(dx * dx + dy * dy);
  }

  geometry_msgs::msg::PointStamped goal_msg(double x, double y, double z) const
  {
    geometry_msgs::msg::PointStamped msg;
    msg.header.stamp = now();
    msg.header.frame_id = "px4_local_ned";
    msg.point.x = x;
    msg.point.y = y;
    msg.point.z = z;
    return msg;
  }

  void publish_dry_run()
  {
    const auto t = now();
    std::array<bool, 4> pose_ready{};
    std::array<bool, 4> status_ready{};
    std::array<double, 4> base_distance{};
    std::array<double, 4> goal_distance{};
    bool all_pose_ready = true;
    bool all_status_ready = true;
    bool topology_ready = true;

    for (std::size_t i = 0; i < vehicles_.size(); ++i) {
      vehicles_[i].goal_pub->publish(
        goal_msg(vehicles_[i].goal_x, vehicles_[i].goal_y, vehicles_[i].goal_z));
      pose_ready[i] = vehicles_[i].position && fresh(vehicles_[i].position_time, t) &&
        valid_position(*vehicles_[i].position);
      status_ready[i] = vehicles_[i].status && fresh(vehicles_[i].status_time, t);
      all_pose_ready = all_pose_ready && pose_ready[i];
      all_status_ready = all_status_ready && status_ready[i];
      base_distance[i] = -1.0;
      goal_distance[i] = -1.0;
      if (pose_ready[i]) {
        base_distance[i] = distance_xy(
          vehicles_[i].position->x, vehicles_[i].position->y, base_x_, base_y_);
        goal_distance[i] = distance_xy(
          vehicles_[i].position->x, vehicles_[i].position->y,
          vehicles_[i].goal_x, vehicles_[i].goal_y);
        topology_ready = topology_ready && base_distance[i] <= relay_radius_m_;
      } else {
        topology_ready = false;
      }
    }

    double chain_max_distance = -1.0;
    double chain_min_margin = -1.0;
    if (all_pose_ready) {
      for (std::size_t i = 1; i < vehicles_.size(); ++i) {
        const auto & a = *vehicles_[i - 1].position;
        const auto & b = *vehicles_[i].position;
        const auto d = distance_xy(a.x, a.y, b.x, b.y);
        chain_max_distance = std::max(chain_max_distance, d);
        const auto margin = relay_radius_m_ - d;
        chain_min_margin = (chain_min_margin < 0.0) ? margin : std::min(chain_min_margin, margin);
        topology_ready = topology_ready && d <= relay_radius_m_;
      }
    }
    const bool safety_ready = topology_ready && all_status_ready;

    double mean_goal_distance = -1.0;
    if (all_pose_ready) {
      double sum_goal_distance = 0.0;
      for (const auto d : goal_distance) {
        sum_goal_distance += d;
      }
      mean_goal_distance = sum_goal_distance / static_cast<double>(goal_distance.size());
    }
    const double topology_score = topology_ready ? 1.0 : 0.0;
    const double state_score = (all_pose_ready && all_status_ready) ? 1.0 : 0.0;
    const double task_distance_score = (mean_goal_distance >= 0.0) ?
      1.0 / (1.0 + mean_goal_distance / relay_radius_m_) : 0.0;
    const double rule_total_score =
      0.45 * topology_score + 0.30 * state_score + 0.25 * task_distance_score;

    std_msgs::msg::String topology_msg;
    std::ostringstream topology;
    topology << (topology_ready ? "FOUR_TOPOLOGY_READY" : "FOUR_TOPOLOGY_HOLD")
             << "; dry_run=true"
             << "; publishes_fmu_in=false"
             << "; relay_radius_m=" << relay_radius_m_
             << "; chain_max_distance_m=" << chain_max_distance;
    for (std::size_t i = 0; i < vehicles_.size(); ++i) {
      topology << "; vehicle_" << (i + 1) << "_base_distance_m=" << base_distance[i];
    }
    topology_msg.data = topology.str();
    topology_pub_->publish(topology_msg);

    std_msgs::msg::String safety_msg;
    std::ostringstream safety;
    safety << (safety_ready ? "FOUR_SAFETY_READY_DRY_RUN" : "FOUR_SAFETY_HOLD")
           << "; dry_run=true"
           << "; starts_offboard=false"
           << "; arms=false"
           << "; publishes_fmu_in=false";
    for (std::size_t i = 0; i < vehicles_.size(); ++i) {
      safety << "; vehicle_" << (i + 1) << "_pose_ready=" << (pose_ready[i] ? "true" : "false")
             << "; vehicle_" << (i + 1) << "_status_ready=" << (status_ready[i] ? "true" : "false")
             << "; vehicle_" << (i + 1) << "_goal_distance_m=" << goal_distance[i];
    }
    safety << "; goal_acceptance_radius_m=" << goal_acceptance_radius_m_;
    safety_msg.data = safety.str();
    safety_pub_->publish(safety_msg);

    std_msgs::msg::String assignment_msg;
    std::ostringstream assignment;
    assignment << "FOUR_RULE_BASELINE_DRY_RUN"
               << "; dry_run=true"
               << "; learned_policy=false"
               << "; starts_offboard=false"
               << "; arms=false"
               << "; publishes_fmu_in=false"
               << "; vehicle_1_role=wind_inspection_candidate"
               << "; vehicle_2_role=cable_inspection_candidate"
               << "; vehicle_3_role=relay_candidate"
               << "; vehicle_4_role=relay_candidate"
               << "; topology_ready=" << (topology_ready ? "true" : "false")
               << "; safety_ready=" << (safety_ready ? "true" : "false");
    assignment_msg.data = assignment.str();
    assignment_pub_->publish(assignment_msg);

    std_msgs::msg::String scoring_msg;
    std::ostringstream scoring;
    scoring << "FOUR_RULE_SCORE_DRY_RUN"
            << "; dry_run=true"
            << "; learned_policy=false"
            << "; starts_offboard=false"
            << "; arms=false"
            << "; publishes_fmu_in=false"
            << "; topology_score=" << topology_score
            << "; state_score=" << state_score
            << "; task_distance_score=" << task_distance_score
            << "; rule_total_score=" << rule_total_score
            << "; chain_max_distance_m=" << chain_max_distance
            << "; chain_min_margin_m=" << chain_min_margin
            << "; mean_goal_distance_m=" << mean_goal_distance
            << "; vehicle_1_task=wind_inspection_candidate"
            << "; vehicle_2_task=cable_inspection_candidate"
            << "; vehicle_3_task=relay_candidate"
            << "; vehicle_4_task=relay_candidate";
    scoring_msg.data = scoring.str();
    scoring_pub_->publish(scoring_msg);

    visualization_msgs::msg::MarkerArray markers;
    auto text_marker = visualization_msgs::msg::Marker();
    text_marker.header.stamp = now();
    text_marker.header.frame_id = "px4_local_ned";
    text_marker.ns = "four_vehicle_dry_run_score";
    text_marker.id = 1;
    text_marker.type = visualization_msgs::msg::Marker::TEXT_VIEW_FACING;
    text_marker.action = visualization_msgs::msg::Marker::ADD;
    text_marker.pose.position.x = -25.0;
    text_marker.pose.position.y = 4.0;
    text_marker.pose.position.z = -4.0;
    text_marker.pose.orientation.w = 1.0;
    text_marker.scale.z = 3.0;
    text_marker.color.r = 0.95F;
    text_marker.color.g = 0.95F;
    text_marker.color.b = 0.95F;
    text_marker.color.a = 1.0F;
    text_marker.text =
      "FOUR_RULE_SCORE_DRY_RUN\n"
      "total=" + std::to_string(rule_total_score) +
      " topology=" + std::to_string(topology_score) +
      " state=" + std::to_string(state_score) +
      "\ntask_distance=" + std::to_string(task_distance_score) +
      " chain_margin_m=" + std::to_string(chain_min_margin);
    markers.markers.push_back(text_marker);

    const std::array<const char *, 4> role_labels{{
      "V1 wind",
      "V2 cable",
      "V3 relay",
      "V4 relay",
    }};
    for (std::size_t i = 0; i < vehicles_.size(); ++i) {
      auto role_marker = visualization_msgs::msg::Marker();
      role_marker.header.stamp = text_marker.header.stamp;
      role_marker.header.frame_id = "px4_local_ned";
      role_marker.ns = "four_vehicle_dry_run_roles";
      role_marker.id = static_cast<int>(10 + i);
      role_marker.type = visualization_msgs::msg::Marker::TEXT_VIEW_FACING;
      role_marker.action = visualization_msgs::msg::Marker::ADD;
      role_marker.pose.position.x = vehicles_[i].goal_x;
      role_marker.pose.position.y = vehicles_[i].goal_y;
      role_marker.pose.position.z = vehicles_[i].goal_z - 3.0;
      role_marker.pose.orientation.w = 1.0;
      role_marker.scale.z = 2.0;
      role_marker.color.r = 0.85F;
      role_marker.color.g = 0.92F;
      role_marker.color.b = 1.0F;
      role_marker.color.a = 1.0F;
      role_marker.text = role_labels[i];
      markers.markers.push_back(role_marker);
    }
    score_markers_pub_->publish(markers);
  }

  double publish_hz_{2.0};
  double base_x_{0.0};
  double base_y_{0.0};
  double relay_radius_m_{800.0};
  double goal_acceptance_radius_m_{5.0};
  double max_state_age_sec_{2.0};
  std::array<VehicleState, 4> vehicles_{};
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr topology_pub_;
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr safety_pub_;
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr assignment_pub_;
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr scoring_pub_;
  rclcpp::Publisher<visualization_msgs::msg::MarkerArray>::SharedPtr score_markers_pub_;
  rclcpp::TimerBase::SharedPtr timer_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  try {
    rclcpp::spin(std::make_shared<FourVehicleDryRunPlanner>());
  } catch (const std::exception & e) {
    std::cerr << "four_vehicle_dry_run_planner error: " << e.what() << "\n";
    rclcpp::shutdown();
    return 1;
  }
  rclcpp::shutdown();
  return 0;
}
