#include <algorithm>
#include <array>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <memory>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include <Eigen/Core>
#include <Eigen/Geometry>
#include <nav_msgs/msg/odometry.hpp>
#include <pcl/ModelCoefficients.h>
#include <pcl/common/transforms.h>
#include <pcl/filters/crop_box.h>
#include <pcl/filters/extract_indices.h>
#include <pcl/filters/filter.h>
#include <pcl/io/pcd_io.h>
#include <pcl/point_cloud.h>
#include <pcl/point_types.h>
#include <pcl/segmentation/sac_segmentation.h>
#include <pcl_conversions/pcl_conversions.h>
#include <rclcpp/rclcpp.hpp>
#include <sensor_msgs/msg/point_cloud2.hpp>

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

using PointT = pcl::PointXYZ;
using Cloud = pcl::PointCloud<PointT>;
using CloudPtr = Cloud::Ptr;

struct Bbox
{
  std::array<double, 3> min{
    std::numeric_limits<double>::infinity(),
    std::numeric_limits<double>::infinity(),
    std::numeric_limits<double>::infinity()};
  std::array<double, 3> max{
    -std::numeric_limits<double>::infinity(),
    -std::numeric_limits<double>::infinity(),
    -std::numeric_limits<double>::infinity()};
  bool valid{false};
};

struct LineCandidate
{
  int frame_index{0};
  int line_index{0};
  std::size_t inliers{0};
  double inlier_ratio{0.0};
  std::array<double, 3> point{0.0, 0.0, 0.0};
  std::array<double, 3> direction{0.0, 0.0, 0.0};
  Bbox bbox;
};

struct FrameStats
{
  int frame_index{0};
  std::size_t raw_points{0};
  std::size_t finite_points{0};
  std::size_t sensor_roi_points{0};
  std::size_t world_roi_points{0};
  std::size_t lines{0};
};

Bbox compute_bbox(const Cloud & cloud)
{
  Bbox bbox;
  for (const auto & point : cloud.points) {
    bbox.min[0] = std::min<double>(bbox.min[0], point.x);
    bbox.min[1] = std::min<double>(bbox.min[1], point.y);
    bbox.min[2] = std::min<double>(bbox.min[2], point.z);
    bbox.max[0] = std::max<double>(bbox.max[0], point.x);
    bbox.max[1] = std::max<double>(bbox.max[1], point.y);
    bbox.max[2] = std::max<double>(bbox.max[2], point.z);
    bbox.valid = true;
  }
  return bbox;
}

std::array<double, 3> normalized_direction(const pcl::ModelCoefficients & coefficients)
{
  std::array<double, 3> direction{0.0, 0.0, 0.0};
  if (coefficients.values.size() < 6) {
    return direction;
  }
  const double x = coefficients.values[3];
  const double y = coefficients.values[4];
  const double z = coefficients.values[5];
  const double norm = std::sqrt(x * x + y * y + z * z);
  if (norm <= std::numeric_limits<double>::epsilon()) {
    return direction;
  }
  direction = {x / norm, y / norm, z / norm};
  return direction;
}
}  // namespace

