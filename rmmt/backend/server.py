import collections
import platform
import math

# Bypassing Windows WMI query hang in Python 3.14
UnameResult = collections.namedtuple('UnameResult', ['system', 'node', 'release', 'version', 'machine', 'processor'])
platform.uname = lambda: UnameResult(system="Windows", node="localhost", release="10", version="10.0.0", machine="AMD64", processor="Intel")
platform.machine = lambda: "AMD64"
platform.win32_ver = lambda *args, **kwargs: ("10", "10.0.0", "", "Multiprocessor Free")

from flask import Flask, request, jsonify
from flask_cors import CORS
import multiprocessing
import threading
import tkinter as tk
from tkinter import simpledialog

from astar_modified import AStarPlanner
from dp_planner import DynamicProgrammingPlanner
from PSO_path_smothing import PathSmooting
from helper_data_prepration_planner_random import helper_DPR_obj

from copy import deepcopy
import matplotlib
try:
    matplotlib.use('TkAgg')
except:
    pass

import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np
import os
import json
import shutil
try:
    import open3d as o3d
except ImportError:
    o3d = None

import cv2
import logging
from typing import List, Tuple, Dict, Any
from matplotlib.patches import Polygon as MplPolygon
from matplotlib.patches import Circle as MplCircle

from datetime import datetime, timezone
from apscheduler.schedulers.background import BackgroundScheduler

# Configure logging
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Database Configuration
db_path = os.path.join(os.path.abspath(os.path.dirname(__file__)), 'instance', 'app.db')
os.makedirs(os.path.join(os.path.abspath(os.path.dirname(__file__)), 'instance'), exist_ok=True)
app.config['SQLALCHEMY_DATABASE_URI'] = f'sqlite:///{db_path}'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

from models import db, migrate, User, Room, Delivery, Order, RobotState, Obstacle
from robot_service import RobotManager
db.init_app(app)
migrate.init_app(app, db)

with app.app_context():
    db.create_all()
    # Seed default obstacles if table is empty
    if Obstacle.query.count() == 0:
        default_walls = [
            {'type': 'polygon', 'points': [[-8.0, 0.8], [0.0, 0.8], [0.0, 1.2], [-8.0, 1.2]]},
            {'type': 'polygon', 'points': [[-13.5, 0.8], [-10.5, 0.8], [-10.5, 1.2], [-13.5, 1.2]]},
            {'type': 'polygon', 'points': [[-16.0, 0.8], [-15.5, 0.8], [-15.5, 1.2], [-16.0, 1.2]]},
            
            {'type': 'polygon', 'points': [[-8.0, -1.2], [0.0, -1.2], [0.0, -0.8], [-8.0, -0.8]]},
            {'type': 'polygon', 'points': [[-13.5, -1.2], [-10.0, -1.2], [-10.0, -0.8], [-13.5, -0.8]]},
            {'type': 'polygon', 'points': [[-16.0, -1.2], [-15.5, -1.2], [-15.5, -0.8], [-16.0, -0.8]]},
        ]
        import json
        for wall in default_walls:
            db.session.add(Obstacle(
                type=wall['type'],
                points=json.dumps(wall['points'])
            ))
        db.session.commit()

robot_manager = RobotManager()
robot_manager.init_app(app)



# ===================================================================
# VISUALIZATION CONFIGURATION
# ===================================================================
ENABLE_WEB_MAP_VIZ = False      # DISABLED to prevent duplicate plots
ENABLE_MATPLOTLIB_VIZ = True   
VIZ_FLAG = 3 

# ===================================================================
# HELPER FUNCTIONS
# ===================================================================

def startup_logging():
    logger.info("Server starting up...")
    logger.info(f"Registered route: /.well-known/agent.json")
    logger.info(f"Registered route: /tasks/send")
    logger.info(f"Registered route: /upload-pcd")

def latlng_to_meters1(lat, lon, ref_lat, ref_lon):
    m_per_deg_lat = 111132.954 - 559.822 * np.cos(2 * np.radians(ref_lat)) + 1.175 * np.cos(4 * np.radians(ref_lat))
    m_per_deg_lon = 111319.488 * np.cos(np.radians(ref_lat))
    x = (lon - ref_lon) * m_per_deg_lon
    y = (lat - ref_lat) * m_per_deg_lat
    return x, y

def meters_to_latlng1(x, y, ref_lat, ref_lon):
    m_per_deg_lat = 111132.954 - 559.822 * np.cos(2 * np.radians(ref_lat)) + 1.175 * np.cos(4 * np.radians(ref_lat))
    m_per_deg_lon = 111319.488 * np.cos(np.radians(ref_lat))
    lon = x / m_per_deg_lon + ref_lon
    lat = y / m_per_deg_lat + ref_lat
    return lat, lon

def calculate_path_length(path):
    if len(path) < 2:
        return 0.0
    total_length = 0.0
    for i in range(len(path) - 1):
        dx = path[i+1][0] - path[i][0]
        dy = path[i+1][1] - path[i][1]
        total_length += np.sqrt(dx**2 + dy**2)
    return total_length

def is_point_inside_polygon_robust(x, y, poly_points):
    n = len(poly_points)
    inside = False
    if n == 0:
        return False
    p1x, p1y = poly_points[0][0], poly_points[0][1]
    for i in range(n + 1):
        p2x, p2y = poly_points[i % n][0], poly_points[i % n][1]
        if y > min(p1y, p2y):
            if y <= max(p1y, p2y):
                if x <= max(p1x, p2x):
                    if p1y != p2y:
                        xinters = (y - p1y) * (p2x - p1x) / (p2y - p1y) + p1x
                    if p1x == p2x or x <= xinters:
                        inside = not inside
        p1x, p1y = p2x, p2y
    return inside

def check_point_collision(point, obstacles):
    try:
        x, y = float(point[0]), float(point[1])
        safety_margin = 0.15  # 15 cm safety buffer
        
        for obs in obstacles:
            if obs.get('type') in ['rectangle', 'polygon']:
                try:
                    points = obs.get('points', [])
                    if len(points) > 0:
                        # Quick bounding box check with safety margin
                        min_x = min(p[0] for p in points) - safety_margin
                        max_x = max(p[0] for p in points) + safety_margin
                        min_y = min(p[1] for p in points) - safety_margin
                        max_y = max(p[1] for p in points) + safety_margin
                        
                        if min_x <= x <= max_x and min_y <= y <= max_y:
                            if is_point_inside_polygon_robust(x, y, points):
                                return True
                except Exception:
                    continue
            elif obs.get('type') == 'circle':
                center = obs.get('center')
                radius = obs.get('radius')
                if center and radius:
                    try:
                        cx, cy = float(center[0]), float(center[1])
                        dist = np.sqrt((x - cx)**2 + (y - cy)**2)
                        if dist <= radius + safety_margin:
                            return True
                    except Exception:
                        continue
        return False
    except Exception:
        return True

def validate_smooth_path_ENHANCED(smooth_path, obstacles, num_samples=300):
    try:
        if len(smooth_path) < 2:
            return True
        sample_indices = np.linspace(0, len(smooth_path) - 1, num_samples, dtype=int)
        for idx in sample_indices:
            point = smooth_path[idx]
            if check_point_collision(point, obstacles):
                return False
        return True
    except Exception as e:
        logger.error(f"Error in enhanced path validation: {e}")
        return False

