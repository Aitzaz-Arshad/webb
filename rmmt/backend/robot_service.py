import os
import math
import logging
import threading
from datetime import datetime, timezone
import roslibpy
import json
import numpy as np
from models import db, Room, Order, RobotState, Delivery, Obstacle
from astar_modified import AStarPlanner
from PSO_path_smothing import PathSmooting

logger = logging.getLogger(__name__)

def yaw_to_quaternion(yaw):
    """
    Converts a yaw angle in radians to a geometry_msgs/Quaternion representation
    for a 2D planar rotation (around the Z axis).
    """
    return {
        'x': 0.0,
        'y': 0.0,
        'z': float(math.sin(yaw / 2.0)),
        'w': float(math.cos(yaw / 2.0))
    }

def calculate_path_length(path):
    if len(path) < 2:
        return 0.0
    total_length = 0.0
    for i in range(len(path) - 1):
        dx = path[i+1][0] - path[i][0]
        dy = path[i+1][1] - path[i][1]
        total_length += math.hypot(dx, dy)
    return total_length

class RobotManager:
    _instance = None
    _lock = threading.Lock()

    def __new__(cls, *args, **kwargs):
        with cls._lock:
            if cls._instance is None:
                cls._instance = super().__new__(cls)
                cls._instance._initialized = False
            return cls._instance

    def init_app(self, app):
        if self._initialized:
            return
        self.app = app
        
        # Read WSL IP from environment variable, default to 127.0.0.1
        # In newer WSL2 versions, localhost is forwarded, but users can specify a direct IP.
        self.wsl_ip = os.environ.get('WSL_IP', '127.0.0.1')
        self.port = 9090
        
        self.ros = None
        self.action_client = None
        self.follow_path_client = None
        self.compute_path_client = None
        self.current_goal_id = None
        self.pose_subscriber = None
        self.plan_subscriber = None
        self.pub_astar = None
        self.pub_smooth = None
        self.ros_path = []
        self.return_timer = None
        
        self.state_lock = threading.Lock()
        
        # Connect to ROS2 rosbridge
        self._connect_ros()
        
        # Initialize singleton row in database & complete active queues from previous runs
        with self.app.app_context():
            try:
                # Mark previous active queues as completed/delivered instead of deleting
                now = datetime.now(timezone.utc)
                
                active_orders = Order.query.filter(Order.status.in_(['pending', 'in_progress'])).all()
                for o in active_orders:
                    o.status = 'completed'
                    
                active_deliveries = Delivery.query.filter(Delivery.status.in_(['pending', 'in_transit'])).all()
                for d in active_deliveries:
                    d.status = 'delivered'
                    d.delivered_at = now
                    
                db.session.commit()
                logger.info("Marked previous active queue orders and deliveries as completed/delivered.")
            except Exception as e:
                db.session.rollback()
                logger.error(f"Error completing active queue at startup: {e}")

            state = RobotState.query.get(1)
            if not state:
                state = RobotState(id=1, current_status='free', current_order_id=None)
                db.session.add(state)
                db.session.commit()
                logger.info("Initialized RobotState singleton row.")
            else:
                state.current_status = 'free'
                state.current_order_id = None
                db.session.commit()
                logger.info("Reset RobotState singleton to FREE at startup.")
                
        self._initialized = True
        logger.info(f"RobotManager initialized (WSL IP: {self.wsl_ip}:{self.port})")
 
    def _connect_ros(self):
        logger.info(f"Connecting to ROS 2 rosbridge at ws://{self.wsl_ip}:{self.port}...")
        try:
            self.ros = roslibpy.Ros(host=self.wsl_ip, port=self.port)
            self.ros.on_ready(self._on_ros_ready)
            self.ros.on('close', lambda *a: self._on_ros_close())
            self.ros.on('error', lambda *a: logger.error("ROS connection error occurred."))
            self.ros.run()
        except Exception as e:
            logger.error(f"Failed to start ROS connection thread: {e}")
 
    def _on_ros_ready(self):
        logger.info("Connected to ROS 2 via rosbridge successfully!")
        self.action_client = roslibpy.ActionClient(
            self.ros, '/navigate_to_pose', 'nav2_msgs/action/NavigateToPose'
        )
        self.follow_path_client = roslibpy.ActionClient(
            self.ros, '/follow_path', 'nav2_msgs/action/FollowPath'
        )
        self.compute_path_client = roslibpy.ActionClient(
            self.ros, '/compute_path_to_pose', 'nav2_msgs/action/ComputePathToPose'
        )
        try:
            self.pub_astar = roslibpy.Topic(self.ros, '/plan', 'nav_msgs/msg/Path')
            self.pub_smooth = roslibpy.Topic(self.ros, '/plan_smoothed', 'nav_msgs/msg/Path')
            logger.info("Initialized path publishers for RViz (/plan, /plan_smoothed)")
        except Exception as e:
            logger.error(f"Failed to initialize RViz path publishers: {e}")
            
        try:
            self.pose_subscriber = roslibpy.Topic(self.ros, '/amcl_pose', 'geometry_msgs/msg/PoseWithCovarianceStamped')
            self.pose_subscriber.subscribe(self._on_pose_received)
            logger.info("Subscribed to /amcl_pose successfully")
        except Exception as e:
            logger.error(f"Failed to subscribe to /amcl_pose: {e}")
            
        try:
            self.plan_subscriber = roslibpy.Topic(self.ros, '/plan', 'nav_msgs/msg/Path')
            self.plan_subscriber.subscribe(self._on_plan_received)
            logger.info("Subscribed to /plan successfully")
        except Exception as e:
            logger.error(f"Failed to subscribe to /plan: {e}")
            
        # Check queue on connection
        self.trigger_dispatch()
 
    def _on_ros_close(self):
        logger.warning("Disconnected from ROS 2 rosbridge.")
        self.action_client = None
        self.follow_path_client = None
        self.compute_path_client = None
        if self.pose_subscriber:
            try:
                self.pose_subscriber.unsubscribe()
            except Exception:
                pass
            self.pose_subscriber = None
        if self.plan_subscriber:
            try:
                self.plan_subscriber.unsubscribe()
            except Exception:
                pass
            self.plan_subscriber = None
            
        if self.pub_astar:
            try:
                self.pub_astar.unadvertise()
            except Exception:
                pass
            self.pub_astar = None
            
        if self.pub_smooth:
            try:
                self.pub_smooth.unadvertise()
            except Exception:
                pass
            self.pub_smooth = None
            
        # Attempt reconnection periodically
        try:
            self.ros.terminate()
        except Exception:
            pass
        threading.Timer(5.0, self._connect_ros).start()
        
    def _on_pose_received(self, message):
        """
        Callback when robot pose is received from AMCL. Updates DB coords.
        """
        try:
            pose_cov = message.get('pose', {})
            pose = pose_cov.get('pose', {})
            position = pose.get('position', {})
            x = position.get('x', 0.0)
            y = position.get('y', 0.0)
            
            with self.app.app_context():
                state = RobotState.query.get(1)
                if state:
                    state.x = float(x)
                    state.y = float(y)
                    db.session.commit()
        except Exception as e:
            logger.error(f"Error processing pose message: {e}")

    def _on_plan_received(self, message):
        """
        Callback when ROS path is received from Nav2 global planner (/plan topic).
        """
        try:
            poses = message.get('poses', [])
            path = []
            for p in poses:
                pos = p.get('pose', {}).get('position', {})
                x = pos.get('x')
                y = pos.get('y')
                if x is not None and y is not None:
                    path.append([float(x), float(y)])
            with self.state_lock:
                self.ros_path = path
        except Exception as e:
            logger.error(f"Error parsing ROS plan: {e}")

    def get_ros_path(self):
        with self.state_lock:
            return list(self.ros_path)

    def get_status(self):
        """
        Thread-safe fetch of current robot state and current order dictionary.
        """
        with self.app.app_context():
            state = RobotState.query.get(1)
            if not state:
                return {"status": "free", "current_order": None}
            
            order_dict = None
            if state.current_order_id:
                order = Order.query.get(state.current_order_id)
                if order:
                    order_dict = order.to_dict()
                    
            pending_count = Order.query.filter_by(status='pending').count()
            return {
                "status": state.current_status,
                "current_order": order_dict,
                "queue_length": pending_count,
                "x": state.x,
                "y": state.y
            }

    def trigger_dispatch(self):
        """
        Core FSM dispatcher. Checks the queue and transitions state based on rules.
        Runs inside state_lock to ensure atomic state transitions.
        """
        with self.state_lock:
            with self.app.app_context():
                state = RobotState.query.get(1)
                if not state:
                    logger.error("RobotState singleton not found in DB.")
                    return

                logger.debug(f"trigger_dispatch called. Current state: {state.current_status}, Current order: {state.current_order_id}")
                
                # Rule 1: FREE + new order arrives -> transition and send Nav2 goal
                if state.current_status == 'free':
                    next_order = self._get_next_due_order()
                    if next_order:
                        self._start_order(state, next_order)

                # Rule 4: While RETURNING, if a new order arrives, immediately preempt
                elif state.current_status == 'returning':
                    next_order = self._get_next_due_order()
                    if next_order:
                        logger.info(f"Preempting returning robot for new order #{next_order.id}")
                        self._cancel_current_goal()
                        self._start_order(state, next_order)
                    elif self.current_goal_id is None:
                        # Check if robot is already at Home (0.0, 0.0)
                        home_room = Room.query.filter_by(is_robot_home=True).first()
                        home_x = home_room.x if home_room else 0.0
                        home_y = home_room.y if home_room else 0.0
                        dist_to_home = math.hypot(state.x - home_x, state.y - home_y)
                        
                        if dist_to_home < 0.5:
                            logger.info("Robot is already at Home station. Setting state to FREE.")
                            state.current_status = 'free'
                            db.session.commit()
                        else:
                            logger.info(f"Robot is returning and needs goal (dist={dist_to_home:.2f}m). Sending return-to-home goal...")
                            self._send_goal_to_home()

    def _get_next_due_order(self):
        """
        Queries the orders table for the next pending order (unscheduled or due now).
        Sorts by created_at (FIFO).
        """
        now_utc = datetime.now(timezone.utc)
        now_naive = datetime.now()

        orders = Order.query.filter_by(status='pending').all()
        due_orders = []

        for order in orders:
            if order.scheduled_time is None:
                due_orders.append(order)
            else:
                sched = order.scheduled_time
                if sched.tzinfo is not None:
                    is_due = sched <= now_utc
                else:
                    is_due = sched <= now_naive
                if is_due:
                    due_orders.append(order)

        if due_orders:
            # FIFO sorting
            due_orders.sort(key=lambda o: o.created_at)
            return due_orders[0]
        return None

    def _start_order(self, state, order):
        """
        Locks state, updates DB, and sends NavigateToPose goal.
        """
        # Ensure any active returning goal or timer is cleanly preempted
        self._cancel_current_goal()

        order.status = 'in_progress'
        state.current_order_id = order.id
        
        delivery = Delivery.query.filter_by(order_id=order.id).first()
        if delivery:
            delivery.status = 'in_transit'
        
        if order.type == 'room_to_room':
            state.current_status = 'en_route_to_pickup'
            db.session.commit()
            logger.info(f"Order #{order.id} in progress. Heading to pickup room: {order.pickup_room}")
            self._send_goal_to_room(order.pickup_room)
        else:  # robo_to_room
            state.current_status = 'en_route_to_dropoff'
            db.session.commit()
            logger.info(f"Order #{order.id} in progress. Heading to dropoff room: {order.dropoff_room}")
            self._send_goal_to_room(order.dropoff_room)

    def _cancel_current_goal(self):
        """
        Cancels the active goal across all action clients and stops any return-to-home timer.
        """
        if self.return_timer:
            try:
                self.return_timer.cancel()
                logger.info("Cancelled pending return-to-home timer.")
            except Exception:
                pass
            self.return_timer = None

        if self.current_goal_id:
            logger.info(f"Cancelling active goal across ROS action clients: {self.current_goal_id}")
            for client in [self.follow_path_client, self.action_client, self.compute_path_client]:
                if client:
                    try:
                        client.cancel_goal(self.current_goal_id)
                    except Exception as e:
                        pass
            self.current_goal_id = None

    def _send_goal_to_room(self, room_name):
        room = Room.query.filter_by(name=room_name).first()
        if not room:
            logger.error(f"Target room '{room_name}' not found in DB!")
            self._handle_navigation_failure("Target room not found")
            return
        self._send_nav2_goal(room.x, room.y, room.theta)

    def _send_goal_to_home(self):
        self.return_timer = None
        room = Room.query.filter_by(is_robot_home=True).first()
        if room:
            logger.info(f"Heading back to robot home: {room.name}")
            self._send_nav2_goal(room.x, room.y, room.theta)
        else:
            logger.warning("No robot home room configured. Defaulting to (-0.033712, 0.018029, 0.0)")
            self._send_nav2_goal(-0.033712, 0.018029, 0.0)

    def _make_ros_path_msg(self, waypoints):
        """Converts waypoints into a ROS 2 nav_msgs/msg/Path message dictionary."""
        poses = []
        for i, pt in enumerate(waypoints):
            pt_x, pt_y = float(pt[0]), float(pt[1])
            yaw_pt = 0.0
            if i < len(waypoints) - 1:
                next_x, next_y = waypoints[i+1][0], waypoints[i+1][1]
                yaw_pt = math.atan2(next_y - pt_y, next_x - pt_x)
                
            poses.append({
                'header': {
                    'stamp': {'sec': 0, 'nanosec': 0},
                    'frame_id': 'map'
                },
                'pose': {
                    'position': {'x': pt_x, 'y': pt_y, 'z': 0.0},
                    'orientation': yaw_to_quaternion(yaw_pt)
                }
            })
            
        return {
            'header': {
                'stamp': {'sec': 0, 'nanosec': 0},
                'frame_id': 'map'
            },
            'poses': poses
        }

    def _get_inflated_obstacles(self):
        """Helper to get inflated obstacles from SQLite database."""
        with self.app.app_context():
            db_obstacles = Obstacle.query.all()
            obstacles = []
            for obs in db_obstacles:
                obstacles.append({
                    'type': obs.type,
                    'points': json.loads(obs.points)
                })
        
        # Inflate obstacles by 20 cm safety margin
        margin = 0.20
        inflated_obstacles = []
        for obs in obstacles:
            pts = np.array(obs['points'])
            cx, cy = np.mean(pts, axis=0)
            inflated_pts = []
            for px, py in pts:
                dx = px - cx
                dy = py - cy
                dist = math.hypot(dx, dy)
                if dist > 0:
                    px_new = px + (dx / dist) * margin
                    py_new = py + (dy / dist) * margin
                else:
                    px_new = px
                    py_new = py
                inflated_pts.append([px_new, py_new])
            inflated_obstacles.append({
                'type': 'polygon',
                'points': inflated_pts
            })
        return inflated_obstacles

    def _prune_dense_path(self, raw_path, inflated_obstacles):
        """Downsamples a dense path from Nav2 into key waypoints."""
        if not raw_path or len(raw_path) < 3:
            return raw_path
            
        boundary = {'bottom_left': (-20.0, -20.0), 'top_right': (20.0, 20.0)}
        planner = AStarPlanner(start=raw_path[0], goal=raw_path[-1], obstacles=inflated_obstacles, boundary=boundary)
        pruned = planner.prune_path(raw_path)
        logger.info(f"Pruned dense path from {len(raw_path)} to {len(pruned)} key waypoints.")
        return pruned

    def _smooth_pruned_path(self, pruned_path, inflated_obstacles):
        """Applies PSO path smoothing to a list of waypoints."""
        smooth_waypoints = pruned_path
        if len(pruned_path) >= 3:
            try:
                way_points_array = np.array(pruned_path)
                way_points = [way_points_array]
                total_length = calculate_path_length(pruned_path)
                smooth_pts, _ = PathSmooting.smooth_path(
                    way_points,
                    total_length,
                    None,
                    inflated_obstacles
                )
                if isinstance(smooth_pts, np.ndarray):
                    smooth_waypoints = smooth_pts.tolist()
                else:
                    smooth_waypoints = smooth_pts
                logger.info(f"Smoothed path using PSO (length: {total_length:.2f}m -> {calculate_path_length(smooth_waypoints):.2f}m).")
            except Exception as e:
                logger.error(f"Error in PSO smoothing: {e}")
        return smooth_waypoints

    def _execute_follow_path_goal(self, smooth_path):
        """Sends the smoothed path as a goal to FollowPath action server."""
        path_msg = self._make_ros_path_msg(smooth_path)
        goal_msg = {
            'path': path_msg,
            'controller_id': '',
            'goal_checker_id': ''
        }
        goal = roslibpy.Goal(goal_msg)
        temp_goal_id = None
        
        def result_cb(result):
            self._on_goal_result(temp_goal_id, result)
            
        def feedback_cb(feedback):
            pass
            
        def err_cb(err):
            self._on_goal_error(temp_goal_id, err)
            
        try:
            goal_id = self.follow_path_client.send_goal(goal, result_cb, feedback_cb, err_cb)
            temp_goal_id = goal_id
            self.current_goal_id = goal_id
            logger.info(f"Successfully sent custom smooth path to FollowPath. Goal ID: {goal_id}")
        except Exception as e:
            logger.error(f"Error sending FollowPath goal: {e}")
            self._handle_navigation_failure(str(e))

    def _execute_fallback_pose_goal(self, x, y, yaw):
        """Sends the target pose as fallback to NavigateToPose action server."""
        logger.info("Executing Fallback: Sending goal pose to standard Nav2 global planner.")
        quat = yaw_to_quaternion(yaw)
        goal_msg = {
            'pose': {
                'header': {
                    'frame_id': 'map',
                    'stamp': {
                        'sec': 0,
                        'nanosec': 0
                    }
                },
                'pose': {
                    'position': {
                        'x': float(x),
                        'y': float(y),
                        'z': 0.0
                    },
                    'orientation': quat
                }
            }
        }
        
        goal = roslibpy.Goal(goal_msg)
        temp_goal_id = None
        
        def result_cb(result):
            self._on_goal_result(temp_goal_id, result)
            
        def feedback_cb(feedback):
            pass
            
        def err_cb(err):
            self._on_goal_error(temp_goal_id, err)
            
        try:
            goal_id = self.action_client.send_goal(goal, result_cb, feedback_cb, err_cb)
            temp_goal_id = goal_id
            self.current_goal_id = goal_id
            logger.info(f"Successfully sent fallback goal to NavigateToPose. Goal ID: {goal_id}")
        except Exception as e:
            logger.error(f"Error sending fallback goal via ActionClient: {e}")
            self._handle_navigation_failure(str(e))

    def _send_nav2_goal(self, x, y, yaw):
        if not self.ros or not self.ros.is_connected:
            logger.error("Cannot send Nav2 goal: rosbridge is disconnected.")
            self._handle_navigation_failure("rosbridge disconnected")
            return
            
        if not self.action_client or not self.follow_path_client or not self.compute_path_client:
            logger.error("Cannot send Nav2 goal: ActionClients not fully initialized.")
            self._handle_navigation_failure("ActionClients not initialized")
            return

        logger.info(f"Requesting raw path from Nav2 Global Planner to pose: ({x:.2f}, {y:.2f})")
        
        # Prepare ComputePathToPose Goal
        goal_msg = {
            'goal': {
                'header': {
                    'frame_id': 'map',
                    'stamp': {'sec': 0, 'nanosec': 0}
                },
                'pose': {
                    'position': {'x': float(x), 'y': float(y), 'z': 0.0},
                    'orientation': yaw_to_quaternion(yaw)
                }
            },
            'planner_id': '',
            'use_start': False
        }
        
        goal = roslibpy.Goal(goal_msg)
        
        def result_callback(result):
            try:
                status = result.get('status')
                is_success = (status == roslibpy.GoalStatus.SUCCEEDED or status == roslibpy.GoalStatus.SUCCEEDED.value or status == 4)
                if not is_success:
                    logger.warning(f"ComputePathToPose action failed with status: {status}. Running fallback.")
                    self._execute_fallback_pose_goal(x, y, yaw)
                    return
                
                path_res = result.get('result', {}).get('path', {})
                poses = path_res.get('poses', [])
                if not poses:
                    logger.warning("ComputePathToPose returned an empty path. Running fallback.")
                    self._execute_fallback_pose_goal(x, y, yaw)
                    return
                
                # Extract coordinates
                raw_path = []
                for p in poses:
                    pos = p.get('pose', {}).get('position', {})
                    raw_path.append([float(pos.get('x', 0.0)), float(pos.get('y', 0.0))])
                
                logger.info(f"Received raw Nav2 path of {len(raw_path)} points.")
                
                # Load and inflate obstacles
                inflated_obstacles = self._get_inflated_obstacles()
                
                # Downsample/prune raw path to key waypoints
                pruned_path = self._prune_dense_path(raw_path, inflated_obstacles)
                
                # Smooth pruned path
                smooth_path = self._smooth_pruned_path(pruned_path, inflated_obstacles)
                
                # Publish both paths to RViz topics
                if self.pub_astar:
                    try:
                        self.pub_astar.publish(self._make_ros_path_msg(raw_path))
                        logger.info("Published raw Nav2 path to /plan")
                    except Exception as pe:
                        logger.error(f"Failed to publish raw path: {pe}")
                        
                if self.pub_smooth:
                    try:
                        self.pub_smooth.publish(self._make_ros_path_msg(smooth_path))
                        logger.info("Published smoothed PSO path to /plan_smoothed")
                    except Exception as pe:
                        logger.error(f"Failed to publish smooth path: {pe}")
                
                # Send smoothed path to follow_path
                self._execute_follow_path_goal(smooth_path)
                
            except Exception as ex:
                logger.error(f"Error processing computed path: {ex}. Running fallback.")
                self._execute_fallback_pose_goal(x, y, yaw)

        def err_callback(err):
            logger.error(f"ComputePathToPose action error: {err}. Running fallback.")
            self._execute_fallback_pose_goal(x, y, yaw)
            
        try:
            self.compute_path_client.send_goal(goal, result_callback, None, err_callback)
            logger.info("Sent ComputePathToPose request to Nav2 Global Planner...")
        except Exception as e:
            logger.error(f"Error requesting path from Nav2: {e}. Running fallback.")
            self._execute_fallback_pose_goal(x, y, yaw)

    def _on_goal_result(self, goal_id, result):
        """
        Invoked on Nav2 goal result. Drives state machine forward if successful.
        """
        logger.info(f"Received result callback for Goal ID: {goal_id}. Result: {result}")
        
        with self.state_lock:
            # Preemption Guard: ignore results of goals that are no longer active
            if goal_id != self.current_goal_id:
                logger.info(f"Ignoring result of preempted/inactive goal: {goal_id}")
                return

            self.current_goal_id = None
            status = result.get('status')
            is_success = (status == roslibpy.GoalStatus.SUCCEEDED or status == roslibpy.GoalStatus.SUCCEEDED.value or status == 4)
            
            with self.app.app_context():
                state = RobotState.query.get(1)
                if not state:
                    return

                order = Order.query.get(state.current_order_id) if state.current_order_id else None

                if not is_success:
                    logger.warning(f"Nav2 goal failed or was cancelled. Status: {status}")
                    # Revert active order status back to pending, reset state to free
                    if order:
                        order.status = 'pending'
                        delivery = Delivery.query.filter_by(order_id=order.id).first()
                        if delivery:
                            delivery.status = 'pending'
                    state.current_status = 'free'
                    state.current_order_id = None
                    db.session.commit()
                    # Trigger next dispatch in case other orders are pending
                    self.trigger_dispatch()
                    return

                # Success State Transitions
                if state.current_status == 'en_route_to_pickup':
                    # Reached pickup room (room_to_room only) -> head to dropoff
                    if order and order.type == 'room_to_room':
                        state.current_status = 'en_route_to_dropoff'
                        db.session.commit()
                        logger.info(f"Reached pickup room. Moving to dropoff room: {order.dropoff_room}")
                        self._send_goal_to_room(order.dropoff_room)

                elif state.current_status == 'en_route_to_dropoff':
                    # Reached dropoff room -> complete order, head to home room
                    if order:
                        order.status = 'completed'
                        order.completed_at = datetime.now(timezone.utc)
                        logger.info(f"Reached dropoff room. Order #{order.id} completed successfully!")
                        
                        delivery = Delivery.query.filter_by(order_id=order.id).first()
                        if delivery:
                            delivery.status = 'delivered'
                            delivery.delivered_at = datetime.now(timezone.utc)
                    
                    state.current_status = 'returning'
                    state.current_order_id = None
                    db.session.commit()
                    
                    logger.info("Delivery completed! Pausing 5s for package pickup, then returning home...")
                    threading.Timer(5.0, self._send_goal_to_home).start()

                elif state.current_status == 'returning':
                    # Reached home room -> transition to FREE, look for new jobs
                    state.current_status = 'free'
                    state.current_order_id = None
                    db.session.commit()
                    logger.info("Reached robot home. Robot is now FREE.")
                    self.trigger_dispatch()

    def _on_goal_error(self, goal_id, err):
        """
        Invoked on action bridge errors.
        """
        logger.error(f"Action error for Goal ID {goal_id}: {err}")
        with self.state_lock:
            if goal_id != self.current_goal_id:
                return
            self.current_goal_id = None
            self._handle_navigation_failure(f"Action error: {err}")

    def _handle_navigation_failure(self, reason):
        """
        Utility function to safely roll back DB states when navigation fails.
        """
        with self.app.app_context():
            state = RobotState.query.get(1)
            if state:
                order = Order.query.get(state.current_order_id) if state.current_order_id else None
                if order:
                    order.status = 'pending'
                state.current_status = 'free'
                state.current_order_id = None
                db.session.commit()
                logger.info(f"Reset DB state due to navigation failure: {reason}")
                
        # Try to dispatch again later
        threading.Timer(10.0, self.trigger_dispatch).start()
