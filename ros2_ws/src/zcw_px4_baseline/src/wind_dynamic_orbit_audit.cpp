#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <memory>
#include <numeric>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include <px4_msgs/msg/vehicle_local_position.hpp>
#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/image_encodings.hpp>
#include <sensor_msgs/msg/image.hpp>

namespace
{
std::string stamp_string()
{
  const auto now = std::chrono::system_clock::now();
  const auto time = std::chrono::system_clock::to_time_t(now);
  std::tm tm{};
  localtime_r(&time, &tm);
  std::ostringstream out;
  out << std::put_time(&tm, "%Y%m%d_%H%M%S");
  return out.str();
}

std::string bool_text(bool value)
{
  return value ? "true" : "false";
}

struct PoseSample
{
  double t_sec{};
  double x{};
  double y{};
  double z{};
  double center_xy_radius{};
  double radius_error{};
  double conservative_clearance{};
  bool xy_valid{};
  bool z_valid{};
};

struct DepthSample
{
  int frame_index{};
  std::uint32_t sec{};
  std::uint32_t nanosec{};
  std::size_t total_pixels{};
  std::size_t finite_positive_pixels{};
  std::size_t useful_depth_pixels{};
  std::size_t far_or_saturated_pixels{};
  std::size_t invalid_pixels{};
  double valid_ratio{};
  double useful_ratio{};
  double min_depth_m{};
  double max_depth_m{};
  double mean_depth_m{};
  double mean_useful_depth_m{};
};

template<typename T>
void scan_depth(
  const sensor_msgs::msg::Image & msg,
  double scale_to_m,
  double saturation_depth_m,
  DepthSample & sample)
{
  const auto bytes_per_pixel = sizeof(T);
  if (msg.step < msg.width * bytes_per_pixel) {
    throw std::runtime_error("Image step is smaller than width * pixel size");
  }

  double sum = 0.0;
  double useful_sum = 0.0;
  sample.min_depth_m = std::numeric_limits<double>::infinity();
  sample.max_depth_m = -std::numeric_limits<double>::infinity();

  for (std::uint32_t row = 0; row < msg.height; ++row) {
    const auto * row_data = msg.data.data() + row * msg.step;
    for (std::uint32_t col = 0; col < msg.width; ++col) {
      T raw{};
      std::memcpy(&raw, row_data + col * bytes_per_pixel, bytes_per_pixel);
      const double depth_m = static_cast<double>(raw) * scale_to_m;
      if (std::isfinite(depth_m) && depth_m > 0.0) {
        ++sample.finite_positive_pixels;
        sum += depth_m;
        sample.min_depth_m = std::min(sample.min_depth_m, depth_m);
        sample.max_depth_m = std::max(sample.max_depth_m, depth_m);
        if (depth_m < saturation_depth_m) {
          ++sample.useful_depth_pixels;
          useful_sum += depth_m;
        } else {
          ++sample.far_or_saturated_pixels;
        }
      } else {
        ++sample.invalid_pixels;
      }
    }
  }

  if (sample.finite_positive_pixels > 0) {
    sample.mean_depth_m = sum / static_cast<double>(sample.finite_positive_pixels);
  } else {
    sample.min_depth_m = 0.0;
    sample.max_depth_m = 0.0;
    sample.mean_depth_m = 0.0;
  }
  sample.valid_ratio = sample.total_pixels == 0 ? 0.0 :
    static_cast<double>(sample.finite_positive_pixels) / static_cast<double>(sample.total_pixels);
  sample.useful_ratio = sample.total_pixels == 0 ? 0.0 :
    static_cast<double>(sample.useful_depth_pixels) / static_cast<double>(sample.total_pixels);
  sample.mean_useful_depth_m = sample.useful_depth_pixels == 0 ? 0.0 :
    useful_sum / static_cast<double>(sample.useful_depth_pixels);
}
}  // namespace