class PointCloudPoseMultilineRansacWorldSmoke : public rclcpp::Node
{
public:
  PointCloudPoseMultilineRansacWorldSmoke()
  : Node("pointcloud_pose_multiline_ransac_world_smoke")
  {
    topic_ = declare_parameter<std::string>("topic", "/camera/points");
    pose_topic_ = declare_parameter<std::string>("pose_topic", "/zcw/depth_camera/pose");
    output_dir_ = declare_parameter<std::string>("output_dir", "data/results");
    output_prefix_ = declare_parameter<std::string>("output_prefix", "pointcloud_multiline_ransac_world");
    frames_ = declare_parameter<int>("frames", 3);
    max_lines_ = declare_parameter<int>("max_lines", 6);
    min_lines_per_frame_ = declare_parameter<int>("min_lines_per_frame", 2);
    distance_threshold_ = declare_parameter<double>("distance_threshold_m", 0.35);
    min_line_inliers_ = declare_parameter<int>("min_line_inliers", 500);
    max_iterations_ = declare_parameter<int>("max_iterations", 250);

    crop_min_x_ = declare_parameter<double>("crop_min_x", -80.0);
    crop_max_x_ = declare_parameter<double>("crop_max_x", 80.0);
    crop_min_y_ = declare_parameter<double>("crop_min_y", -80.0);
    crop_max_y_ = declare_parameter<double>("crop_max_y", 80.0);
    crop_min_z_ = declare_parameter<double>("crop_min_z", 0.0);
    crop_max_z_ = declare_parameter<double>("crop_max_z", 80.0);

    world_crop_min_x_ = declare_parameter<double>("world_crop_min_x", -120.0);
    world_crop_max_x_ = declare_parameter<double>("world_crop_max_x", 40.0);
    world_crop_min_y_ = declare_parameter<double>("world_crop_min_y", 5.0);
    world_crop_max_y_ = declare_parameter<double>("world_crop_max_y", 30.0);
    world_crop_min_z_ = declare_parameter<double>("world_crop_min_z", 0.0);
    world_crop_max_z_ = declare_parameter<double>("world_crop_max_z", 65.0);

    apply_sensor_pose_in_link_ = declare_parameter<bool>("apply_sensor_pose_in_link", true);
    sensor_roll_rad_ = declare_parameter<double>("sensor_roll_rad", -1.57079632679);
    sensor_pitch_rad_ = declare_parameter<double>("sensor_pitch_rad", 0.0);
    sensor_yaw_rad_ = declare_parameter<double>("sensor_yaw_rad", -1.57079632679);

    if (frames_ <= 0) {
      frames_ = 1;
    }
    if (max_lines_ <= 0) {
      max_lines_ = 1;
    }
    if (min_lines_per_frame_ <= 0) {
      min_lines_per_frame_ = 1;
    }
    std::filesystem::create_directories(output_dir_);

    pose_subscription_ = create_subscription<nav_msgs::msg::Odometry>(
      pose_topic_,
      10,
      [this](nav_msgs::msg::Odometry::ConstSharedPtr msg) {
        latest_pose_ = *msg;
        pose_received_ = true;
      });

    cloud_subscription_ = create_subscription<sensor_msgs::msg::PointCloud2>(
      topic_,
      rclcpp::SensorDataQoS(),
      [this](sensor_msgs::msg::PointCloud2::ConstSharedPtr msg) {
        process(msg);
      });

    RCLCPP_INFO(get_logger(), "Waiting for pose topic %s and %d PointCloud2 frames on %s",
      pose_topic_.c_str(), frames_, topic_.c_str());
  }

  bool done() const { return done_; }
  int result_code() const { return result_code_; }

private:
  CloudPtr crop_sensor(const CloudPtr & input) const
  {
    return crop(input, crop_min_x_, crop_max_x_, crop_min_y_, crop_max_y_, crop_min_z_, crop_max_z_);
  }

  CloudPtr crop_world(const CloudPtr & input) const
  {
    return crop(
      input,
      world_crop_min_x_, world_crop_max_x_,
      world_crop_min_y_, world_crop_max_y_,
      world_crop_min_z_, world_crop_max_z_);
  }

  CloudPtr crop(
    const CloudPtr & input,
    double min_x, double max_x,
    double min_y, double max_y,
    double min_z, double max_z) const
  {
    auto cropped = std::make_shared<Cloud>();
    pcl::CropBox<PointT> crop_box;
    crop_box.setMin(Eigen::Vector4f(min_x, min_y, min_z, 1.0f));
    crop_box.setMax(Eigen::Vector4f(max_x, max_y, max_z, 1.0f));
    crop_box.setInputCloud(input);
    crop_box.filter(*cropped);
    return cropped;
  }

  Eigen::Affine3f world_transform_from_latest_pose() const
  {
    const auto & pose = latest_pose_.pose.pose;
    Eigen::Affine3f transform = Eigen::Affine3f::Identity();
    transform.translation() << static_cast<float>(pose.position.x),
      static_cast<float>(pose.position.y),
      static_cast<float>(pose.position.z);

    Eigen::Quaternionf q(
      static_cast<float>(pose.orientation.w),
      static_cast<float>(pose.orientation.x),
      static_cast<float>(pose.orientation.y),
      static_cast<float>(pose.orientation.z));
    if (q.norm() > 0.0f) {
      q.normalize();
      transform.linear() = q.toRotationMatrix();
    }

    if (apply_sensor_pose_in_link_) {
      Eigen::Affine3f sensor_pose = Eigen::Affine3f::Identity();
      const Eigen::Matrix3f sensor_rotation =
        (Eigen::AngleAxisf(static_cast<float>(sensor_yaw_rad_), Eigen::Vector3f::UnitZ()) *
        Eigen::AngleAxisf(static_cast<float>(sensor_pitch_rad_), Eigen::Vector3f::UnitY()) *
        Eigen::AngleAxisf(static_cast<float>(sensor_roll_rad_), Eigen::Vector3f::UnitX())).toRotationMatrix();
      sensor_pose.linear() = sensor_rotation;
      transform = transform * sensor_pose;
    }
    return transform;
  }

