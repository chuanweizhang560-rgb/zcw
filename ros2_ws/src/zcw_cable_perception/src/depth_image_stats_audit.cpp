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
#include <string>
#include <vector>

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

struct FrameStats
{
  int frame_index{};
  std::size_t total_pixels{};
  std::size_t finite_positive_pixels{};
  std::size_t useful_depth_pixels{};
  std::size_t far_or_saturated_pixels{};
  std::size_t finite_zero_or_negative_pixels{};
  std::size_t nan_or_inf_pixels{};
  double valid_ratio{};
  double useful_ratio{};
  double min_depth_m{};
  double max_depth_m{};
  double mean_depth_m{};
  double mean_useful_depth_m{};
};

template<typename T>
void scan_depth_buffer(
  const sensor_msgs::msg::Image & msg,
  const double scale_to_m,
  const double saturation_depth_m,
  FrameStats & stats)
{
  const auto bytes_per_pixel = sizeof(T);
  if (msg.step < msg.width * bytes_per_pixel) {
    throw std::runtime_error("Image step is smaller than width * pixel size");
  }

  double sum = 0.0;
  double useful_sum = 0.0;
  stats.min_depth_m = std::numeric_limits<double>::infinity();
  stats.max_depth_m = -std::numeric_limits<double>::infinity();

  for (std::uint32_t row = 0; row < msg.height; ++row) {
    const auto * row_data = msg.data.data() + row * msg.step;
    for (std::uint32_t col = 0; col < msg.width; ++col) {
      T value{};
      std::memcpy(&value, row_data + col * bytes_per_pixel, bytes_per_pixel);
      const double depth_m = static_cast<double>(value) * scale_to_m;
      if (!std::isfinite(depth_m)) {
        ++stats.nan_or_inf_pixels;
      } else if (depth_m > 0.0) {
        ++stats.finite_positive_pixels;
        sum += depth_m;
        stats.min_depth_m = std::min(stats.min_depth_m, depth_m);
        stats.max_depth_m = std::max(stats.max_depth_m, depth_m);
        if (depth_m < saturation_depth_m) {
          ++stats.useful_depth_pixels;
          useful_sum += depth_m;
        } else {
          ++stats.far_or_saturated_pixels;
        }
      } else {
        ++stats.finite_zero_or_negative_pixels;
      }
    }
  }

  if (stats.finite_positive_pixels > 0) {
    stats.mean_depth_m = sum / static_cast<double>(stats.finite_positive_pixels);
  } else {
    stats.min_depth_m = 0.0;
    stats.max_depth_m = 0.0;
    stats.mean_depth_m = 0.0;
  }
  stats.valid_ratio = stats.total_pixels == 0 ? 0.0 :
    static_cast<double>(stats.finite_positive_pixels) /
    static_cast<double>(stats.total_pixels);
  stats.useful_ratio = stats.total_pixels == 0 ? 0.0 :
    static_cast<double>(stats.useful_depth_pixels) /
    static_cast<double>(stats.total_pixels);
  stats.mean_useful_depth_m = stats.useful_depth_pixels == 0 ? 0.0 :
    useful_sum / static_cast<double>(stats.useful_depth_pixels);
}
}  // namespace

class DepthImageStatsAudit : public rclcpp::Node
{
public:
  DepthImageStatsAudit()
  : Node("depth_image_stats_audit")
  {
    topic_ = declare_parameter<std::string>("topic", "/camera/depth/image_raw");
    output_dir_ = declare_parameter<std::string>("output_dir", "data/results/depth_image_stats");
    frames_target_ = declare_parameter<int>("frames", 30);
    saturation_depth_m_ = declare_parameter<double>("saturation_depth_m", 65.0);
    min_mean_useful_ratio_ = declare_parameter<double>("min_mean_useful_ratio", 0.01);
    min_any_useful_ratio_ = declare_parameter<double>("min_any_useful_ratio", 0.05);

    if (frames_target_ <= 0) {
      throw std::runtime_error("frames must be positive");
    }

    std::filesystem::create_directories(output_dir_);
    const auto stamp = stamp_string();
    csv_path_ = output_dir_ + "/depth_image_stats_frames_" + stamp + ".csv";
    summary_path_ = output_dir_ + "/depth_image_stats_" + stamp + ".txt";

    csv_.open(csv_path_);
    csv_ << "frame_index,stamp_sec,stamp_nanosec,encoding,width,height,total_pixels,"
      "finite_positive_pixels,useful_depth_pixels,far_or_saturated_pixels,"
      "finite_zero_or_negative_pixels,nan_or_inf_pixels,valid_ratio,useful_ratio,"
      "min_depth_m,max_depth_m,mean_depth_m,mean_useful_depth_m\n";

    subscription_ = create_subscription<sensor_msgs::msg::Image>(
      topic_,
      rclcpp::SensorDataQoS(),
      [this](sensor_msgs::msg::Image::ConstSharedPtr msg) {
        process(*msg);
      });

    RCLCPP_INFO(get_logger(), "Waiting for depth image topic: %s", topic_.c_str());
  }