def validate_control_points_segments(control_points, obstacles, samples_per_segment=50):
    try:
        if len(control_points) < 2:
            return True
        for i in range(len(control_points) - 1):
            p1 = np.array(control_points[i])
            p2 = np.array(control_points[i+1])
            for alpha in np.linspace(0, 1, samples_per_segment):
                test_point = p1 + alpha * (p2 - p1)
                if check_point_collision(test_point, obstacles):
                    return False
        return True
    except Exception as e:
        logger.error(f"Error validating control point segments: {e}")
        return False

def apply_path_smoothing_FIXED(pruned_path, obstacles=None):
    try:
        if len(pruned_path) < 3:
            return np.array(pruned_path), np.array(pruned_path)
        
        obstacles_for_smoothing = obstacles if obstacles is not None else []
        way_points_array = np.array(pruned_path)
        way_points = [way_points_array]
        shortest_path_length = calculate_path_length(pruned_path)
        axes_objects = None
        
        smooth_waypoints, control_waypoints = PathSmooting.smooth_path(
            way_points,
            shortest_path_length,
            axes_objects,
            obstacles_for_smoothing,
        )
        
        # Validation checks
        for i, cp in enumerate(control_waypoints):
            if check_point_collision(cp, obstacles_for_smoothing):
                return np.array(pruned_path), np.array(pruned_path)
        
        if not validate_control_points_segments(control_waypoints, obstacles_for_smoothing):
            return np.array(pruned_path), np.array(pruned_path)
        
        if not validate_smooth_path_ENHANCED(smooth_waypoints, obstacles_for_smoothing):
            return np.array(pruned_path), np.array(pruned_path)
        
        return smooth_waypoints, control_waypoints
    except Exception as e:
        logger.error(f"❌ EXCEPTION in path smoothing: {e}")
        return np.array(pruned_path), np.array(pruned_path)

def process_request_data(data):
    try:
        if not data.get('boundary') or not data['boundary'].get('points') or len(data['boundary']['points']) == 0:
            raise ValueError("Boundary points are missing or invalid")
        if not data.get('start') or not data.get('goal'):
            raise ValueError("Start or goal point is missing")
        ref_lat = data['boundary']['points'][0]['latitude']
        ref_lon = data['boundary']['points'][0]['longitude']
        start_x, start_y = latlng_to_meters1(data['start']['latitude'], data['start']['longitude'], ref_lat, ref_lon)
        goal_x, goal_y = latlng_to_meters1(data['goal']['latitude'], data['goal']['longitude'], ref_lat, ref_lon)
        boundary_points_m = [latlng_to_meters1(p['latitude'], p['longitude'], ref_lat, ref_lon) for p in data['boundary']['points']]
        min_x = min(p[0] for p in boundary_points_m)
        max_x = max(p[0] for p in boundary_points_m)
        min_y = min(p[1] for p in boundary_points_m)
        max_y = max(p[1] for p in boundary_points_m)
        boundary_m = {'bottom_left': (min_x, min_y), 'top_right': (max_x, max_y)}
        obstacles_m = []
        for obs in data.get('obstacles', []):
            if obs['type'] == 'rectangle':
                points_m = [latlng_to_meters1(p['latitude'], p['longitude'], ref_lat, ref_lon) for p in obs['points']]
                obstacles_m.append({'type': 'rectangle', 'points': points_m})
            elif obs['type'] == 'circle':
                center_x, center_y = latlng_to_meters1(obs['center']['latitude'], obs['center']['longitude'], ref_lat, ref_lon)
                obstacles_m.append({'type': 'circle', 'center': (center_x, center_y), 'radius': obs['radius']})
            elif obs['type'] == 'polygon':
                points_m = [latlng_to_meters1(p['latitude'], p['longitude'], ref_lat, ref_lon) for p in obs['points']]
                obstacles_m.append({'type': 'polygon', 'points': points_m})
        return (start_x, start_y), (goal_x, goal_y), obstacles_m, boundary_m, ref_lat, ref_lon
    except (KeyError, TypeError, ValueError) as e:
        raise ValueError(f"Invalid request data: {str(e)}")

# ===================================================================
# VISUALIZATION FUNCTIONS
# ===================================================================

def visualize_web_map_auto(data, save_plot=False):
    """Visualize the map drawn on web interface."""
    try:
        start, goal, obstacles, boundary, ref_lat, ref_lon = process_request_data(data)
        
        fig, ax = plt.subplots(figsize=(12, 10))
        ax.set_aspect('equal')
        ax.grid(True, alpha=0.3, linestyle='--', linewidth=0.5)
        
        bl = boundary['bottom_left']
        tr = boundary['top_right']
        width = tr[0] - bl[0]
        height = tr[1] - bl[1]
        
        boundary_rect = patches.Rectangle(
            bl, width, height,
            linewidth=3, edgecolor='green', facecolor='lightgreen',
            alpha=0.15, linestyle='--', label='Workspace Boundary'
        )
        ax.add_patch(boundary_rect)
        
        padding = max(width, height) * 0.1
        ax.set_xlim(bl[0] - padding, tr[0] + padding)
        ax.set_ylim(bl[1] - padding, tr[1] + padding)
        
        for i, obs in enumerate(obstacles):
            if obs['type'] in ['rectangle', 'polygon']:
                points = np.array(obs['points'])
                poly = MplPolygon(
                    points, closed=True, edgecolor='red', facecolor='red',
                    alpha=0.5, linewidth=2.5
                )
                ax.add_patch(poly)
            elif obs['type'] == 'circle':
                circle = MplCircle(
                    obs['center'], obs['radius'],
                    edgecolor='red', facecolor='red',
                    alpha=0.5, linewidth=2.5
                )
                ax.add_patch(circle)
        
        if start:
            ax.plot(start[0], start[1], 'o', color='green', markersize=20, label='Start')
        if goal:
            ax.plot(goal[0], goal[1], 's', color='red', markersize=20, label='Goal')
        
        ax.legend(loc='upper right')
        ax.set_title(f"Web Map: {data.get('name', 'Unnamed')}")
        plt.show()
        
    except Exception as e:
        print(f"❌ Failed to visualize web map: {e}")

def ask_user_for_viz_flag_popup(initial_val=3):
    """
    Opens a robust pop-up dialog to ask for the visualization flag.
    Includes Option 5 for DP Grid.
    """
    try:
        # Create a hidden root window
        root = tk.Tk()
        root.withdraw() 
        root.attributes('-topmost', True) # Force it to appear on top
        
        # Define prompt text
        prompt = (
            "Select Visualization Mode:\n\n"
            "1: A* path only\n"
            "2: Smooth pathing\n"
            "3: Both paths \n"
            "4: Obstacle inflation\n"
            "5: DP Grid Decomposition"
        )
        
        # Show dialog
        flag = simpledialog.askinteger(
            "Visualization Settings", 
            prompt,
            parent=root,
            minvalue=1, 
            maxvalue=5,
            initialvalue=initial_val
        )
        
        root.destroy()
        
        if flag is None:
            return initial_val
            
        return flag

    except Exception as e:
        print(f"❌ Popup failed: {e}. Defaulting to {initial_val}.")
        return initial_val