  std::vector<LineCandidate> extract_lines(const CloudPtr & world_roi, int frame_index) const
  {
    std::vector<LineCandidate> candidates;
    auto remaining = std::make_shared<Cloud>(*world_roi);
    const std::size_t initial_points = remaining->size();

    for (int line_index = 0; line_index < max_lines_; ++line_index) {
      if (remaining->size() < static_cast<std::size_t>(min_line_inliers_)) {
        break;
      }

      pcl::SACSegmentation<PointT> segmentation;
      segmentation.setOptimizeCoefficients(true);
      segmentation.setModelType(pcl::SACMODEL_LINE);
      segmentation.setMethodType(pcl::SAC_RANSAC);
      segmentation.setMaxIterations(max_iterations_);
      segmentation.setDistanceThreshold(distance_threshold_);
      segmentation.setInputCloud(remaining);

      pcl::PointIndices::Ptr inliers(new pcl::PointIndices);
      pcl::ModelCoefficients::Ptr coefficients(new pcl::ModelCoefficients);
      segmentation.segment(*inliers, *coefficients);
      if (inliers->indices.size() < static_cast<std::size_t>(min_line_inliers_)) {
        break;
      }

      pcl::ExtractIndices<PointT> extract;
      extract.setInputCloud(remaining);
      extract.setIndices(inliers);

      auto inlier_cloud = std::make_shared<Cloud>();
      extract.setNegative(false);
      extract.filter(*inlier_cloud);

      const auto frame = std::to_string(frame_index);
      const auto line = std::to_string(line_index);
      pcl::io::savePCDFileBinary(
        output_dir_ + "/frame_" + frame + "_line_" + line + "_inliers_world.pcd",
        *inlier_cloud);

      LineCandidate candidate;
      candidate.frame_index = frame_index;
      candidate.line_index = line_index;
      candidate.inliers = inliers->indices.size();
      candidate.inlier_ratio = initial_points == 0 ? 0.0 :
        static_cast<double>(candidate.inliers) / static_cast<double>(initial_points);
      candidate.bbox = compute_bbox(*inlier_cloud);
      if (coefficients->values.size() >= 6) {
        candidate.point = {
          coefficients->values[0],
          coefficients->values[1],
          coefficients->values[2]};
      }
      candidate.direction = normalized_direction(*coefficients);
      candidates.push_back(candidate);

      auto remaining_next = std::make_shared<Cloud>();
      extract.setNegative(true);
      extract.filter(*remaining_next);
      remaining = remaining_next;
    }

    return candidates;
  }

