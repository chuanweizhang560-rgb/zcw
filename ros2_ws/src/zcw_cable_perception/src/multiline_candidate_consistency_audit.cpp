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
#include <string>
#include <vector>

namespace
{
struct Candidate
{
  int frame{0};
  int line{0};
  int inliers{0};
  double inlier_ratio{0.0};
  double point_x{0.0};
  double point_y{0.0};
  double point_z{0.0};
  double dir_x{0.0};
  double dir_y{0.0};
  double dir_z{0.0};
  double min_x{0.0};
  double min_y{0.0};
  double min_z{0.0};
  double max_x{0.0};
  double max_y{0.0};
  double max_z{0.0};
};

struct Args
{
  std::string input_csv;
  std::string output_dir{"data/results"};
  std::string output_prefix{"multiline_candidate_consistency"};
  double min_abs_dir_x{0.85};
  double max_abs_dir_y{0.05};
  double max_abs_dir_z{0.18};
  double min_x_span{40.0};
  double max_y_span{5.0};
  double max_z_span{18.0};
  double y_bin_size{2.0};
  int min_candidates_per_group{2};
  int min_frames_per_group{2};
  int min_accepted_groups{1};
};

struct GroupStats
{
  int group_id{0};
  int candidates{0};
  int min_frame{std::numeric_limits<int>::max()};
  int max_frame{std::numeric_limits<int>::min()};
  std::map<int, int> frames;
  double mean_dir_x{0.0};
  double mean_dir_y{0.0};
  double mean_dir_z{0.0};
  double mean_point_y{0.0};
  double mean_point_z{0.0};
  double min_x{std::numeric_limits<double>::infinity()};
  double max_x{-std::numeric_limits<double>::infinity()};
  double min_y{std::numeric_limits<double>::infinity()};
  double max_y{-std::numeric_limits<double>::infinity()};
  double min_z{std::numeric_limits<double>::infinity()};
  double max_z{-std::numeric_limits<double>::infinity()};
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

double to_double(const std::string & value)
{
  return std::stod(value);
}

int to_int(const std::string & value)
{
  return std::stoi(value);
}

std::vector<Candidate> read_candidates(const std::string & path)
{
  std::ifstream in(path);
  if (!in) {
    throw std::runtime_error("failed to open input csv: " + path);
  }

  std::vector<Candidate> candidates;
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
    if (cols.size() != 16) {
      throw std::runtime_error("unexpected csv column count in line: " + line);
    }
    Candidate c;
    c.frame = to_int(cols[0]);
    c.line = to_int(cols[1]);
    c.inliers = to_int(cols[2]);
    c.inlier_ratio = to_double(cols[3]);
    c.point_x = to_double(cols[4]);
    c.point_y = to_double(cols[5]);
    c.point_z = to_double(cols[6]);
    c.dir_x = to_double(cols[7]);
    c.dir_y = to_double(cols[8]);
    c.dir_z = to_double(cols[9]);
    c.min_x = to_double(cols[10]);
    c.min_y = to_double(cols[11]);
    c.min_z = to_double(cols[12]);
    c.max_x = to_double(cols[13]);
    c.max_y = to_double(cols[14]);
    c.max_z = to_double(cols[15]);

    if (c.dir_x < 0.0) {
      c.dir_x = -c.dir_x;
      c.dir_y = -c.dir_y;
      c.dir_z = -c.dir_z;
    }
    candidates.push_back(c);
  }
  return candidates;
}

bool passes_geometry_gate(const Candidate & c, const Args & args)
{
  const double x_span = c.max_x - c.min_x;
  const double y_span = c.max_y - c.min_y;
  const double z_span = c.max_z - c.min_z;
  return std::abs(c.dir_x) >= args.min_abs_dir_x &&
         std::abs(c.dir_y) <= args.max_abs_dir_y &&
         std::abs(c.dir_z) <= args.max_abs_dir_z &&
         x_span >= args.min_x_span &&
         y_span <= args.max_y_span &&
         z_span <= args.max_z_span;
}

std::map<int, GroupStats> build_groups(const std::vector<Candidate> & accepted, const Args & args)
{
  std::map<int, GroupStats> groups;
  for (const auto & c : accepted) {
    const int group_id = static_cast<int>(std::floor(c.point_y / args.y_bin_size));
    auto & g = groups[group_id];
    g.group_id = group_id;
    g.candidates += 1;
    g.min_frame = std::min(g.min_frame, c.frame);
    g.max_frame = std::max(g.max_frame, c.frame);
    g.frames[c.frame] += 1;
    g.mean_dir_x += c.dir_x;
    g.mean_dir_y += c.dir_y;
    g.mean_dir_z += c.dir_z;
    g.mean_point_y += c.point_y;
    g.mean_point_z += c.point_z;
    g.min_x = std::min(g.min_x, c.min_x);
    g.max_x = std::max(g.max_x, c.max_x);
    g.min_y = std::min(g.min_y, c.min_y);
    g.max_y = std::max(g.max_y, c.max_y);
    g.min_z = std::min(g.min_z, c.min_z);
    g.max_z = std::max(g.max_z, c.max_z);
  }

  for (auto & item : groups) {
    auto & g = item.second;
    if (g.candidates > 0) {
      const double n = static_cast<double>(g.candidates);
      g.mean_dir_x /= n;
      g.mean_dir_y /= n;
      g.mean_dir_z /= n;
      g.mean_point_y /= n;
      g.mean_point_z /= n;
    }
    g.accepted = g.candidates >= args.min_candidates_per_group &&
      static_cast<int>(g.frames.size()) >= args.min_frames_per_group;
  }
  return groups;
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
    << "Usage: multiline_candidate_consistency_audit --input <lines.csv> [options]\n"
    << "Options:\n"
    << "  --output-dir <dir>\n"
    << "  --output-prefix <name>\n"
    << "  --min-abs-dir-x <value>\n"
    << "  --max-abs-dir-y <value>\n"
    << "  --max-abs-dir-z <value>\n"
    << "  --min-x-span <meters>\n"
    << "  --max-y-span <meters>\n"
    << "  --max-z-span <meters>\n"
    << "  --y-bin-size <meters>\n"
    << "  --min-candidates-per-group <count>\n"
    << "  --min-frames-per-group <count>\n"
    << "  --min-accepted-groups <count>\n";
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
    } else if (key == "--min-abs-dir-x") {
      args.min_abs_dir_x = to_double(require_value(key));
    } else if (key == "--max-abs-dir-y") {
      args.max_abs_dir_y = to_double(require_value(key));
    } else if (key == "--max-abs-dir-z") {
      args.max_abs_dir_z = to_double(require_value(key));
    } else if (key == "--min-x-span") {
      args.min_x_span = to_double(require_value(key));
    } else if (key == "--max-y-span") {
      args.max_y_span = to_double(require_value(key));
    } else if (key == "--max-z-span") {
      args.max_z_span = to_double(require_value(key));
    } else if (key == "--y-bin-size") {
      args.y_bin_size = to_double(require_value(key));
    } else if (key == "--min-candidates-per-group") {
      args.min_candidates_per_group = to_int(require_value(key));
    } else if (key == "--min-frames-per-group") {
      args.min_frames_per_group = to_int(require_value(key));
    } else if (key == "--min-accepted-groups") {
      args.min_accepted_groups = to_int(require_value(key));
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
  if (args.y_bin_size <= 0.0) {
    throw std::runtime_error("--y-bin-size must be positive");
  }
  return args;
}
}  // namespace

