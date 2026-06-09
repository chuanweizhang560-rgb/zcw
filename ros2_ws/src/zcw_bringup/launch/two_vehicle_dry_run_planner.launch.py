from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    return LaunchDescription([
        Node(
            package='zcw_px4_baseline',
            executable='two_vehicle_dry_run_planner',
            name='two_vehicle_dry_run_planner',
            output='screen',
            parameters=[{
                'publish_hz': 2.0,
                'base_x': 0.0,
                'base_y': 0.0,
                'relay_radius_m': 800.0,
                'goal_acceptance_radius_m': 5.0,
                'max_state_age_sec': 2.0,
                'vehicle_1_goal_x': -25.0,
                'vehicle_1_goal_y': -10.0,
                'vehicle_1_goal_z': -20.0,
                'vehicle_2_goal_x': -12.5,
                'vehicle_2_goal_y': -5.0,
                'vehicle_2_goal_z': -12.0,
            }],
        ),
    ])