class WindDynamicOrbitAudit : public rclcpp::Node
{
public:
  WindDynamicOrbitAudit()
  : Node("wind_dynamic_orbit_audit")
  {
    output_dir_ = declare_parameter<std::string>("output_dir", "data/results/wind_dynamic_orbit_audit");
    duration_sec_ = declare_parameter<double>("duration_sec", 45.0);
    sample_rate_hz_ = declare_parameter<double>("sample_rate_hz", 10.0);
    center_x_ = declare_parameter<double>("center_x", -25.0);
    center_y_ = declare_parameter<double>("center_y", -25.0);
    expected_radius_m_ = declare_parameter<double>("expected_radius_m", 20.0);
    conservative_mesh_radius_m_ = declare_parameter<double>("conservative_mesh_radius_m", 11.880407);
    min_clearance_m_ = declare_parameter<double>("min_clearance_m", 1.0);
    max_radius_error_m_ = declare_parameter<double>("max_radius_error_m", 8.0);
    min_mean_useful_ratio_ = declare_parameter<double>("min_mean_useful_ratio", 0.001);
    min_any_useful_ratio_ = declare_parameter<double>("min_any_useful_ratio", 0.01);
    saturation_depth_m_ = declare_parameter<double>("saturation_depth_m", 65.0);

    if (duration_sec_ <= 0.0 || sample_rate_hz_ <= 0.0) {
      throw std::runtime_error("duration_sec and sample_rate_hz must be positive");
    }
    std::filesystem::create_directories(output_dir_);
    stamp_ = stamp_string();
    pose_csv_path_ = output_dir_ + "/wind_dynamic_orbit_pose_" + stamp_ + ".csv";
    depth_csv_path_ = output_dir_ + "/wind_dynamic_orbit_depth_" + stamp_ + ".csv";
    summary_path_ = output_dir_ + "/wind_dynamic_orbit_audit_" + stamp_ + ".txt";

    pose_csv_.open(pose_csv_path_);
    depth_csv_.open(depth_csv_path_);
    pose_csv_ << "sample_index,t_sec,x,y,z,xy_valid,z_valid,center_xy_radius_m,"
      "radius_error_m,conservative_clearance_m\n";
    depth_csv_ << "frame_index,stamp_sec,stamp_nanosec,total_pixels,finite_positive_pixels,"
      "useful_depth_pixels,far_or_saturated_pixels,invalid_pixels,valid_ratio,useful_ratio,"
      "min_depth_m,max_depth_m,mean_depth_m,mean_useful_depth_m\n";

    local_position_sub_ = create_subscription<px4_msgs::msg::VehicleLocalPosition>(
      "/fmu/out/vehicle_local_position",
      rclcpp::SensorDataQoS(),
      [this](px4_msgs::msg::VehicleLocalPosition::SharedPtr msg) {
        latest_local_position_ = msg;
      });
    depth_sub_ = create_subscription<sensor_msgs::msg::Image>(
      "/camera/depth/image_raw",
      rclcpp::SensorDataQoS(),
      [this](sensor_msgs::msg::Image::ConstSharedPtr msg) {
        process_depth(*msg);
      });
    timer_ = create_wall_timer(
      std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::duration<double>(1.0 / sample_rate_hz_)),
      [this]() { sample_pose(); });
    start_time_ = now();
  }

  bool done() const { return done_; }
  int result_code() const { return result_code_; }

