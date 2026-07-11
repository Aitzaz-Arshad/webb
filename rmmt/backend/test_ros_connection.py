import roslibpy
import time

ros = roslibpy.Ros(host='172.23.65.98', port=9090)
ros.run()

print('Connected:', ros.is_connected)

action = roslibpy.actionlib.ActionClient(ros, '/navigate_to_pose', 'nav2_msgs/action/NavigateToPose')
goal = roslibpy.actionlib.Goal(action, roslibpy.Message({
    'pose': {
        'header': {'frame_id': 'map'},
        'pose': {
            'position': {'x': 1.0, 'y': 0.5, 'z': 0.0},
            'orientation': {'x': 0.0, 'y': 0.0, 'z': 0.0, 'w': 1.0}
        }
    }
}))

goal.send()
print('Goal sent — check Gazebo, the robot should start moving.')

time.sleep(15)
ros.terminate()
