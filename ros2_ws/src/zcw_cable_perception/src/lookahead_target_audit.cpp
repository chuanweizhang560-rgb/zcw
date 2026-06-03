#include <algorithm>
#include <chrono>
#include <cmath>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace
{
struct Point
{
  std::string group_id;
  int index{0};
  double x{0.0};
  double y{0.0};
  double z{0.0};
  double tangent_x{0.0};
  double tangent_y{0.0};
  double tangent_z{0.0};
};

struct Args
{
  std::string input_csv;
  std::string output_dir{"data/results"};
  std::string output_prefix{"lookahead_target_audit"};
  double lookahead_m{20.0};
  double min_target_distance_m{15.0};
  double max_target_distance_m{25.0};
  int min_targets_per_group{2};
};

struct GroupAudit
{
  std::string group_id;
  int points{0};
  int targets{0};
  double min_distance{std::numeric_limits<double>::infinity()};
  double max_distance{0.0};
  double mean_distance{0.0};
  bool monotonic_target_index{true};
  bool accepted{false};
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

double to_double(const std::string & value) { return std::stod(value); }
int to_int(const std::string & value) { return std::stoi(value); }

std::vector<Point> read_points(const std::string & path)
{
  std::ifstream in(path);
  if (!in) {
    throw std::runtime_error("failed to open input csv: " + path);
  }

  std::vector<Point> points;
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
      throw std::runtime_error("unexpected csv column count in line: " + line);
    }
    Point p;
    p.group_id = cols[0];
    p.index = to_int(cols[1]);
    p.x = to_double(cols[2]);
    p.y = to_double(cols[3]);
    p.z = to_double(cols[4]);
    p.tangent_x = to_double(cols[10]);
    p.tangent_y = to_double(cols[11]);
    p.tangent_z = to_double(cols[12]);
    points.push_back(p);
  }
  return points;
}

double distance(const Point & a, const Point & b)
{
  const double dx = b.x - a.x;
  const double dy = b.y - a.y;
  const double dz = b.z - a.z;
  return std::sqrt(dx * dx + dy * dy + dz * dz);
}

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

void print_usage()
{
  std::cerr
    << "Usage: lookahead_target_audit --input <offset_path.csv> [options]\n"
    << "Options:\n"
    << "  --output-dir <dir>\n"
    << "  --output-prefix <name>\n"
    << "  --lookahead-m <meters>\n"
    << "  --min-target-distance-m <meters>\n"
    << "  --max-target-distance-m <meters>\n"
    << "  --min-targets-per-group <count>\n";
}

Args parse_args(int argc, char ** argv)
{
  Args args;
  for (int i = 1; i < argc; ++i) {
    const std::string key = argv[i];
    auto require_value = [&](const std::string & option) -> std::string {
      if (i + 1 >= argc) {
        throw std::runtime_error("missing value for " + option);
      }
      return argv[++i];
    };
    if (key == "--input") {
      args.input_csv = require_value(key);
    } else if (key == "--output-dir") {
      args.output_dir = require_value(key);
    } else if (key == "--output-prefix") {
      args.output_prefix = require_value(key);
    } else if (key == "--lookahead-m") {
      args.lookahead_m = to_double(require_value(key));
    } else if (key == "--min-target-distance-m") {
      args.min_target_distance_m = to_double(require_value(key));
    } else if (key == "--max-target-distance-m") {
      args.max_target_distance_m = to_double(require_value(key));
    } else if (key == "--min-targets-per-group") {
      args.min_targets_per_group = to_int(require_value(key));
    } else if (key == "--help" || key == "-h") {
      print_usage();
      std::exit(0);
    } else {
      throw std::runtime_error("unknown argument: " + key);
    }
  }
  if (args.input_csv.empty()) {
    throw std::runtime_error("--input is required");
  }
  if (args.lookahead_m <= 0.0) {
    throw std::runtime_error("--lookahead-m must be positive");
  }
  return args;
}
}  // namespace