def visualize_result_in_matplotlib(path_meters, pruned_path_meters, smooth_path_meters, 
                                 control_path_meters, obstacles_meters, boundary_meters, 
                                 start_meters, goal_meters, original_obstacles_meters=None, 
                                 flag=3, grid_data=None):
    try:
        from visualize_planning import visualize_from_server_response
        
        response_data = {
            'path': path_meters,
            'pruned_path': pruned_path_meters,
            'smooth_path': smooth_path_meters,
            'control_path': control_path_meters
        }
        
        viz = visualize_from_server_response(
            response_data=response_data,
            obstacles=obstacles_meters,
            boundary=boundary_meters,
            start=start_meters,
            goal=goal_meters,
            flag=flag,
            show_inflation=(flag == 4),
            original_obstacles=original_obstacles_meters,
            grid_data=grid_data
        )
        viz.show()
    except Exception as e:
        print(f"Failed to show matplotlib visualization: {e}")

# ===================================================================
# VISUALIZATION WORKER FUNCTION (Runs in separate process)
# ===================================================================
def visualization_worker(params_data, path, pruned_path, smooth_waypoints, 
                         control_waypoints, inflated_obstacles, boundary, 
                         start, goal, original_obstacles, 
                         enable_web_viz, enable_matplotlib_viz, default_flag,
                         grid_data=None, skip_flag_popup=False):
    """
    This runs in a completely separate process.
    Handles grid_data argument for DP visualization.
    
    Args:
        skip_flag_popup: If True, uses default_flag without asking user
    """
    try:
        # Show web map first if enabled
        if enable_web_viz:
            visualize_web_map_auto(params_data, save_plot=True)
        
        # Ask for flag using POPUP (ONLY if not skipping)
        user_chosen_flag = default_flag
        if enable_matplotlib_viz and not skip_flag_popup:
            user_chosen_flag = ask_user_for_viz_flag_popup(initial_val=default_flag)
        
        # --- IF USER CHOSE FLAG 5 (DP GRID), COMPUTE IT NOW ---
        computed_grid_data = grid_data
        if user_chosen_flag == 5 and grid_data is None:
            logger.info("🔧 Flag 5 selected: Computing DP Grid decomposition...")
            try:
                # Extract map data from params
                start_pt, goal_pt, obstacles_m, boundary_m, ref_lat, ref_lon = process_request_data(params_data)
                
                # Use temp directory for on-demand decomposition
                temp_decomp_dir = "decomposition_temp_viz"
                os.makedirs(temp_decomp_dir, exist_ok=True)
                
                # Create DP planner to get grid
                dp_planner = DynamicProgrammingPlanner(
                    start=start_pt, 
                    goal=goal_pt, 
                    obstacles=obstacles_m, 
                    boundary=boundary_m,
                    decomposition_dir=temp_decomp_dir
                )
                computed_grid_data = dp_planner.get_grid_data()
                logger.info(f"✅ Grid computed: {computed_grid_data['total_cells']} cells")
                
            except Exception as e:
                logger.error(f"❌ Failed to compute DP grid: {e}")
                computed_grid_data = None
        
        # Show result
        if enable_matplotlib_viz:
            visualize_result_in_matplotlib(
                path_meters=path,
                pruned_path_meters=pruned_path,
                smooth_path_meters=smooth_waypoints,
                control_path_meters=control_waypoints,
                obstacles_meters=inflated_obstacles,
                boundary_meters=boundary,
                start_meters=start,
                goal_meters=goal,
                original_obstacles_meters=original_obstacles,
                flag=user_chosen_flag,
                grid_data=computed_grid_data
            )
            
        print("\n✅ Visualization process finished.")
    except Exception as e:
        print(f"❌ Error in visualization worker: {e}")

# ===================================================================
# ROUTES
# ===================================================================

@app.route("/.well-known/agent.json", methods=["GET"])
def agent_card():
    logger.info("Handling request for /.well-known/agent.json")
    return jsonify({
        "name": "PathPlannerAgent",
        "description": "Handles path planning, map management, and PCD processing for navigation.",
        "url": "http://localhost:5000", 
        "version": "1.0",
        "capabilities": {"streaming": False, "pushNotifications": False}
    })