private:
  void sample_pose()
  {
    if (done_) {
      return;
    }
    const double elapsed = (now() - start_time_).seconds();
    if (latest_local_position_) {
      const auto & msg = *latest_local_position_;
      PoseSample sample;
      sample.t_sec = elapsed;
      sample.x = msg.x;
      sample.y = msg.y;
      sample.z = msg.z;
      sample.xy_valid = msg.xy_valid;
      sample.z_valid = msg.z_valid;
      sample.center_xy_radius = std::hypot(sample.x - center_x_, sample.y - center_y_);
      sample.radius_error = std::abs(sample.center_xy_radius - expected_radius_m_);
      sample.conservative_clearance = sample.center_xy_radius - conservative_mesh_radius_m_;
      pose_samples_.push_back(sample);
      pose_csv_ << (pose_samples_.size() - 1) << ','
        << sample.t_sec << ','
        << sample.x << ','
        << sample.y << ','
        << sample.z << ','
        << bool_text(sample.xy_valid) << ','
        << bool_text(sample.z_valid) << ','
        << sample.center_xy_radius << ','
        << sample.radius_error << ','
        << sample.conservative_clearance << '\n';
    }
    if (elapsed >= duration_sec_) {
      write_summary();
    }
  }

  void process_depth(const sensor_msgs::msg::Image & msg)
  {
    if (done_) {
      return;
    }
    DepthSample sample;
    sample.frame_index = static_cast<int>(depth_samples_.size());
    sample.sec = msg.header.stamp.sec;
    sample.nanosec = msg.header.stamp.nanosec;
    sample.total_pixels = static_cast<std::size_t>(msg.width) * static_cast<std::size_t>(msg.height);
    try {
      if (msg.encoding == sensor_msgs::image_encodings::TYPE_32FC1) {
        scan_depth<float>(msg, 1.0, saturation_depth_m_, sample);
      } else if (msg.encoding == sensor_msgs::image_encodings::TYPE_16UC1) {
        scan_depth<std::uint16_t>(msg, 0.001, saturation_depth_m_, sample);
      } else {
        return;
      }
    } catch (const std::exception &) {
      return;
    }
    depth_samples_.push_back(sample);
    depth_csv_ << sample.frame_index << ','
      << sample.sec << ','
      << sample.nanosec << ','
      << sample.total_pixels << ','
      << sample.finite_positive_pixels << ','
      << sample.useful_depth_pixels << ','
      << sample.far_or_saturated_pixels << ','
      << sample.invalid_pixels << ','
      << sample.valid_ratio << ','
      << sample.useful_ratio << ','
      << sample.min_depth_m << ','
      << sample.max_depth_m << ','
      << sample.mean_depth_m << ','
      << sample.mean_useful_depth_m << '\n';
  }

  void write_summary()
  {
    if (done_) {
      return;
    }
    pose_csv_.flush();
    depth_csv_.flush();

    const auto min_clearance_it = std::min_element(
      pose_samples_.begin(), pose_samples_.end(),
      [](const PoseSample & a, const PoseSample & b) {
        return a.conservative_clearance < b.conservative_clearance;
      });
    const auto max_radius_error_it = std::max_element(
      pose_samples_.begin(), pose_samples_.end(),
      [](const PoseSample & a, const PoseSample & b) {
        return a.radius_error < b.radius_error;
      });
    const double min_clearance = min_clearance_it == pose_samples_.end() ?
      std::numeric_limits<double>::quiet_NaN() : min_clearance_it->conservative_clearance;
    const double max_radius_error = max_radius_error_it == pose_samples_.end() ?
      std::numeric_limits<double>::quiet_NaN() : max_radius_error_it->radius_error;
    const double mean_radius_error = pose_samples_.empty() ? 0.0 :
      std::accumulate(
        pose_samples_.begin(), pose_samples_.end(), 0.0,
        [](double acc, const PoseSample & sample) { return acc + sample.radius_error; }) /
      static_cast<double>(pose_samples_.size());
    const int valid_pose_count = static_cast<int>(std::count_if(
      pose_samples_.begin(), pose_samples_.end(),
      [](const PoseSample & sample) { return sample.xy_valid && sample.z_valid; }));

    const double mean_useful = depth_samples_.empty() ? 0.0 :
      std::accumulate(
        depth_samples_.begin(), depth_samples_.end(), 0.0,
        [](double acc, const DepthSample & sample) { return acc + sample.useful_ratio; }) /
      static_cast<double>(depth_samples_.size());
    const auto max_useful_it = std::max_element(
      depth_samples_.begin(), depth_samples_.end(),
      [](const DepthSample & a, const DepthSample & b) { return a.useful_ratio < b.useful_ratio; });
    const double max_useful = max_useful_it == depth_samples_.end() ? 0.0 : max_useful_it->useful_ratio;

    const bool pose_ok =
      !pose_samples_.empty() &&
      valid_pose_count == static_cast<int>(pose_samples_.size()) &&
      std::isfinite(min_clearance) &&
      min_clearance >= min_clearance_m_ &&
      std::isfinite(max_radius_error) &&
      max_radius_error <= max_radius_error_m_;
    const bool depth_ok =
      !depth_samples_.empty() &&
      mean_useful >= min_mean_useful_ratio_ &&
      max_useful >= min_any_useful_ratio_;
    const bool accepted = pose_ok && depth_ok;

    std::ofstream out(summary_path_);
    out << std::setprecision(12);
    out << "scope=wind_dynamic_orbit_audit\n";
    out << "decision=" << (accepted ? "accepted_wind_dynamic_orbit_audit" : "rejected_wind_dynamic_orbit_audit") << "\n";
    out << "reason=" << (accepted ? "dynamic_pose_and_depth_metrics_passed" : "dynamic_pose_or_depth_metrics_failed") << "\n";
    out << "starts_ros=true\n";
    out << "starts_px4=false\n";
    out << "starts_gazebo=false\n";
    out << "starts_rviz=false\n";
    out << "starts_offboard=false\n";
    out << "arms=false\n";
    out << "publishes_fmu_in=false\n";
    out << "subscribes_vehicle_local_position=true\n";
    out << "subscribes_depth_image=true\n";
    out << "duration_sec=" << duration_sec_ << "\n";
    out << "sample_rate_hz=" << sample_rate_hz_ << "\n";
    out << "pose_samples=" << pose_samples_.size() << "\n";
    out << "valid_pose_samples=" << valid_pose_count << "\n";
    out << "depth_frames=" << depth_samples_.size() << "\n";
    out << "center_x=" << center_x_ << "\n";
    out << "center_y=" << center_y_ << "\n";
    out << "expected_radius_m=" << expected_radius_m_ << "\n";
    out << "conservative_mesh_radius_m=" << conservative_mesh_radius_m_ << "\n";
    out << "min_conservative_clearance_m=" << min_clearance << "\n";
    out << "mean_radius_error_m=" << mean_radius_error << "\n";
    out << "max_radius_error_m_observed=" << max_radius_error << "\n";
    out << "min_clearance_m=" << min_clearance_m_ << "\n";
    out << "max_radius_error_m=" << max_radius_error_m_ << "\n";
    out << "mean_useful_ratio=" << mean_useful << "\n";
    out << "max_useful_ratio=" << max_useful << "\n";
    out << "min_mean_useful_ratio=" << min_mean_useful_ratio_ << "\n";
    out << "min_any_useful_ratio=" << min_any_useful_ratio_ << "\n";
    out << "pose_ok=" << bool_text(pose_ok) << "\n";
    out << "depth_ok=" << bool_text(depth_ok) << "\n";
    out << "claims_final_coverage=false\n";
    out << "pose_csv=" << pose_csv_path_ << "\n";
    out << "depth_csv=" << depth_csv_path_ << "\n";

    done_ = true;
    result_code_ = accepted ? 0 : 1;
  }

  std::string output_dir_;
  std::string stamp_;
  std::string pose_csv_path_;
  std::string depth_csv_path_;
  std::string summary_path_;
  std::ofstream pose_csv_;
  std::ofstream depth_csv_;
  double duration_sec_{45.0};
  double sample_rate_hz_{10.0};
  double center_x_{-25.0};
  double center_y_{-25.0};
  double expected_radius_m_{20.0};
  double conservative_mesh_radius_m_{11.880407};
  double min_clearance_m_{1.0};
  double max_radius_error_m_{8.0};
  double min_mean_useful_ratio_{0.001};
  double min_any_useful_ratio_{0.01};
  double saturation_depth_m_{65.0};
  bool done_{false};
  int result_code_{1};
  rclcpp::Time start_time_{0, 0, RCL_ROS_TIME};
  px4_msgs::msg::VehicleLocalPosition::SharedPtr latest_local_position_;
  std::vector<PoseSample> pose_samples_;
  std::vector<DepthSample> depth_samples_;
  rclcpp::Subscription<px4_msgs::msg::VehicleLocalPosition>::SharedPtr local_position_sub_;
  rclcpp::Subscription<sensor_msgs::msg::Image>::SharedPtr depth_sub_;
  rclcpp::TimerBase::SharedPtr timer_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  int result = 1;
  try {
    auto node = std::make_shared<WindDynamicOrbitAudit>();
    rclcpp::WallRate rate(100.0);
    while (rclcpp::ok() && !node->done()) {
      rclcpp::spin_some(node);
      rate.sleep();
    }
    result = node->result_code();
  } catch (const std::exception & e) {
    std::cerr << "wind_dynamic_orbit_audit error: " << e.what() << "\n";
  }
  rclcpp::shutdown();
  return result;
}