int main(int argc, char ** argv)
{
  try {
    const Args args = parse_args(argc, argv);
    std::filesystem::create_directories(args.output_dir);

    const auto candidates = read_candidates(args.input_csv);
    std::vector<Candidate> accepted_candidates;
    for (const auto & candidate : candidates) {
      if (passes_geometry_gate(candidate, args)) {
        accepted_candidates.push_back(candidate);
      }
    }

    const auto groups = build_groups(accepted_candidates, args);
    int accepted_groups = 0;
    for (const auto & item : groups) {
      if (item.second.accepted) {
        ++accepted_groups;
      }
    }

    const auto stamp = stamp_string();
    const auto summary_path = args.output_dir + "/" + args.output_prefix + "_" + stamp + ".txt";
    const auto groups_path = args.output_dir + "/" + args.output_prefix + "_groups_" + stamp + ".csv";
    const auto accepted_path = args.output_dir + "/" + args.output_prefix + "_accepted_" + stamp + ".csv";

    std::ofstream accepted_csv(accepted_path);
    accepted_csv << "frame,line,inliers,inlier_ratio,point_y,point_z,dir_x,dir_y,dir_z,x_span,y_span,z_span\n";
    for (const auto & c : accepted_candidates) {
      accepted_csv << c.frame << ","
                   << c.line << ","
                   << c.inliers << ","
                   << c.inlier_ratio << ","
                   << c.point_y << ","
                   << c.point_z << ","
                   << c.dir_x << ","
                   << c.dir_y << ","
                   << c.dir_z << ","
                   << (c.max_x - c.min_x) << ","
                   << (c.max_y - c.min_y) << ","
                   << (c.max_z - c.min_z) << "\n";
    }

    std::ofstream groups_csv(groups_path);
    groups_csv << "group_id,candidates,frames,min_frame,max_frame,mean_point_y,mean_point_z,"
               << "mean_dir_x,mean_dir_y,mean_dir_z,min_x,max_x,min_y,max_y,min_z,max_z,accepted\n";
    for (const auto & item : groups) {
      const auto & g = item.second;
      groups_csv << g.group_id << ","
                 << g.candidates << ","
                 << g.frames.size() << ","
                 << g.min_frame << ","
                 << g.max_frame << ","
                 << g.mean_point_y << ","
                 << g.mean_point_z << ","
                 << g.mean_dir_x << ","
                 << g.mean_dir_y << ","
                 << g.mean_dir_z << ","
                 << g.min_x << ","
                 << g.max_x << ","
                 << g.min_y << ","
                 << g.max_y << ","
                 << g.min_z << ","
                 << g.max_z << ","
                 << (g.accepted ? "true" : "false") << "\n";
    }

    std::ofstream summary(summary_path);
    summary << "input_csv: " << args.input_csv << "\n";
    summary << "total_candidates: " << candidates.size() << "\n";
    summary << "geometry_gate_candidates: " << accepted_candidates.size() << "\n";
    summary << "groups: " << groups.size() << "\n";
    summary << "accepted_groups: " << accepted_groups << "\n";
    summary << "min_accepted_groups: " << args.min_accepted_groups << "\n";
    summary << "min_abs_dir_x: " << args.min_abs_dir_x << "\n";
    summary << "max_abs_dir_y: " << args.max_abs_dir_y << "\n";
    summary << "max_abs_dir_z: " << args.max_abs_dir_z << "\n";
    summary << "min_x_span: " << args.min_x_span << "\n";
    summary << "max_y_span: " << args.max_y_span << "\n";
    summary << "max_z_span: " << args.max_z_span << "\n";
    summary << "y_bin_size: " << args.y_bin_size << "\n";
    summary << "min_candidates_per_group: " << args.min_candidates_per_group << "\n";
    summary << "min_frames_per_group: " << args.min_frames_per_group << "\n";
    summary << "accepted_csv: " << accepted_path << "\n";
    summary << "groups_csv: " << groups_path << "\n";
    summary << "decision: "
            << (accepted_groups >= args.min_accepted_groups ?
              "accepted_for_catenary_input_smoke" :
              "rejected_for_catenary_input_smoke")
            << "\n";

    std::cout << "Multiline consistency audit completed.\n";
    std::cout << "Summary: " << summary_path << "\n";
    std::cout << "Groups CSV: " << groups_path << "\n";
    std::cout << "Accepted CSV: " << accepted_path << "\n";
    std::cout << "Accepted groups: " << accepted_groups << "\n";

    return accepted_groups >= args.min_accepted_groups ? 0 : 2;
  } catch (const std::exception & e) {
    std::cerr << "multiline_candidate_consistency_audit error: " << e.what() << "\n";
    print_usage();
    return 1;
  }
}