@app.route("/tasks/send", methods=["POST"])
def handle_task():
    try:
        task = request.get_json()
        task_id = task.get("id")
        parts = task["message"]["parts"]
        if not parts or len(parts) < 1:
            return jsonify({"error": "No message parts provided"}), 400
        operation = parts[0]["text"]
        params = parts[1]["text"] if len(parts) > 1 else "{}"
        params_data = json.loads(params)
    except (KeyError, IndexError, TypeError, ValueError) as e:
        return jsonify({"error": f"Invalid task format: {str(e)}"}), 400

    response_data = {}
    status_code = 200

    try:
        if operation == "plan-path":
            # A* PLANNER (WITH SMOOTHING)
            start, goal, obstacles, boundary, ref_lat, ref_lon = process_request_data(params_data)
            inflated_obstacles = helper_DPR_obj.strching_obstacles(obstacles)
            
            planner = AStarPlanner(start=start, goal=goal, obstacles=inflated_obstacles, boundary=boundary)
            path, pruned_path = planner.planning()
            
            if not path:
                return jsonify({"error": "No path found"}), 404
            
            enable_smoothing = params_data.get("enable_smoothing", True)
            smooth_waypoints, control_waypoints = np.array(pruned_path), np.array(pruned_path)
            
            if enable_smoothing and len(pruned_path) >= 3:
                smooth_waypoints, control_waypoints = apply_path_smoothing_FIXED(
                    pruned_path, inflated_obstacles
                )
            
            def to_ll_custom(pts):
                return [{'latitude': lat, 'longitude': lon} for lat, lon in [meters_to_latlng1(p[0], p[1], ref_lat, ref_lon) for p in pts]]

            resp_data = {
                "path": to_ll_custom(path),
                "pruned_path": to_ll_custom(pruned_path),
                "smooth_path": to_ll_custom(smooth_waypoints),
                "control_path": to_ll_custom(control_waypoints)
            }
            
            if ENABLE_MATPLOTLIB_VIZ:
                # Default Flag 3 for A* (Shows popup)
                p = multiprocessing.Process(target=visualization_worker, 
                    args=(params_data, path, pruned_path, smooth_waypoints, control_waypoints, 
                          inflated_obstacles, boundary, start, goal, obstacles, 
                          ENABLE_WEB_MAP_VIZ, ENABLE_MATPLOTLIB_VIZ, 3, None, False))
                p.start()

            return jsonify({"id": task_id, "status": {"state": "completed"}, 
                          "messages": [task["message"], {"role": "agent", "parts": [{"text": json.dumps(resp_data)}]}]})

        elif operation == "plan-path-dp":
            # DP PLANNER (GRID ONLY - NO SMOOTHING)
            name = params_data.get("name", "temp")
            start, goal, obstacles, boundary, ref_lat, ref_lon = process_request_data(params_data)
            
            decomposition_dir = os.path.join("saved_maps", name, "decomposition") if name != "temp" else "decomposition_temp"
            os.makedirs(decomposition_dir, exist_ok=True)
            
            planner = DynamicProgrammingPlanner(start=start, goal=goal, obstacles=obstacles, boundary=boundary, decomposition_dir=decomposition_dir)
            path, pruned_path = planner.planning()
            
            # 1. Get Grid Data (CRITICAL for Option 5)
            grid_data = planner.get_grid_data()
            
            if not path:
                return jsonify({"error": "No path found"}), 404
                
            def to_ll_custom(pts):
                return [{'latitude': lat, 'longitude': lon} for lat, lon in [meters_to_latlng1(p[0], p[1], ref_lat, ref_lon) for p in pts]]

            resp_data = {"path": to_ll_custom(path), "pruned_path": to_ll_custom(pruned_path)}
            
            if ENABLE_MATPLOTLIB_VIZ:
                # Default Flag 5 for DP. Smoothing arrays are empty.
                # skip_flag_popup=False (YOU WANT TO TYPE 5 YOURSELF)
                p = multiprocessing.Process(target=visualization_worker, 
                    args=(params_data, path, pruned_path, [], [], 
                          obstacles, boundary, start, goal, obstacles, 
                          False, True, 5, grid_data, False)) 
                p.start()
            
            return jsonify({"id": task_id, "status": {"state": "completed"}, 
                          "messages": [task["message"], {"role": "agent", "parts": [{"text": json.dumps(resp_data)}]}]})

        elif operation == "get-grid":
            name = params_data.get("name", "temp")
            start, goal, obstacles, boundary, ref_lat, ref_lon = process_request_data(params_data)
            decomposition_dir = os.path.join("saved_maps", name, "decomposition") if name != "temp" else "decomposition_temp"
            if not os.path.exists(decomposition_dir):
                return jsonify({"error": "No decomposition found."}), 404
            planner = DynamicProgrammingPlanner(start=start, goal=goal, obstacles=obstacles, boundary=boundary, decomposition_dir=decomposition_dir)
            grid_data = planner.get_grid_data()
            cells_latlng = []
            for cell in grid_data['cells']:
                bounds = cell['bounds']
                cell_latlng = {
                    'cell_number': cell['cell_number'],
                    'center': {
                        'latitude': meters_to_latlng1(cell['center'][0], cell['center'][1], ref_lat, ref_lon)[0],
                        'longitude': meters_to_latlng1(cell['center'][0], cell['center'][1], ref_lat, ref_lon)[1]
                    },
                    'bounds': {
                        'min': {
                            'latitude': meters_to_latlng1(bounds['min_x'], bounds['min_y'], ref_lat, ref_lon)[0],
                            'longitude': meters_to_latlng1(bounds['min_x'], bounds['min_y'], ref_lat, ref_lon)[1]
                        },
                        'max': {
                            'latitude': meters_to_latlng1(bounds['max_x'], bounds['max_y'], ref_lat, ref_lon)[0],
                            'longitude': meters_to_latlng1(bounds['max_x'], bounds['max_y'], ref_lat, ref_lon)[1]
                        }
                    }
                }
                cells_latlng.append(cell_latlng)
            response_data = {'cells': cells_latlng, 'total_cells': grid_data['total_cells']}
            return jsonify({
                "id": task_id,
                "status": {"state": "completed"},
                "messages": [
                    task["message"],
                    {"role": "agent", "parts": [{"text": json.dumps(response_data)}]}
                ]
            }), 200

        elif operation == "save-map":
            name = params_data.get("name")
            if not name:
                return jsonify({"error": "Map name is required"}), 400
            map_dir = os.path.join("saved_maps", name)
            os.makedirs(map_dir, exist_ok=True)
            json_path = os.path.join(map_dir, f"{name}.json")
            with open(json_path, "w") as f:
                json.dump(params_data, f)
            dummy_start = (0, 0)
            dummy_goal = (1, 1)
            _, _, obstacles, boundary, _, _ = process_request_data(params_data)
            decomposition_dir = os.path.join(map_dir, "decomposition")
            os.makedirs(decomposition_dir, exist_ok=True)
            try:
                DynamicProgrammingPlanner(dummy_start, dummy_goal, obstacles, boundary, decomposition_dir=decomposition_dir)
            except: pass
            response_data = {"success": True}
            return jsonify({
                "id": task_id,
                "status": {"state": "completed"},
                "messages": [
                    task["message"],
                    {"role": "agent", "parts": [{"text": json.dumps(response_data)}]}
                ]
            }), 200

        elif operation == "load-map":
            name = params_data.get("name")
            if not name:
                return jsonify({"error": "Map name is required"}), 400
            json_path = os.path.join("saved_maps", name, f"{name}.json")
            if not os.path.exists(json_path):
                return jsonify({"error": "Map not found"}), 404
            with open(json_path, "r") as f:
                response_data = json.load(f)
            return jsonify({
                "id": task_id,
                "status": {"state": "completed"},
                "messages": [
                    task["message"],
                    {"role": "agent", "parts": [{"text": json.dumps(response_data)}]}
                ]
            }), 200

        elif operation == "list-maps":
            if not os.path.exists("saved_maps"):
                response_data = {"maps": []}
            else:
                maps = [d for d in os.listdir("saved_maps") if os.path.isdir(os.path.join("saved_maps", d))]
                response_data = {"maps": maps}
            return jsonify({
                "id": task_id,
                "status": {"state": "completed"},
                "messages": [
                    task["message"],
                    {"role": "agent", "parts": [{"text": json.dumps(response_data)}]}
                ]
            }), 200

        elif operation == "delete-map":
            name = params_data.get("name")
            if not name:
                return jsonify({"error": "Map name is required"}), 400
            map_dir = os.path.join("saved_maps", name)
            if not os.path.exists(map_dir):
                return jsonify({"error": "Map not found"}), 404
            shutil.rmtree(map_dir)
            response_data = {"success": True}
            return jsonify({
                "id": task_id,
                "status": {"state": "completed"},
                "messages": [
                    task["message"],
                    {"role": "agent", "parts": [{"text": json.dumps(response_data)}]}
                ]
            }), 200

        else:
            return jsonify({"error": f"Unknown operation: {operation}"}), 400

    except ValueError as e:
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        logger.error(f"Error processing {operation}: {e}", exc_info=True)
        return jsonify({"error": f"Error during {operation}"}), 500