  void process(const sensor_msgs::msg::PointCloud2::ConstSharedPtr & msg)
  {
    if (done_) {
      return;
    }
    if (!pose_received_) {
      RCLCPP_WARN_THROTTLE(get_logger(), *get_clock(), 2000,
        "Waiting for pose before processing point clouds.");
      return;
    }

    auto cloud = std::make_shared<Cloud>();
    pcl::fromROSMsg(*msg, *cloud);

    FrameStats stats;
    stats.frame_index = static_cast<int>(frames_seen_);
    stats.raw_points = cloud->size();

    std::vector<int> finite_indices;
    pcl::removeNaNFromPointCloud(*cloud, *cloud, finite_indices);
    stats.finite_points = cloud->size();

    const auto sensor_roi = crop_sensor(cloud);
    stats.sensor_roi_points = sensor_roi->size();

    const auto transform = world_transform_from_latest_pose();
    auto sensor_roi_world = std::make_shared<Cloud>();
    pcl::transformPointCloud(*sensor_roi, *sensor_roi_world, transform);
    const auto world_roi = crop_world(sensor_roi_world);
    stats.world_roi_points = world_roi->size();

    const auto frame = std::to_string(stats.frame_index);
    pcl::io::savePCDFileBinary(output_dir_ + "/frame_" + frame + "_roi_world.pcd", *world_roi);

    auto frame_candidates = extract_lines(world_roi, stats.frame_index);
    stats.lines = frame_candidates.size();
    candidates_.insert(candidates_.end(), frame_candidates.begin(), frame_candidates.end());
    frame_stats_.push_back(stats);

    RCLCPP_INFO(get_logger(),
      "frame=%d raw=%zu finite=%zu sensor_roi=%zu world_roi=%zu lines=%zu",
      stats.frame_index,
      stats.raw_points,
      stats.finite_points,
      stats.sensor_roi_points,
      stats.world_roi_points,
      stats.lines);

    ++frames_seen_;
    if (frames_seen_ >= static_cast<std::size_t>(frames_)) {
      write_summary();
      done_ = true;
    }
  }

  void write_summary()
  {
    const auto stamp = stamp_string();
    const auto summary_txt = output_dir_ + "/" + output_prefix_ + "_" + stamp + ".txt";
    const auto frame_csv_path = output_dir_ + "/" + output_prefix_ + "_frames_" + stamp + ".csv";
    const auto line_csv_path = output_dir_ + "/" + output_prefix_ + "_lines_" + stamp + ".csv";

    std::ofstream frame_csv(frame_csv_path);
    frame_csv << "frame,raw_points,finite_points,sensor_roi_points,world_roi_points,lines\n";

    std::size_t min_lines = std::numeric_limits<std::size_t>::max();
    std::size_t max_lines = 0;
    std::size_t failed_frames = 0;
    std::size_t total_lines = 0;
    std::size_t total_world_roi_points = 0;

    for (const auto & stats : frame_stats_) {
      min_lines = std::min(min_lines, stats.lines);
      max_lines = std::max(max_lines, stats.lines);
      total_lines += stats.lines;
      total_world_roi_points += stats.world_roi_points;
      if (stats.lines < static_cast<std::size_t>(min_lines_per_frame_)) {
        ++failed_frames;
      }
      frame_csv << stats.frame_index << ","
                << stats.raw_points << ","
                << stats.finite_points << ","
                << stats.sensor_roi_points << ","
                << stats.world_roi_points << ","
                << stats.lines << "\n";
    }
    if (frame_stats_.empty()) {
      min_lines = 0;
    }

    std::ofstream line_csv(line_csv_path);
    line_csv << "frame,line,inliers,inlier_ratio,point_x,point_y,point_z,"
             << "dir_x,dir_y,dir_z,min_x,min_y,min_z,max_x,max_y,max_z\n";
    for (const auto & candidate : candidates_) {
      line_csv << candidate.frame_index << ","
               << candidate.line_index << ","
               << candidate.inliers << ","
               << candidate.inlier_ratio << ","
               << candidate.point[0] << ","
               << candidate.point[1] << ","
               << candidate.point[2] << ","
               << candidate.direction[0] << ","
               << candidate.direction[1] << ","
               << candidate.direction[2] << ",";
      if (candidate.bbox.valid) {
        line_csv << candidate.bbox.min[0] << ","
                 << candidate.bbox.min[1] << ","
                 << candidate.bbox.min[2] << ","
                 << candidate.bbox.max[0] << ","
                 << candidate.bbox.max[1] << ","
                 << candidate.bbox.max[2];
      } else {
        line_csv << ",,,,,";
      }
      line_csv << "\n";
    }

    const double frame_count = static_cast<double>(frame_stats_.size());
    const double mean_lines = frame_count == 0.0 ? 0.0 :
      static_cast<double>(total_lines) / frame_count;
    const double mean_world_roi_points = frame_count == 0.0 ? 0.0 :
      static_cast<double>(total_world_roi_points) / frame_count;

    std::ofstream summary(summary_txt);
    summary << "topic: " << topic_ << "\n";
    summary << "pose_topic: " << pose_topic_ << "\n";
    summary << "output_prefix: " << output_prefix_ << "\n";
    summary << "frames_requested: " << frames_ << "\n";
    summary << "frames_processed: " << frame_stats_.size() << "\n";
    summary << "max_lines: " << max_lines_ << "\n";
    summary << "min_lines_per_frame: " << min_lines_per_frame_ << "\n";
    summary << "distance_threshold_m: " << distance_threshold_ << "\n";
    summary << "min_line_inliers: " << min_line_inliers_ << "\n";
    summary << "apply_sensor_pose_in_link: " << (apply_sensor_pose_in_link_ ? "true" : "false") << "\n";
    summary << "sensor_rpy_rad: " << sensor_roll_rad_ << " " << sensor_pitch_rad_ << " " << sensor_yaw_rad_ << "\n";
    summary << "sensor_crop_min: " << crop_min_x_ << " " << crop_min_y_ << " " << crop_min_z_ << "\n";
    summary << "sensor_crop_max: " << crop_max_x_ << " " << crop_max_y_ << " " << crop_max_z_ << "\n";
    summary << "world_crop_min: " << world_crop_min_x_ << " " << world_crop_min_y_ << " " << world_crop_min_z_ << "\n";
    summary << "world_crop_max: " << world_crop_max_x_ << " " << world_crop_max_y_ << " " << world_crop_max_z_ << "\n";
    summary << "min_lines_found: " << min_lines << "\n";
    summary << "max_lines_found: " << max_lines << "\n";
    summary << "mean_lines_found: " << mean_lines << "\n";
    summary << "mean_world_roi_points: " << mean_world_roi_points << "\n";
    summary << "failed_frames: " << failed_frames << "\n";
    summary << "total_candidates: " << candidates_.size() << "\n";
    summary << "frame_csv: " << frame_csv_path << "\n";
    summary << "line_csv: " << line_csv_path << "\n";

    result_code_ = failed_frames == 0 && frame_stats_.size() == static_cast<std::size_t>(frames_) ? 0 : 2;
    RCLCPP_INFO(get_logger(), "summary: %s", summary_txt.c_str());
    RCLCPP_INFO(get_logger(), "frame csv: %s", frame_csv_path.c_str());
    RCLCPP_INFO(get_logger(), "line csv: %s", line_csv_path.c_str());
  }

