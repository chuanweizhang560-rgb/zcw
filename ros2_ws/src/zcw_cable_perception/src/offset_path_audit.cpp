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
  double source_x{0.0};
  double source_y{0.0};
  double source_z{0.0};
  double offset_y_m{0.0};
  double offset_z_m{0.0};
  double tangent_x{0.0};
  double tangent_y{0.0};
  double tangent_z{0.0};
};

struct Args
{
  std::string input_csv;
  std::string output_dir{"data/results"};
  std::string output_prefix{"offset_path_audit"};
  double expected_step_m{10.0};
  double max_step_error_m{1.0};
  double max_curvature{0.02};
  double max_offset_error_m{0.05};
  int min_points_per_group{3};
};

struct GroupAudit
{
  std::string group_id;
  int points{0};
  double min_step{std::numeric_limits<double>::infinity()};
  double max_step{0.0};
  double mean_step{0.0};
  double max_step_error{0.0};
  double max_curvature{0.0};
  double max_offset_y_error{0.0};
  double max_offset_z_error{0.0};
  bool monotonic_x{true};
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
    p.source_x = to_double(cols[5]);
    p.source_y = to_double(cols[6]);
    p.source_z = to_double(cols[7]);
    p.offset_y_m = to_double(cols[8]);
    p.offset_z_m = to_double(cols[9]);
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

double curvature_from_three_points(const Point & a, const Point & b, const Point & c)
{
  const double ab = distance(a, b);
  const double bc = distance(b, c);
  const double ac = distance(a, c);
  if (ab <= 1e-9 || bc <= 1e-9 || ac <= 1e-9) {
    return std::numeric_limits<double>::infinity();
  }

  const double ux = b.x - a.x;
  const double uy = b.y - a.y;
  const double uz = b.z - a.z;
  const double vx = c.x - a.x;
  const double vy = c.y - a.y;
  const double vz = c.z - a.z;
  const double cx = uy * vz - uz * vy;
  const double cy = uz * vx - ux * vz;
  const double cz = ux * vy - uy * vx;
  const double area2 = std::sqrt(cx * cx + cy * cy + cz * cz);
  return 2.0 * area2 / (ab * bc * ac);
}

GroupAudit audit_group(const std::string & group_id, std::vector<Point> points, const Args & args)
{
  std::sort(points.begin(), points.end(), [](const Point & a, const Point & b) {
    return a.index < b.index;
  });

  GroupAudit audit;
  audit.group_id = group_id;
  audit.points = static_cast<int>(points.size());
  if (points.size() < 2) {
    audit.min_step = 0.0;
    return audit;
  }

  double step_sum = 0.0;
  int step_count = 0;
  for (std::size_t i = 1; i < points.size(); ++i) {
    const double step = distance(points[i - 1], points[i]);
    audit.min_step = std::min(audit.min_step, step);
    audit.max_step = std::max(audit.max_step, step);
    audit.max_step_error = std::max(audit.max_step_error, std::abs(step - args.expected_step_m));
    step_sum += step;
    ++step_count;
    if (points[i].x <= points[i - 1].x) {
      audit.monotonic_x = false;
    }
  }
  audit.mean_step = step_sum / static_cast<double>(step_count);

  for (const auto & p : points) {
    const double observed_offset_y = p.y - p.source_y;
    const double observed_offset_z = p.z - p.source_z;
    audit.max_offset_y_error = std::max(audit.max_offset_y_error, std::abs(observed_offset_y - p.offset_y_m));
    audit.max_offset_z_error = std::max(audit.max_offset_z_error, std::abs(observed_offset_z - p.offset_z_m));
  }

  if (points.size() >= 3) {
    for (std::size_t i = 1; i + 1 < points.size(); ++i) {
      audit.max_curvature = std::max(
        audit.max_curvature,
        curvature_from_three_points(points[i - 1], points[i], points[i + 1]));
    }
  }

  audit.accepted = audit.points >= args.min_points_per_group &&
    audit.monotonic_x &&
    audit.max_step_error <= args.max_step_error_m &&
    audit.max_curvature <= args.max_curvature &&
    audit.max_offset_y_error <= args.max_offset_error_m &&
    audit.max_offset_z_error <= args.max_offset_error_m;
  return audit;
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
    << "Usage: offset_path_audit --input <offset_path.csv> [options]\n"
    << "Options:\n"
    << "  --output-dir <dir>\n"
    << "  --output-prefix <name>\n"
    << "  --expected-step-m <meters>\n"
    << "  --max-step-error-m <meters>\n"
    << "  --max-curvature <1/meters>\n"
    << "  --max-offset-error-m <meters>\n"
    << "  --min-points-per-group <count>\n";
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
    } else if (key == "--expected-step-m") {
      args.expected_step_m = to_double(require_value(key));
    } else if (key == "--max-step-error-m") {
      args.max_step_error_m = to_double(require_value(key));
    } else if (key == "--max-curvature") {
      args.max_curvature = to_double(require_value(key));
    } else if (key == "--max-offset-error-m") {
      args.max_offset_error_m = to_double(require_value(key));
    } else if (key == "--min-points-per-group") {
      args.min_points_per_group = to_int(require_value(key));
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
  if (args.expected_step_m <= 0.0) {
    throw std::runtime_error("--expected-step-m must be positive");
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
    const auto points = read_points(args.input_csv);
    for (const auto & p : points) {
      groups[p.group_id].push_back(p);
    }

    std::vector<GroupAudit> audits;
    int accepted_groups = 0;
    for (const auto & item : groups) {
      auto audit = audit_group(item.first, item.second, args);
      if (audit.accepted) {
        ++accepted_groups;
      }
      audits.push_back(audit);
    }

    const auto stamp = stamp_string();
    const auto summary_path = args.output_dir + "/" + args.output_prefix + "_" + stamp + ".txt";
    const auto groups_path = args.output_dir + "/" + args.output_prefix + "_groups_" + stamp + ".csv";

    std::ofstream groups_csv(groups_path);
    groups_csv << "group_id,points,min_step,max_step,mean_step,max_step_error,"
               << "max_curvature,max_offset_y_error,max_offset_z_error,monotonic_x,accepted\n";
    for (const auto & a : audits) {
      groups_csv << a.group_id << ","
                 << a.points << ","
                 << a.min_step << ","
                 << a.max_step << ","
                 << a.mean_step << ","
                 << a.max_step_error << ","
                 << a.max_curvature << ","
                 << a.max_offset_y_error << ","
                 << a.max_offset_z_error << ","
                 << (a.monotonic_x ? "true" : "false") << ","
                 << (a.accepted ? "true" : "false") << "\n";
    }

    std::ofstream summary(summary_path);
    summary << "input_csv: " << args.input_csv << "\n";
    summary << "points: " << points.size() << "\n";
    summary << "groups: " << audits.size() << "\n";
    summary << "accepted_groups: " << accepted_groups << "\n";
    summary << "expected_step_m: " << args.expected_step_m << "\n";
    summary << "max_step_error_m: " << args.max_step_error_m << "\n";
    summary << "max_curvature: " << args.max_curvature << "\n";
    summary << "max_offset_error_m: " << args.max_offset_error_m << "\n";
    summary << "min_points_per_group: " << args.min_points_per_group << "\n";
    summary << "groups_csv: " << groups_path << "\n";
    summary << "decision: "
            << (accepted_groups == static_cast<int>(audits.size()) && accepted_groups > 0 ?
              "accepted_offset_path_smoke" : "rejected_offset_path_smoke")
            << "\n";

    std::cout << "Offset path audit completed.\n";
    std::cout << "Summary: " << summary_path << "\n";
    std::cout << "Groups CSV: " << groups_path << "\n";
    std::cout << "Accepted groups: " << accepted_groups << "\n";
    return accepted_groups == static_cast<int>(audits.size()) && accepted_groups > 0 ? 0 : 2;
  } catch (const std::exception & e) {
    std::cerr << "offset_path_audit error: " << e.what() << "\n";
    print_usage();
    return 1;
  }
}