@app.route("/upload-pcd", methods=["POST"])
def upload_pcd():
    try:
        if "pcd_file" not in request.files:
            return jsonify({"error": "No PCD file provided"}), 400
        file = request.files["pcd_file"]
        name = request.form.get("name")
        ref_lat = float(request.form.get("ref_lat"))
        ref_lon = float(request.form.get("ref_lon"))
        if not name:
            return jsonify({"error": "Map name is required"}), 400
        map_dir = os.path.join("saved_maps", name)
        os.makedirs(map_dir, exist_ok=True)
        pcd_path = os.path.join(map_dir, "map.pcd")
        file.save(pcd_path)
        pcd = o3d.io.read_point_cloud(pcd_path)
        if pcd.is_empty():
            raise ValueError("PCD file is empty or invalid")
        pcd = pcd.voxel_down_sample(voxel_size=0.005)
        points_3d = np.asarray(pcd.points)
        if points_3d.size == 0:
            raise ValueError("No points after downsampling")
        plane_model, inliers = pcd.segment_plane(distance_threshold=0.01, ransac_n=3, num_iterations=1000)
        outlier_cloud = pcd.select_by_index(inliers, invert=True)
        points_3d_filtered = np.asarray(outlier_cloud.points)
        if points_3d_filtered.size == 0:
            points_2d = np.array([]).reshape(0, 2)
        else:
            z_range = (0.1, 2.0)
            filtered_points = points_3d_filtered[(points_3d_filtered[:, 2] > z_range[0]) & (points_3d_filtered[:, 2] <= z_range[1])]
            points_2d = filtered_points[:, :2] if filtered_points.size > 0 else np.array([]).reshape(0, 2)
        obstacles: List[Dict[str, Any]] = []
        all_points_2d = points_3d[:, :2]
        if points_2d.size > 0:
            min_x_grid, min_y_grid = points_2d.min(axis=0)
            max_x_grid, max_y_grid = points_2d.max(axis=0)
            width = int((max_x_grid - min_x_grid) / 0.005) + 1
            height = int((max_y_grid - min_y_grid) / 0.005) + 1
            if width > 0 and height > 0:
                grid = np.zeros((height, width), dtype=np.uint8)
                for pt in points_2d:
                    x_idx = int((pt[0] - min_x_grid) / 0.005)
                    y_idx = int((pt[1] - min_y_grid) / 0.005)
                    if 0 <= x_idx < width and 0 <= y_idx < height:
                        grid[y_idx, x_idx] = 255
                num_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(grid, connectivity=8)
                for i in range(1, num_labels):
                    area = stats[i, cv2.CC_STAT_AREA]
                    if area > 10:
                        x = stats[i, cv2.CC_STAT_LEFT] * 0.005 + min_x_grid
                        y = stats[i, cv2.CC_STAT_TOP] * 0.005 + min_y_grid
                        w = stats[i, cv2.CC_STAT_WIDTH] * 0.005
                        h = stats[i, cv2.CC_STAT_HEIGHT] * 0.005
                        p1 = meters_to_latlng1(x, y, ref_lat, ref_lon)
                        p2 = meters_to_latlng1(x + w, y, ref_lat, ref_lon)
                        p3 = meters_to_latlng1(x + w, y + h, ref_lat, ref_lon)
                        p4 = meters_to_latlng1(x, y + h, ref_lat, ref_lon)
                        obstacles.append({
                            "type": "rectangle",
                            "points": [
                                {"latitude": p1[0], "longitude": p1[1]},
                                {"latitude": p2[0], "longitude": p2[1]},
                                {"latitude": p3[0], "longitude": p3[1]},
                                {"latitude": p4[0], "longitude": p4[1]}
                            ]
                        })
        min_x_m, min_y_m = all_points_2d.min(axis=0)
        max_x_m, max_y_m = all_points_2d.max(axis=0)
        bl = meters_to_latlng1(min_x_m, min_y_m, ref_lat, ref_lon)
        tr = meters_to_latlng1(max_x_m, max_y_m, ref_lat, ref_lon)
        boundary = {"points": [{"latitude": bl[0], "longitude": bl[1]}, {"latitude": tr[0], "longitude": tr[1]}]}
        map_data = {"name": name, "boundary": boundary, "obstacles": obstacles, "ref_lat": ref_lat, "ref_lon": ref_lon}
        json_path = os.path.join(map_dir, f"{name}.json")
        with open(json_path, "w") as f:
            json.dump(map_data, f)
        try:
            dummy_start_m = (0, 0)
            dummy_goal_m = (1, 1)
            _, _, obstacles_processed, boundary_processed, _, _ = process_request_data(map_data)
            decomposition_dir = os.path.join(map_dir, "decomposition")
            os.makedirs(decomposition_dir, exist_ok=True)
            DynamicProgrammingPlanner(dummy_start_m, dummy_goal_m, obstacles_processed, boundary_processed, decomposition_dir=decomposition_dir)
        except: pass
        return jsonify({
            "id": request.form.get("task_id", "unknown"),
            "status": {"state": "completed"},
            "messages": [
                {"role": "user", "parts": [{"text": "upload-pcd"}]},
                {"role": "agent", "parts": [{"text": json.dumps({"boundary": boundary, "obstacles": obstacles})}]}
            ]
        })
    except ValueError as e:
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        return jsonify({"error": "PCD processing error"}), 500

# ===================================================================
# DATABASE API ENDPOINTS
# ===================================================================

from datetime import datetime, timezone
from werkzeug.security import generate_password_hash, check_password_hash

# 1. AUTHENTICATION ROUTES

@app.route('/auth/register', methods=['POST'])
def auth_register():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "No input data provided"}), 400
        
        name = data.get('name')
        email = data.get('email')
        password = data.get('password')
        role = 'user'

        if not name or not email or not password:
            return jsonify({"error": "Missing required fields: name, email, password"}), 400

        # Check if user already exists
        existing_user = User.query.filter_by(email=email).first()
        if existing_user:
            return jsonify({"error": "User with this email already exists"}), 409

        # Hash password and create user
        password_hash = generate_password_hash(password)
        new_user = User(
            name=name,
            email=email,
            password_hash=password_hash,
            role=role
        )
        db.session.add(new_user)
        db.session.commit()

        return jsonify({"message": "User registered successfully", "user": new_user.to_dict()}), 201
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error in register: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/auth/login', methods=['POST'])
def auth_login():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "No credentials provided"}), 400

        email = data.get('email')
        password = data.get('password')

        if not email or not password:
            return jsonify({"error": "Email and password are required"}), 400

        user = User.query.filter_by(email=email).first()
        if not user or not check_password_hash(user.password_hash, password):
            return jsonify({"error": "Invalid email or password"}), 401

        if not user.is_active:
            return jsonify({"error": "This account has been deactivated."}), 403

        return jsonify({
            "message": "Login successful",
            "user": user.to_dict()
        }), 200
    except Exception as e:
        logger.error(f"Error in login: {e}")
        return jsonify({"error": str(e)}), 500



# 2. ROOM CRUD ROUTES

@app.route('/robot/camera_stream', methods=['GET'])
def camera_stream():
    from flask import Response, stream_with_context
    import urllib.request
    
    wsl_ip = robot_manager.wsl_ip
    url = f"http://{wsl_ip}:8080/stream?topic=/camera/image_raw"
    try:
        req = urllib.request.urlopen(url, timeout=5)
        content_type = req.headers.get('Content-Type', 'multipart/x-mixed-replace; boundary=--boundarydonotcross')
        
        def generate():
            try:
                while True:
                    chunk = req.read(4096)
                    if not chunk:
                        break
                    yield chunk
            except Exception as e:
                logger.error(f"Error reading camera stream chunk: {e}")
            finally:
                req.close()
                
        response = Response(stream_with_context(generate()), content_type=content_type)
        response.headers['Access-Control-Allow-Origin'] = '*'
        return response
    except Exception as e:
        logger.error(f"Error connecting to ROS camera stream proxy: {e}")
        return jsonify({"error": f"Error connecting to ROS camera stream: {str(e)}"}), 500