  bool done() const { return done_; }
  int result_code() const { return result_code_; }

private:
  void process(const sensor_msgs::msg::Image & msg)
  {
    if (done_) {
      return;
    }

    FrameStats stats;
    stats.frame_index = static_cast<int>(frames_.size());
    stats.total_pixels = static_cast<std::size_t>(msg.width) * static_cast<std::size_t>(msg.height);

    try {
      if (msg.encoding == sensor_msgs::image_encodings::TYPE_32FC1) {
        scan_depth_buffer<float>(msg, 1.0, saturation_depth_m_, stats);
      } else if (msg.encoding == sensor_msgs::image_encodings::TYPE_16UC1) {
        scan_depth_buffer<std::uint16_t>(msg, 0.001, saturation_depth_m_, stats);
      } else {
        throw std::runtime_error("Unsupported depth encoding: " + msg.encoding);
      }
    } catch (const std::exception & exc) {
      write_failure("unsupported_or_invalid_depth_image", exc.what());
      return;
    }

    csv_ << stats.frame_index << ','
      << msg.header.stamp.sec << ','
      << msg.header.stamp.nanosec << ','
      << msg.encoding << ','
      << msg.width << ','
      << msg.height << ','
      << stats.total_pixels << ','
      << stats.finite_positive_pixels << ','
      << stats.useful_depth_pixels << ','
      << stats.far_or_saturated_pixels << ','
      << stats.finite_zero_or_negative_pixels << ','
      << stats.nan_or_inf_pixels << ','
      << stats.valid_ratio << ','
      << stats.useful_ratio << ','
      << stats.min_depth_m << ','
      << stats.max_depth_m << ','
      << stats.mean_depth_m << ','
      << stats.mean_useful_depth_m << '\n';
    frames_.push_back(stats);

    if (static_cast<int>(frames_.size()) >= frames_target_) {
      write_success_or_failure();
    }
  }

  void write_failure(const std::string & reason, const std::string & detail)
  {
    std::ofstream out(summary_path_);
    out << "decision=rejected_depth_image_stats\n";
    out << "reason=" << reason << "\n";
    out << "detail=" << detail << "\n";
    out << "topic=" << topic_ << "\n";
    out << "frames_collected=" << frames_.size() << "\n";
    out << "csv=" << csv_path_ << "\n";
    done_ = true;
    result_code_ = 1;
  }

  void write_success_or_failure()
  {
    const double sum_valid_ratio = std::accumulate(
      frames_.begin(), frames_.end(), 0.0,
      [](double acc, const FrameStats & stats) {
        return acc + stats.valid_ratio;
      });
    const double mean_valid_ratio = frames_.empty() ? 0.0 :
      sum_valid_ratio / static_cast<double>(frames_.size());
    const double sum_useful_ratio = std::accumulate(
      frames_.begin(), frames_.end(), 0.0,
      [](double acc, const FrameStats & stats) {
        return acc + stats.useful_ratio;
      });
    const double mean_useful_ratio = frames_.empty() ? 0.0 :
      sum_useful_ratio / static_cast<double>(frames_.size());

    const auto best_it = std::max_element(
      frames_.begin(), frames_.end(),
      [](const FrameStats & lhs, const FrameStats & rhs) {
        return lhs.valid_ratio < rhs.valid_ratio;
      });
    const double max_valid_ratio = best_it == frames_.end() ? 0.0 : best_it->valid_ratio;
    const auto best_useful_it = std::max_element(
      frames_.begin(), frames_.end(),
      [](const FrameStats & lhs, const FrameStats & rhs) {
        return lhs.useful_ratio < rhs.useful_ratio;
      });
    const double max_useful_ratio = best_useful_it == frames_.end() ? 0.0 :
      best_useful_it->useful_ratio;

    const bool accepted =
      mean_useful_ratio >= min_mean_useful_ratio_ &&
      max_useful_ratio >= min_any_useful_ratio_;

    std::ofstream out(summary_path_);
    out << "decision=" << (accepted ? "accepted_depth_image_stats" : "rejected_depth_image_stats") << "\n";
    out << "reason=" << (accepted ? "depth_images_have_measurable_useful_returns" : "depth_images_have_too_few_useful_returns") << "\n";
    out << "topic=" << topic_ << "\n";
    out << "frames_target=" << frames_target_ << "\n";
    out << "frames_collected=" << frames_.size() << "\n";
    out << "mean_valid_ratio=" << mean_valid_ratio << "\n";
    out << "max_valid_ratio=" << max_valid_ratio << "\n";
    out << "mean_useful_ratio=" << mean_useful_ratio << "\n";
    out << "max_useful_ratio=" << max_useful_ratio << "\n";
    out << "saturation_depth_m=" << saturation_depth_m_ << "\n";
    out << "min_mean_useful_ratio=" << min_mean_useful_ratio_ << "\n";
    out << "min_any_useful_ratio=" << min_any_useful_ratio_ << "\n";
    out << "csv=" << csv_path_ << "\n";

    done_ = true;
    result_code_ = accepted ? 0 : 1;
  }

  std::string topic_;
  std::string output_dir_;
  std::string csv_path_;
  std::string summary_path_;
  int frames_target_{};
  double saturation_depth_m_{};
  double min_mean_useful_ratio_{};
  double min_any_useful_ratio_{};
  bool done_{false};
  int result_code_{1};
  std::ofstream csv_;
  std::vector<FrameStats> frames_;
  rclcpp::Subscription<sensor_msgs::msg::Image>::SharedPtr subscription_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  auto node = std::make_shared<DepthImageStatsAudit>();
  rclcpp::WallRate rate(50.0);
  while (rclcpp::ok() && !node->done()) {
    rclcpp::spin_some(node);
    rate.sleep();
  }
  const auto result = node->result_code();
  rclcpp::shutdown();
  return result;
}