int main(int argc, char ** argv)
{
  try {
    const Args args = parse_args(argc, argv);
    std::filesystem::create_directories(args.output_dir);

    std::map<std::string, std::vector<Point>> groups;
    for (const auto & point : read_points(args.input_csv)) {
      groups[point.group_id].push_back(point);
    }

    const auto stamp = stamp_string();
    const auto summary_path = args.output_dir + "/" + args.output_prefix + "_" + stamp + ".txt";
    const auto targets_path = args.output_dir + "/" + args.output_prefix + "_targets_" + stamp + ".csv";
    const auto groups_path = args.output_dir + "/" + args.output_prefix + "_groups_" + stamp + ".csv";

    std::ofstream targets_csv(targets_path);
    targets_csv << "group_id,current_index,current_x,current_y,current_z,target_index,target_x,target_y,target_z,"
                << "target_distance,tangent_x,tangent_y,tangent_z\n";

    std::vector<GroupAudit> audits;
    int accepted_groups = 0;
    int total_targets = 0;
    for (auto & item : groups) {
      auto & points = item.second;
      std::sort(points.begin(), points.end(), [](const Point & a, const Point & b) {
        return a.index < b.index;
      });

      GroupAudit audit;
      audit.group_id = item.first;
      audit.points = static_cast<int>(points.size());
      int previous_target_index = -1;
      double distance_sum = 0.0;

      for (std::size_t i = 0; i + 1 < points.size(); ++i) {
        std::size_t target = i + 1;
        while (target + 1 < points.size() && distance(points[i], points[target]) < args.lookahead_m) {
          ++target;
        }
        const double d = distance(points[i], points[target]);
        if (d < args.min_target_distance_m || d > args.max_target_distance_m) {
          continue;
        }
        if (previous_target_index > points[target].index) {
          audit.monotonic_target_index = false;
        }
        previous_target_index = points[target].index;
        audit.min_distance = std::min(audit.min_distance, d);
        audit.max_distance = std::max(audit.max_distance, d);
        distance_sum += d;
        ++audit.targets;
        ++total_targets;

        targets_csv << item.first << ","
                    << points[i].index << ","
                    << points[i].x << ","
                    << points[i].y << ","
                    << points[i].z << ","
                    << points[target].index << ","
                    << points[target].x << ","
                    << points[target].y << ","
                    << points[target].z << ","
                    << d << ","
                    << points[target].tangent_x << ","
                    << points[target].tangent_y << ","
                    << points[target].tangent_z << "\n";
      }

      if (audit.targets > 0) {
        audit.mean_distance = distance_sum / static_cast<double>(audit.targets);
      } else {
        audit.min_distance = 0.0;
      }
      audit.accepted = audit.targets >= args.min_targets_per_group && audit.monotonic_target_index;
      if (audit.accepted) {
        ++accepted_groups;
      }
      audits.push_back(audit);
    }

    std::ofstream groups_csv(groups_path);
    groups_csv << "group_id,points,targets,min_distance,max_distance,mean_distance,monotonic_target_index,accepted\n";
    for (const auto & audit : audits) {
      groups_csv << audit.group_id << ","
                 << audit.points << ","
                 << audit.targets << ","
                 << audit.min_distance << ","
                 << audit.max_distance << ","
                 << audit.mean_distance << ","
                 << (audit.monotonic_target_index ? "true" : "false") << ","
                 << (audit.accepted ? "true" : "false") << "\n";
    }

    std::ofstream summary(summary_path);
    summary << "input_csv: " << args.input_csv << "\n";
    summary << "groups: " << audits.size() << "\n";
    summary << "accepted_groups: " << accepted_groups << "\n";
    summary << "targets: " << total_targets << "\n";
    summary << "lookahead_m: " << args.lookahead_m << "\n";
    summary << "min_target_distance_m: " << args.min_target_distance_m << "\n";
    summary << "max_target_distance_m: " << args.max_target_distance_m << "\n";
    summary << "min_targets_per_group: " << args.min_targets_per_group << "\n";
    summary << "targets_csv: " << targets_path << "\n";
    summary << "groups_csv: " << groups_path << "\n";
    summary << "decision: "
            << (accepted_groups == static_cast<int>(audits.size()) && accepted_groups > 0 ?
              "accepted_lookahead_target_smoke" : "rejected_lookahead_target_smoke")
            << "\n";

    std::cout << "Lookahead target audit completed.\n";
    std::cout << "Summary: " << summary_path << "\n";
    std::cout << "Targets CSV: " << targets_path << "\n";
    std::cout << "Groups CSV: " << groups_path << "\n";
    std::cout << "Accepted groups: " << accepted_groups << "\n";
    return accepted_groups == static_cast<int>(audits.size()) && accepted_groups > 0 ? 0 : 2;
  } catch (const std::exception & e) {
    std::cerr << "lookahead_target_audit error: " << e.what() << "\n";
    print_usage();
    return 1;
  }
}