@app.route('/floorplan', methods=['GET'])
def get_floorplan():
    try:
        from flask import send_file
        floorplan_path = os.path.join(os.path.abspath(os.path.dirname(__file__)), 'floor_plan.png')
        if not os.path.exists(floorplan_path):
            return jsonify({"error": "Floor plan image file not found on server"}), 404
        return send_file(floorplan_path, mimetype='image/png')
    except Exception as e:
        logger.error(f"Error serving floorplan: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/rooms', methods=['GET'])
def get_rooms():
    try:
        is_public = request.args.get('public', 'false').lower() == 'true'
        
        # Check if requester is admin (if headers are provided and is not public)
        requester_id = request.headers.get('X-User-Id')
        requester_role = request.headers.get('X-User-Role')
        
        is_admin = False
        if requester_id and requester_role == 'admin':
            requester = User.query.get(int(requester_id))
            if requester and requester.role == 'admin' and requester.is_active:
                is_admin = True
        
        rooms = Room.query.all()
        
        if is_public or not is_admin:
            # Return only public fields
            res = []
            for r in rooms:
                res.append({
                    'id': r.id,
                    'name': r.name,
                    'label_x': r.label_x,
                    'label_y': r.label_y,
                    'region_width': r.region_width,
                    'region_height': r.region_height,
                    'is_robot_home': r.is_robot_home
                })
            return jsonify(res), 200
        else:
            # Return full data for admin
            return jsonify([room.to_dict() for room in rooms]), 200
    except Exception as e:
        logger.error(f"Error fetching rooms: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/rooms', methods=['POST'])
def create_room():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "No room data provided"}), 400

        name = data.get('name')
        x = data.get('x')
        y = data.get('y')
        theta = data.get('theta')
        is_robot_home = data.get('is_robot_home', False)

        if not name or x is None or y is None or theta is None:
            return jsonify({"error": "Missing required fields: name, x, y, theta"}), 400

        # If this room is robot home, unset any other home rooms
        if is_robot_home:
            Room.query.update({Room.is_robot_home: False})

        new_room = Room(
            name=name,
            x=float(x),
            y=float(y),
            theta=float(theta),
            is_robot_home=bool(is_robot_home),
            label_x=float(data['label_x']) if data.get('label_x') is not None else None,
            label_y=float(data['label_y']) if data.get('label_y') is not None else None,
            region_width=float(data['region_width']) if data.get('region_width') is not None else None,
            region_height=float(data['region_height']) if data.get('region_height') is not None else None
        )
        db.session.add(new_room)
        db.session.commit()

        return jsonify({"message": "Room created successfully", "room": new_room.to_dict()}), 201
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error creating room: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/rooms/<int:room_id>', methods=['PUT'])
def update_room(room_id):
    try:
        requester_id = request.headers.get('X-User-Id')
        requester_role = request.headers.get('X-User-Role')
        
        if not requester_id or requester_role != 'admin':
            return jsonify({"error": "Admin privilege required"}), 403
            
        requester = User.query.get(int(requester_id))
        if not requester or requester.role != 'admin' or not requester.is_active:
            return jsonify({"error": "Admin privilege required"}), 403

        room = Room.query.get(room_id)
        if not room:
            return jsonify({"error": "Room not found"}), 404

        data = request.get_json()
        if not data:
            return jsonify({"error": "No update data provided"}), 400

        if 'name' in data:
            room.name = data['name']
        if 'x' in data:
            room.x = float(data['x'])
        if 'y' in data:
            room.y = float(data['y'])
        if 'theta' in data:
            room.theta = float(data['theta'])
        if 'is_robot_home' in data:
            is_home = bool(data['is_robot_home'])
            if is_home and not room.is_robot_home:
                Room.query.update({Room.is_robot_home: False})
            room.is_robot_home = is_home
        
        if 'label_x' in data:
            room.label_x = float(data['label_x']) if data['label_x'] is not None else None
        if 'label_y' in data:
            room.label_y = float(data['label_y']) if data['label_y'] is not None else None
        if 'region_width' in data:
            room.region_width = float(data['region_width']) if data['region_width'] is not None else None
        if 'region_height' in data:
            room.region_height = float(data['region_height']) if data['region_height'] is not None else None

        db.session.commit()
        return jsonify({"message": "Room updated successfully", "room": room.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error updating room {room_id}: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/rooms/<int:room_id>', methods=['DELETE'])
def delete_room(room_id):
    try:
        room = Room.query.get(room_id)
        if not room:
            return jsonify({"error": "Room not found"}), 404

        db.session.delete(room)
        db.session.commit()
        return jsonify({"message": f"Room {room_id} deleted successfully"}), 200
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error deleting room: {e}")
        return jsonify({"error": str(e)}), 500


# 3. DELIVERY LIFECYCLE ROUTES

def dispatch_delivery(delivery):
    """
    Dispatches the delivery by creating a corresponding FSM Order and triggering FSM.
    """
    logger.info(f"=== DISPATCHING DELIVERY #{delivery.id} ===")
    order_type = 'room_to_room' if delivery.delivery_type == 'room_to_room' else 'robo_to_room'
    
    order = Order(
        type=order_type,
        pickup_room=delivery.pickup_room.name if delivery.pickup_room else None,
        dropoff_room=delivery.recipient_room.name,
        status='pending',
        scheduled_time=delivery.scheduled_at
    )
    db.session.add(order)
    db.session.commit()
    
    delivery.order_id = order.id
    delivery.is_dispatched = True
    db.session.commit()
    
    # Trigger FSM dispatch immediately in a background thread to prevent HTTP blocking
    threading.Thread(target=RobotManager().trigger_dispatch).start()

def check_scheduled_deliveries():
    try:
        with app.app_context():
            now_utc = datetime.now(timezone.utc)
            now_naive = datetime.now()
            
            pending_deliveries = Delivery.query.filter(
                Delivery.status == 'pending',
                Delivery.is_dispatched == False
            ).all()
            
            for delivery in pending_deliveries:
                sched = delivery.scheduled_at
                is_due = True
                if sched is not None:
                    if sched.tzinfo is not None:
                        is_due = sched <= now_utc
                    else:
                        is_due = sched <= now_naive
                
                if is_due:
                    try:
                        dispatch_delivery(delivery)
                        logger.info(f"Successfully dispatched pending delivery #{delivery.id} to queue.")
                    except Exception as ex:
                        db.session.rollback()
                        logger.error(f"Error dispatching delivery #{delivery.id}: {ex}")
    except Exception as e:
        logger.error(f"Error in check_scheduled_deliveries: {e}")

def check_scheduled_orders():
    try:
        with app.app_context():
            threading.Thread(target=RobotManager().trigger_dispatch).start()
    except Exception as e:
        logger.error(f"Error in check_scheduled_orders: {e}")

# Initialize BackgroundScheduler
scheduler = BackgroundScheduler()
scheduler.add_job(func=check_scheduled_deliveries, trigger="interval", minutes=1)
scheduler.add_job(func=check_scheduled_orders, trigger="interval", seconds=10)
scheduler.start()



def check_robot_availability():
    """
    Checks the robot status/availability using FSM state.
    """
    try:
        status_info = RobotManager().get_status()
        status = status_info.get('status', 'free')
        if status in ['free', 'returning']:
            return "Available"
        return "Busy"
    except Exception as e:
        logger.error(f"Error checking robot availability: {e}")
        return "Busy"


@app.route('/deliveries', methods=['POST'])
def create_delivery():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "No delivery data provided"}), 400

        sender_id = data.get('sender_id')
        recipient_room_id = data.get('recipient_room_id')
        pickup_room_id = data.get('pickup_room_id')
        delivery_type = data.get('delivery_type')
        recipient_name = data.get('recipient_name')
        scheduled_at_str = data.get('scheduled_at')

        if not sender_id or not recipient_room_id or not delivery_type or not recipient_name:
            return jsonify({"error": "Missing required fields: sender_id, recipient_room_id, delivery_type, recipient_name"}), 400

        if delivery_type not in ['room_to_room', 'home_to_room']:
            return jsonify({"error": "Invalid delivery_type. Must be 'room_to_room' or 'home_to_room'"}), 400

        if delivery_type == 'room_to_room' and not pickup_room_id:
            return jsonify({"error": "pickup_room_id is required for room_to_room delivery"}), 400

        # Parse scheduled_at if provided
        scheduled_at_dt = None
        if scheduled_at_str:
            try:
                scheduled_at_dt = datetime.fromisoformat(scheduled_at_str.replace('Z', '+00:00'))
            except Exception as ex:
                return jsonify({"error": f"Invalid scheduled_at format. Must be ISO-8601: {ex}"}), 400

        # Validate User and Rooms exist
        sender = User.query.get(sender_id)
        if not sender:
            return jsonify({"error": "Sender user not found"}), 404

        sender_name = sender.name if (sender.name and sender.name.strip() != "") else f"User {sender_id}"

        recipient = Room.query.get(recipient_room_id)
        if not recipient:
            return jsonify({"error": "Recipient room not found"}), 404

        if pickup_room_id:
            pickup = Room.query.get(pickup_room_id)
            if not pickup:
                return jsonify({"error": "Pickup room not found"}), 404

        # Check if scheduled in the future
        is_future = False
        if scheduled_at_dt:
            if scheduled_at_dt.tzinfo is not None:
                is_future = scheduled_at_dt > datetime.now(timezone.utc)
            else:
                is_future = scheduled_at_dt > datetime.now()

        # Determine dispatch behavior
        if not is_future:
            is_dispatched = True
            robot_status = "Queued" if check_robot_availability() == "Busy" else "Available"
        else:
            is_dispatched = False
            robot_status = "Scheduled"

        new_delivery = Delivery(
            sender_id=sender_id,
            sender_name=sender_name,
            recipient_room_id=recipient_room_id,
            pickup_room_id=pickup_room_id if delivery_type == 'room_to_room' else None,
            delivery_type=delivery_type,
            recipient_name=recipient_name,
            status='pending',
            scheduled_at=scheduled_at_dt,
            is_dispatched=is_dispatched
        )
        db.session.add(new_delivery)
        db.session.commit()

        if is_dispatched:
            dispatch_delivery(new_delivery)

        return jsonify({
            "message": "Delivery requested successfully", 
            "delivery": new_delivery.to_dict(),
            "robot_status": robot_status
        }), 201
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error creating delivery: {e}")
        return jsonify({"error": str(e)}), 500


