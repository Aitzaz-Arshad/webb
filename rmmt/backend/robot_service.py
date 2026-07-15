import os
import math
import logging
import threading
from datetime import datetime, timezone
import roslibpy
from models import db, Room, Order, RobotState, Delivery

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
        self.current_goal_id = None
        self.pose_subscriber = None
        self.plan_subscriber = None
        self.ros_path = []
        
        self.state_lock = threading.Lock()
        
        # Connect to ROS2 rosbridge
        self._connect_ros()
        
        # Initialize singleton row in database
        with self.app.app_context():
            state = RobotState.query.get(1)
            if not state:
                state = RobotState(id=1, current_status='free', current_order_id=None)
                db.session.add(state)
                db.session.commit()
                logger.info("Initialized RobotState singleton row.")
                
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
        Cancels the active goal on rosbridge.
        """
        if self.action_client and self.current_goal_id:
            logger.info(f"Cancelling Nav2 goal: {self.current_goal_id}")
            try:
                self.action_client.cancel_goal(self.current_goal_id)
            except Exception as e:
                logger.error(f"Error cancelling goal: {e}")
            self.current_goal_id = None

    def _send_goal_to_room(self, room_name):
        room = Room.query.filter_by(name=room_name).first()
        if not room:
            logger.error(f"Target room '{room_name}' not found in DB!")
            self._handle_navigation_failure("Target room not found")
            return
        self._send_nav2_goal(room.x, room.y, room.theta)

    def _send_goal_to_home(self):
        room = Room.query.filter_by(is_robot_home=True).first()
        if room:
            logger.info(f"Heading back to robot home: {room.name}")
            self._send_nav2_goal(room.x, room.y, room.theta)
        else:
            logger.warning("No robot home room configured. Defaulting to (0.0, 0.0, 0.0)")
            self._send_nav2_goal(0.0, 0.0, 0.0)

    def _send_nav2_goal(self, x, y, yaw):
        if not self.ros or not self.ros.is_connected:
            logger.error("Cannot send Nav2 goal: rosbridge is disconnected.")
            self._handle_navigation_failure("rosbridge disconnected")
            return
            
        if not self.action_client:
            logger.error("Cannot send Nav2 goal: ActionClient not initialized.")
            self._handle_navigation_failure("ActionClient not initialized")
            return

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
        
        # We need to capture the returned goal ID synchronously and bind it to callbacks.
        # Closure-bound callback parameters handle preemption race conditions.
        temp_goal_id = None
        
        def result_cb(result):
            self._on_goal_result(temp_goal_id, result)
            
        def feedback_cb(feedback):
            # Optional feedback logging
            pass
            
        def err_cb(err):
            self._on_goal_error(temp_goal_id, err)
            
        try:
            goal_id = self.action_client.send_goal(goal, result_cb, feedback_cb, err_cb)
            temp_goal_id = goal_id
            self.current_goal_id = goal_id
            logger.info(f"Successfully sent goal to Nav2. Assigned Goal ID: {goal_id}")
        except Exception as e:
            logger.error(f"Error sending goal via ActionClient: {e}")
            self._handle_navigation_failure(str(e))

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
                    
                    self._send_goal_to_home()
                    # Try to preempt the returning state immediately if another order is waiting
                    self.trigger_dispatch()

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