  std::string topic_;
  std::string pose_topic_;
  std::string output_dir_;
  std::string output_prefix_;
  int frames_{3};
  int max_lines_{6};
  int min_lines_per_frame_{2};
  double distance_threshold_{0.35};
  int min_line_inliers_{500};
  int max_iterations_{250};
  double crop_min_x_{-80.0};
  double crop_max_x_{80.0};
  double crop_min_y_{-80.0};
  double crop_max_y_{80.0};
  double crop_min_z_{0.0};
  double crop_max_z_{80.0};
  double world_crop_min_x_{-120.0};
  double world_crop_max_x_{40.0};
  double world_crop_min_y_{5.0};
  double world_crop_max_y_{30.0};
  double world_crop_min_z_{0.0};
  double world_crop_max_z_{65.0};
  bool apply_sensor_pose_in_link_{true};
  double sensor_roll_rad_{-1.57079632679};
  double sensor_pitch_rad_{0.0};
  double sensor_yaw_rad_{-1.57079632679};
  bool pose_received_{false};
  nav_msgs::msg::Odometry latest_pose_;
  std::size_t frames_seen_{0};
  bool done_{false};
  int result_code_{1};
  std::vector<FrameStats> frame_stats_;
  std::vector<LineCandidate> candidates_;
  rclcpp::Subscription<nav_msgs::msg::Odometry>::SharedPtr pose_subscription_;
  rclcpp::Subscription<sensor_msgs::msg::PointCloud2>::SharedPtr cloud_subscription_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  auto node = std::make_shared<PointCloudPoseMultilineRansacWorldSmoke>();

  const auto start = std::chrono::steady_clock::now();
  const auto timeout = std::chrono::seconds(75);
  while (rclcpp::ok() && !node->done()) {
    rclcpp::spin_some(node);
    if (std::chrono::steady_clock::now() - start > timeout) {
      RCLCPP_ERROR(node->get_logger(), "Timed out waiting for posed point clouds.");
      rclcpp::shutdown();
      return 1;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  }

  const int result_code = node->result_code();
  rclcpp::shutdown();
  return result_code;
}