# --- REST API FOR NEW ORDER / ROBOT STATE MACHINE ---

@app.route('/orders', methods=['POST'])
def create_order():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "No order data provided"}), 400

        order_type = data.get('type')
        pickup_room_name = data.get('pickup_room')
        dropoff_room_name = data.get('dropoff_room')
        scheduled_time_str = data.get('scheduled_time')

        if not order_type or not dropoff_room_name:
            return jsonify({"error": "Missing required fields: type, dropoff_room"}), 400

        if order_type not in ['robo_to_room', 'room_to_room']:
            return jsonify({"error": "Invalid type. Must be 'robo_to_room' or 'room_to_room'"}), 400

        if order_type == 'room_to_room' and not pickup_room_name:
            return jsonify({"error": "pickup_room is required for room_to_room orders"}), 400

        # Validate rooms exist in DB
        dropoff_room = Room.query.filter_by(name=dropoff_room_name).first()
        if not dropoff_room:
            return jsonify({"error": f"Dropoff room '{dropoff_room_name}' not found"}), 404

        if order_type == 'room_to_room':
            pickup_room = Room.query.filter_by(name=pickup_room_name).first()
            if not pickup_room:
                return jsonify({"error": f"Pickup room '{pickup_room_name}' not found"}), 404

        # Parse scheduled_time if provided
        scheduled_time_dt = None
        if scheduled_time_str:
            try:
                # Handle potential trailing Z timezone
                scheduled_time_dt = datetime.fromisoformat(scheduled_time_str.replace('Z', '+00:00'))
            except Exception as ex:
                return jsonify({"error": f"Invalid scheduled_time format. Must be ISO-8601: {ex}"}), 400

        # Create new order
        new_order = Order(
            type=order_type,
            pickup_room=pickup_room_name if order_type == 'room_to_room' else None,
            dropoff_room=dropoff_room_name,
            status='pending',
            scheduled_time=scheduled_time_dt
        )
        db.session.add(new_order)
        db.session.commit()

        # Trigger robot dispatch logic immediately if not scheduled in the future
        is_future = False
        if scheduled_time_dt:
            now_compare = datetime.now(timezone.utc) if scheduled_time_dt.tzinfo else datetime.now()
            is_future = scheduled_time_dt > now_compare

        if not is_future:
            # Trigger dispatch asynchronously or on the manager in a background thread
            threading.Thread(target=RobotManager().trigger_dispatch).start()

        return jsonify({
            "message": "Order created successfully",
            "order": new_order.to_dict()
        }), 201
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error creating order: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/orders/<int:order_id>', methods=['GET'])
def get_order_status(order_id):
    try:
        order = Order.query.get(order_id)
        if not order:
            return jsonify({"error": "Order not found"}), 404
        return jsonify(order.to_dict()), 200
    except Exception as e:
        logger.error(f"Error fetching order {order_id}: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/robot/status', methods=['GET'])
def get_robot_status():
    try:
        status_info = RobotManager().get_status()
        return jsonify(status_info), 200
    except Exception as e:
        logger.error(f"Error fetching robot status: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/deliveries', methods=['GET'])
def get_deliveries():
    try:
        requester_id = request.headers.get('X-User-Id')
        requester_role = request.headers.get('X-User-Role')
        
        is_admin = False
        user_id = None
        if requester_id:
            try:
                user_id = int(requester_id)
                user = User.query.get(user_id)
                if user and user.is_active and user.role == 'admin' and requester_role == 'admin':
                    is_admin = True
            except (ValueError, TypeError):
                pass

        status = request.args.get('status')
        date_from = request.args.get('date_from')
        date_to = request.args.get('date_to')

        query = Delivery.query

        # Enforce role scoping
        if requester_id and not is_admin:
            query = query.filter_by(sender_id=user_id)
        else:
            sender_id = request.args.get('sender_id')
            if sender_id:
                query = query.filter_by(sender_id=int(sender_id))

        if status:
            query = query.filter_by(status=status)

        if date_from:
            try:
                val_df = date_from
                if len(val_df) == 10:
                    val_df += "T00:00:00"
                from_dt = datetime.fromisoformat(val_df)
                query = query.filter(Delivery.created_at >= from_dt)
            except ValueError:
                return jsonify({"error": "Invalid date_from format. Use YYYY-MM-DD or ISO 8601"}), 400

        if date_to:
            try:
                val_dt = date_to
                if len(val_dt) == 10:
                    val_dt += "T23:59:59"
                to_dt = datetime.fromisoformat(val_dt)
                query = query.filter(Delivery.created_at <= to_dt)
            except ValueError:
                return jsonify({"error": "Invalid date_to format. Use YYYY-MM-DD or ISO 8601"}), 400

        query = query.order_by(Delivery.created_at.desc())
        deliveries = query.all()
        return jsonify([delivery.to_dict() for delivery in deliveries]), 200
    except Exception as e:
        logger.error(f"Error fetching deliveries: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/deliveries/<int:delivery_id>', methods=['GET'])
def get_delivery(delivery_id):
    try:
        delivery = Delivery.query.get(delivery_id)
        if not delivery:
            return jsonify({"error": "Delivery task not found"}), 404
        return jsonify(delivery.to_dict()), 200
    except Exception as e:
        logger.error(f"Error fetching delivery {delivery_id}: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/deliveries/<int:delivery_id>', methods=['PUT'])
def update_delivery(delivery_id):
    try:
        delivery = Delivery.query.get(delivery_id)
        if not delivery:
            return jsonify({"error": "Delivery task not found"}), 404

        data = request.get_json()
        if not data:
            return jsonify({"error": "No update data provided"}), 400

        status = data.get('status')
        if not status:
            return jsonify({"error": "status field is required"}), 400

        valid_statuses = ['pending', 'picked_up', 'in_transit', 'delivered', 'failed']
        if status not in valid_statuses:
            return jsonify({"error": f"Invalid status. Must be one of: {', '.join(valid_statuses)}"}), 400

        delivery.status = status
        if status == 'delivered':
            delivery.delivered_at = datetime.now(timezone.utc)
        else:
            delivery.delivered_at = None

        db.session.commit()
        return jsonify({"message": "Delivery updated successfully", "delivery": delivery.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error updating delivery {delivery_id}: {e}")
        return jsonify({"error": str(e)}), 500


# 4. USER ENDPOINT (ADMIN VIEW)

@app.route('/users', methods=['GET'])
def get_users():
    try:
        requester_id = request.headers.get('X-User-Id')
        requester_role = request.headers.get('X-User-Role')
        
        if not requester_id or requester_role != 'admin':
            return jsonify({"error": "Admin privilege required"}), 403
            
        requester = User.query.get(int(requester_id))
        if not requester or requester.role != 'admin' or not requester.is_active:
            return jsonify({"error": "Admin privilege required"}), 403

        users = User.query.all()
        return jsonify([user.to_dict() for user in users]), 200
    except Exception as e:
        logger.error(f"Error fetching users: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/users/<int:user_id>', methods=['PUT'])
def update_user(user_id):
    try:
        requester_id = request.headers.get('X-User-Id')
        requester_role = request.headers.get('X-User-Role')
        
        if not requester_id or requester_role != 'admin':
            return jsonify({"error": "Admin privilege required"}), 403
            
        requester = User.query.get(int(requester_id))
        if not requester or requester.role != 'admin' or not requester.is_active:
            return jsonify({"error": "Admin privilege required"}), 403

        target_user = User.query.get(user_id)
        if not target_user:
            return jsonify({"error": "User not found"}), 404

        data = request.get_json()
        if not data:
            return jsonify({"error": "No update data provided"}), 400

        # Safety Check: Prevent admins from deactivating themselves
        if 'is_active' in data and not data['is_active'] and target_user.id == requester.id:
            return jsonify({"error": "Admins cannot deactivate themselves"}), 400

        # Safety Check: Prevent admins from changing their own role to non-admin if they are the only admin
        if 'role' in data and data['role'] != 'admin' and target_user.id == requester.id:
            other_admins = User.query.filter(User.role == 'admin', User.is_active == True, User.id != target_user.id).first()
            if not other_admins:
                return jsonify({"error": "Cannot change role. At least one active Admin is required"}), 400

        if 'role' in data:
            role = data['role']
            if role not in ['admin', 'user']:
                return jsonify({"error": "Invalid role. Must be 'admin' or 'user'"}), 400
            target_user.role = role

        if 'is_active' in data:
            target_user.is_active = bool(data['is_active'])

        db.session.commit()
        return jsonify({"message": "User updated successfully", "user": target_user.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error updating user {user_id}: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/robot/obstacles', methods=['POST'])
def save_obstacles():
    try:
        data = request.get_json() or []
        # Clear old obstacles
        Obstacle.query.delete()
        
        # Save new ones
        import json
        for obs in data:
            new_obs = Obstacle(
                type=obs.get('type', 'polygon'),
                points=json.dumps(obs.get('points', []))
            )
            db.session.add(new_obs)
        db.session.commit()
        return jsonify({"message": "Obstacles saved successfully!"}), 200
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error saving obstacles: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/robot/obstacles', methods=['GET'])
def get_obstacles():
    try:
        obstacles = Obstacle.query.all()
        return jsonify([obs.to_dict() for obs in obstacles]), 200
    except Exception as e:
        logger.error(f"Error fetching obstacles: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/robot/rooms/bulk', methods=['POST'])
def update_rooms_bulk():
    try:
        data = request.get_json() or []
        for room_data in data:
            room_id = room_data.get('id')
            room = Room.query.get(room_id)
            if room:
                room.x = float(room_data.get('x', room.x))
                room.y = float(room_data.get('y', room.y))
                room.label_x = float(room_data.get('label_x', room.label_x))
                room.label_y = float(room_data.get('label_y', room.label_y))
        db.session.commit()
        return jsonify({"message": "Room locations updated successfully!"}), 200
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error in bulk room updates: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/robot/plan_local', methods=['POST'])
def plan_local():
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "No input parameters provided"}), 400
        
        start_x = float(data.get('start_x', 0.0))
        start_y = float(data.get('start_y', 0.0))
        goal_x = float(data.get('goal_x', 0.0))
        goal_y = float(data.get('goal_y', 0.0))
        
        # Read custom drawn obstacles from request, fallback to database/default seeded obstacles
        req_obstacles = data.get('obstacles')
        if req_obstacles is not None:
            obstacles = req_obstacles
        else:
            db_obstacles = Obstacle.query.all()
            obstacles = []
            import json
            for obs in db_obstacles:
                obstacles.append({
                    'type': obs.type,
                    'points': json.loads(obs.points)
                })
        
        boundary = {'bottom_left': (-16.0, -16.0), 'top_right': (16.0, 16.0)}
        
        # Inflate the walls by 0.20 meters (20 cm) safety margin
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
        
        start = (start_x, start_y)
        goal = (goal_x, goal_y)
        
        planner = AStarPlanner(start=start, goal=goal, obstacles=inflated_obstacles, boundary=boundary)
        path, pruned_path = planner.planning()
        
        if not path or len(path) < 2:
            return jsonify({"error": "No path found! Start or Goal location is blocked by obstacles."}), 404
            
        smooth_waypoints = pruned_path
        if len(pruned_path) >= 3:
            try:
                smooth_waypoints, _ = apply_path_smoothing_FIXED(pruned_path, inflated_obstacles)
                if isinstance(smooth_waypoints, np.ndarray):
                    smooth_waypoints = smooth_waypoints.tolist()
            except Exception as e:
                logger.error(f"Error in path smoothing: {e}")
                
        # Clean smooth_waypoints and raw_path to filter out any NaNs/Nones
        def clean_coords(pts):
            clean = []
            for pt in pts:
                if pt is not None and len(pt) >= 2:
                    x, y = pt[0], pt[1]
                    if x is not None and y is not None and not np.isnan(x) and not np.isnan(y):
                        clean.append([float(x), float(y)])
            return clean

        return jsonify({
            "raw_path": clean_coords(path),
            "pruned_path": clean_coords(pruned_path),
            "smooth_path": clean_coords(smooth_waypoints)
        }), 200
    except Exception as e:
        logger.error(f"Error in local path planning: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/robot/plan_ros', methods=['GET'])
def get_ros_plan():
    try:
        from robot_service import RobotManager
        robot_manager = RobotManager()
        path = robot_manager.get_ros_path()
        return jsonify({"path": path}), 200
    except Exception as e:
        logger.error(f"Error getting ROS plan: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    startup_logging()
    app.run(host="0.0.0.0", port=5000, debug=True, use_reloader=True)