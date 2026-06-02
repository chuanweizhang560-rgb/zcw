from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    return LaunchDescription([
        Node(
            package='zcw_px4_baseline',
            executable='offboard_hover_retry',
            name='offboard_hover_retry',
            output='screen',
        ),
    ])
