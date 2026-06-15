import math

from launch import LaunchDescription
from launch_ros.actions import Node


def _multilevel_slow_loop_waypoints(center_x=-25.0, center_y=-25.0, radius=15.0):
    levels_ned = [-32.0, -24.0, -16.0]
    points_per_lap = 24
    laps_per_level = 2
    waypoints = [0.0, 0.0, -8.0]
    yaws = [math.atan2(center_y, center_x)]

    for level_index, z in enumerate(levels_ned):
        for lap in range(laps_per_level):
            point_range = range(points_per_lap)
            if (level_index + lap) % 2 == 1:
                point_range = reversed(range(points_per_lap))
            for point in point_range:
                theta = 2.0 * math.pi * point / points_per_lap
                x = center_x + radius * math.cos(theta)
                y = center_y + radius * math.sin(theta)
                waypoints.extend([x, y, z])
                yaws.append(math.atan2(center_y - y, center_x - x))

    waypoints.extend([center_x + radius, center_y, levels_ned[-1]])
    yaws.append(math.atan2(center_y - center_y, center_x - (center_x + radius)))
    return waypoints, yaws


def generate_launch_description():
    waypoints, yaws = _multilevel_slow_loop_waypoints()
    return LaunchDescription([
        Node(
            package='zcw_px4_baseline',
            executable='offboard_waypoint_sequence',
            name='wind_turbine_multilevel_slow_loop_closure_smoke_baseline',
            output='screen',
            parameters=[{
                'waypoints_ned': waypoints,
                'yaws_rad': yaws,
                'acceptance_radius_m': 2.5,
                'hold_ticks_required': 8,
            }],
        ),
    ])
