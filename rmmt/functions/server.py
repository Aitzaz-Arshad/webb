from flask import Flask, request, jsonify
from flask_cors import CORS
from astar_modified import AStarPlanner
from dp_planner import DynamicProgrammingPlanner
# Import path smoothing components
from PSO_path_smothing import PathSmooting
# CRITICAL FIX: Import helper object to access the inflation function
from helper_data_prepration_planner_random import helper_DPR_obj

import numpy as np
import os
import json
import shutil
import open3d as o3d
import cv2
import logging
from typing import List, Tuple, Dict, Any

# Configure logging
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Manual startup logging function
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

def latlng_to_meters(lat, lon, ref_lat, ref_lon):
    lat_rad = np.radians(ref_lat)
    N = 6378137.0 / np.sqrt(1 - (0.00669437999014 * np.sin(lat_rad)**2))
    M = 6378137.0 * (1 - 0.00669437999014) / (1 - (0.00669437999014 * np.sin(lat_rad)**2))**1.5
    m_per_deg_lat = M * np.pi / 180.0
    m_per_deg_lon = N * np.cos(lat_rad) * np.pi / 180.0
    x = (lon - ref_lon) * m_per_deg_lon
    y = (lat - ref_lat) * m_per_deg_lat
    return x, y

def meters_to_latlng(x, y, ref_lat, ref_lon):
    lat_rad = np.radians(ref_lat)
    N = 6378137.0 / np.sqrt(1 - (0.00669437999014 * np.sin(lat_rad)**2))
    M = 6378137.0 * (1 - 0.00669437999014) / (1 - (0.00669437999014 * np.sin(lat_rad)**2))**1.5
    m_per_deg_lat = M * np.pi / 180.0
    m_per_deg_lon = N * np.cos(lat_rad) * np.pi / 180.0
    lon = x / m_per_deg_lon + ref_lon
    lat = y / m_per_deg_lat + ref_lat
    return lat, lon

def calculate_path_length(path):
    """Calculate the total length of a path"""
    if len(path) < 2:
        return 0.0
    total_length = 0.0
    for i in range(len(path) - 1):
        dx = path[i+1][0] - path[i][0]
        dy = path[i+1][1] - path[i][1]
        total_length += np.sqrt(dx**2 + dy**2)
    return total_length

def check_point_collision(point, obstacles):
    """
    Unified point collision check for all obstacle types.
    
    Args:
        point: (x, y) coordinate
        obstacles: List of obstacle dictionaries
    
    Returns:
        True if point collides with any obstacle, False otherwise
    """
    try:
        x, y = float(point[0]), float(point[1])
        
        for obs in obstacles:
            if obs.get('type') in ['rectangle', 'polygon']:
                try:
                    points = np.array(obs.get('points', []))
                    if len(points) > 0:
                        if helper_DPR_obj.pointInObstacleListRect((x, y), [points]):
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
                        if dist <= radius:
                            return True
                    except Exception:
                        continue
        
        return False
        
    except Exception:
        return True  # Conservative: assume collision on error

def validate_smooth_path_ENHANCED(smooth_path, obstacles, num_samples=300):
    """
    COMPREHENSIVE path validation with multiple sampling strategies.
    
    Args:
        smooth_path: Array of (x, y) points representing the smooth path
        obstacles: List of obstacle dictionaries
        num_samples: Number of regular samples to check
    
    Returns:
        True if path is collision-free, False if collision detected
    """
    try:
        if len(smooth_path) < 2:
            return True  # Empty path is technically valid
        
        # Strategy 1: Regular interval sampling (300 points)
        sample_indices = np.linspace(0, len(smooth_path) - 1, num_samples, dtype=int)
        
        for idx in sample_indices:
            point = smooth_path[idx]
            if check_point_collision(point, obstacles):
                logger.warning(f"Collision detected at sample {idx}: {point}")
                return False
        
        # Strategy 2: High-curvature detection
        # Sample more densely where the path curves sharply
        if len(smooth_path) > 20:
            # Calculate approximate curvature by angle change
            for i in range(1, len(smooth_path) - 1):
                prev = np.array(smooth_path[i-1])
                curr = np.array(smooth_path[i])
                next_pt = np.array(smooth_path[i+1])
                
                # Vectors
                v1 = curr - prev
                v2 = next_pt - curr
                
                # Check for sharp turns (potential collision zones)
                v1_norm = np.linalg.norm(v1)
                v2_norm = np.linalg.norm(v2)
                
                if v1_norm > 0 and v2_norm > 0:
                    cos_angle = np.dot(v1, v2) / (v1_norm * v2_norm)
                    
                    # If angle is sharp (cos < 0.7 means angle > 45°)
                    if cos_angle < 0.7:
                        # Extra dense sampling around this point
                        start_idx = max(0, i - 5)
                        end_idx = min(len(smooth_path), i + 6)
                        for j in range(start_idx, end_idx):
                            if check_point_collision(smooth_path[j], obstacles):
                                logger.warning(f"Collision at curve point {j}")
                                return False
        
        # Strategy 3: Midpoint sampling between regular samples
        for i in range(len(sample_indices) - 1):
            idx1 = sample_indices[i]
            idx2 = sample_indices[i+1]
            mid_idx = (idx1 + idx2) // 2
            
            if mid_idx > idx1 and mid_idx < idx2:
                if check_point_collision(smooth_path[mid_idx], obstacles):
                    logger.warning(f"Collision at midpoint {mid_idx}")
                    return False
        
        return True
        
    except Exception as e:
        logger.error(f"Error in enhanced path validation: {e}")
        return False

def validate_control_points_segments(control_points, obstacles, samples_per_segment=50):
    """
    Validate segments between adjacent control points.
    
    Args:
        control_points: Array of waypoint coordinates
        obstacles: List of obstacle dictionaries
        samples_per_segment: Number of points to check per segment
    
    Returns:
        True if all segments are collision-free, False otherwise
    """
    try:
        if len(control_points) < 2:
            return True
        
        # Check each pair of adjacent control points
        for i in range(len(control_points) - 1):
            p1 = np.array(control_points[i])
            p2 = np.array(control_points[i+1])
            
            # Dense sampling of the straight line segment
            for alpha in np.linspace(0, 1, samples_per_segment):
                test_point = p1 + alpha * (p2 - p1)
                if check_point_collision(test_point, obstacles):
                    logger.error(f"Collision detected in segment {i}-{i+1}")
                    return False
        
        return True
        
    except Exception as e:
        logger.error(f"Error validating control point segments: {e}")
        return False

def apply_path_smoothing_FIXED(pruned_path, obstacles=None):
    """
    Apply PSO-based path smoothing with COMPREHENSIVE multi-stage validation.
    
    Args:
        pruned_path: Pruned A* path as list of (x, y) tuples
        obstacles: List of obstacle dictionaries (should be inflated)
    
    Returns:
        Tuple of (smooth_waypoints, control_waypoints)
        Falls back to pruned_path if validation fails
    """
    try:
        if len(pruned_path) < 3:
            logger.warning(f"Path too short for smoothing ({len(pruned_path)} points).")
            return np.array(pruned_path), np.array(pruned_path)
        
        # Ensure obstacles are properly formatted
        obstacles_for_smoothing = obstacles if obstacles is not None else []
        
        # Convert to numpy
        way_points_array = np.array(pruned_path)
        way_points = [way_points_array]
        
        shortest_path_length = calculate_path_length(pruned_path)
        axes_objects = None
        
        logger.info("="*70)
        logger.info(f"STARTING PATH SMOOTHING")
        logger.info(f"  Input waypoints: {len(pruned_path)}")
        logger.info(f"  Pruned path length: {shortest_path_length:.2f}m")
        logger.info(f"  Obstacles for validation: {len(obstacles_for_smoothing)}")
        logger.info("="*70)
        
        # Apply PSO smoothing
        smooth_waypoints, control_waypoints = PathSmooting.smooth_path(
            way_points,
            shortest_path_length,
            axes_objects,
            obstacles_for_smoothing,
        )
        
        logger.info("\n" + "="*70)
        logger.info("VALIDATION STAGE 1: Control Points")
        logger.info("="*70)
        
        # VALIDATION STAGE 1: Control points validation
        for i, cp in enumerate(control_waypoints):
            if check_point_collision(cp, obstacles_for_smoothing):
                logger.error(f"❌ Control point {i} at {cp} is in collision!")
                logger.error("   Reverting to pruned A* path")
                return np.array(pruned_path), np.array(pruned_path)
        
        logger.info(f"✓ All {len(control_waypoints)} control points collision-free")
        
        logger.info("\n" + "="*70)
        logger.info("VALIDATION STAGE 2: Segments Between Control Points")
        logger.info("="*70)
        
        # VALIDATION STAGE 2: Segments between control points
        if not validate_control_points_segments(control_waypoints, obstacles_for_smoothing, samples_per_segment=50):
            logger.error("❌ Collision detected in segments between control points!")
            logger.error("   Reverting to pruned A* path")
            return np.array(pruned_path), np.array(pruned_path)
        
        logger.info(f"✓ All {len(control_waypoints)-1} segments collision-free")
        
        logger.info("\n" + "="*70)
        logger.info("VALIDATION STAGE 3: Final Smooth Path (Comprehensive)")
        logger.info("="*70)
        
        # VALIDATION STAGE 3: Final smooth path comprehensive check
        if not validate_smooth_path_ENHANCED(smooth_waypoints, obstacles_for_smoothing, num_samples=300):
            logger.error("❌ Final smooth path validation FAILED!")
            logger.error("   Collision detected in smooth spline")
            logger.error("   Reverting to pruned A* path")
            return np.array(pruned_path), np.array(pruned_path)
        
        logger.info(f"✓ Smooth path validated with 300+ sample points")
        
        logger.info("\n" + "="*70)
        logger.info("VALIDATION STAGE 4: Path Length Sanity Check")
        logger.info("="*70)
        
        # VALIDATION STAGE 4: Path length sanity check
        smooth_length = calculate_path_length(smooth_waypoints)
        pruned_length = calculate_path_length(pruned_path)
        
        length_ratio = smooth_length / pruned_length if pruned_length > 0 else float('inf')
        
        logger.info(f"  Smooth path length: {smooth_length:.2f}m")
        logger.info(f"  Pruned path length: {pruned_length:.2f}m")
        logger.info(f"  Length ratio: {length_ratio:.2f}x")
        
        if smooth_length > pruned_length * 1.5:
            logger.warning(f"❌ Smooth path too long ({smooth_length:.2f}m vs {pruned_length:.2f}m)")
            logger.warning(f"   Ratio {length_ratio:.2f}x exceeds 1.5x threshold")
            logger.warning("   Using pruned A* path instead")
            return np.array(pruned_path), np.array(pruned_path)
        
        logger.info(f"✓ Path length acceptable (ratio: {length_ratio:.2f}x < 1.5x)")
        
        logger.info("\n" + "="*70)
        logger.info("✓✓✓ PATH SMOOTHING SUCCESSFUL ✓✓✓")
        logger.info(f"  Final smooth points: {len(smooth_waypoints)}")
        logger.info(f"  Control points: {len(control_waypoints)}")
        logger.info(f"  Path length: {smooth_length:.2f}m")
        logger.info(f"  Improvement: {((pruned_length - smooth_length) / pruned_length * 100):.1f}% shorter")
        logger.info("="*70 + "\n")
        
        return smooth_waypoints, control_waypoints
        
    except Exception as e:
        logger.error("="*70)
        logger.error(f"❌ EXCEPTION in path smoothing: {e}")
        logger.error("="*70)
        import traceback
        logger.error(traceback.format_exc())
        logger.error("Falling back to pruned A* path")
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

@app.route("/.well-known/agent.json", methods=["GET"])
def agent_card():
    logger.info("Handling request for /.well-known/agent.json")
    return jsonify({
        "name": "PathPlannerAgent",
        "description": "Handles path planning, map management, and PCD processing for navigation.",
        # --- CORRECTED LINE BELOW ---
        "url": "https://autonomous-robot-2b4c4.web.app", 
        # --- CORRECTED LINE ABOVE ---
        "version": "1.0",
        "capabilities": {
            "streaming": False,
            "pushNotifications": False
        }
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
            # A* Path Planning WITH Path Smoothing
            start, goal, obstacles, boundary, ref_lat, ref_lon = process_request_data(params_data)
            
            logger.info("\n" + "="*70)
            logger.info("OBSTACLE INFLATION")
            logger.info("="*70)
            
            # Apply safety inflation
            inflated_obstacles = helper_DPR_obj.strching_obstacles(obstacles)
            
            logger.info(f"Original obstacles: {len(obstacles)}")
            logger.info(f"Inflated obstacles: {len(inflated_obstacles)}")
            
            # Run A* with inflated obstacles
            logger.info("\n" + "="*70)
            logger.info("A* PATH PLANNING")
            logger.info("="*70)
            logger.info(f"Start: {start}")
            logger.info(f"Goal: {goal}")
            
            planner = AStarPlanner(start=start, goal=goal, obstacles=inflated_obstacles, boundary=boundary)
            path, pruned_path = planner.planning()
            
            if not path:
                logger.error("No path found by A*!")
                return jsonify({"error": "No path found"}), 404
            
            logger.info(f"✓ A* found path: {len(path)} points → {len(pruned_path)} pruned points")
            
            # Check if smoothing should be enabled (can disable via params)
            enable_smoothing = params_data.get("enable_smoothing", True)
            
            if enable_smoothing and len(pruned_path) >= 3:
                # Apply smoothing with strict validation
                logger.info("\n" + "="*70)
                logger.info("APPLYING PATH SMOOTHING WITH MULTI-STAGE VALIDATION")
                logger.info("="*70)
                
                smooth_waypoints, control_waypoints = apply_path_smoothing_FIXED(
                    pruned_path, 
                    inflated_obstacles
                )
                
            else:
                logger.info("\n" + "="*70)
                logger.info("PATH SMOOTHING DISABLED OR PATH TOO SHORT")
                logger.info("="*70)
                logger.info(f"Enable smoothing: {enable_smoothing}")
                logger.info(f"Path length: {len(pruned_path)}")
                
                smooth_waypoints = np.array(pruned_path)
                control_waypoints = np.array(pruned_path)
            
            # Convert to lat/lng
            path_latlng = [{'latitude': lat, 'longitude': lon} for lat, lon in 
                          [meters_to_latlng1(p[0], p[1], ref_lat, ref_lon) for p in path]]
            
            pruned_path_latlng = [{'latitude': lat, 'longitude': lon} for lat, lon in 
                                 [meters_to_latlng1(p[0], p[1], ref_lat, ref_lon) for p in pruned_path]]
            
            smooth_path_latlng = [{'latitude': lat, 'longitude': lon} for lat, lon in 
                                 [meters_to_latlng1(p[0], p[1], ref_lat, ref_lon) for p in smooth_waypoints]]
            
            control_path_latlng = [{'latitude': lat, 'longitude': lon} for lat, lon in 
                                  [meters_to_latlng1(p[0], p[1], ref_lat, ref_lon) for p in control_waypoints]]
            
            response_data = {
                "path": path_latlng,
                "pruned_path": pruned_path_latlng,
                "smooth_path": smooth_path_latlng,
                "control_path": control_path_latlng
            }
            
            logger.info("\n" + "="*70)
            logger.info("PATH PLANNING COMPLETE")
            logger.info(f"  Full path: {len(path_latlng)} points")
            logger.info(f"  Pruned path: {len(pruned_path_latlng)} points")
            logger.info(f"  Smooth path: {len(smooth_path_latlng)} points")
            logger.info(f"  Control points: {len(control_path_latlng)} points")
            logger.info("="*70 + "\n")

        elif operation == "plan-path-dp":
            name = params_data.get("name", "temp")
            start, goal, obstacles, boundary, ref_lat, ref_lon = process_request_data(params_data)
            decomposition_dir = os.path.join("saved_maps", name, "decomposition") if name != "temp" else "decomposition_temp"
            os.makedirs(decomposition_dir, exist_ok=True)
            planner = DynamicProgrammingPlanner(start=start, goal=goal, obstacles=obstacles, boundary=boundary, decomposition_dir=decomposition_dir)
            path, pruned_path = planner.planning()
            if not path:
                return jsonify({"error": "No path found"}), 404
            path_latlng = [{'latitude': lat, 'longitude': lon} for lat, lon in [meters_to_latlng1(p[0], p[1], ref_lat, ref_lon) for p in path]]
            pruned_path_latlng = [{'latitude': lat, 'longitude': lon} for lat, lon in [meters_to_latlng1(p[0], p[1], ref_lat, ref_lon) for p in pruned_path]]
            response_data = {"path": path_latlng, "pruned_path": pruned_path_latlng}

        elif operation == "get-grid":
            # NEW OPERATION FOR GETTING GRID DATA
            name = params_data.get("name", "temp")
            start, goal, obstacles, boundary, ref_lat, ref_lon = process_request_data(params_data)
            decomposition_dir = os.path.join("saved_maps", name, "decomposition") if name != "temp" else "decomposition_temp"
            
            # Check if decomposition exists
            if not os.path.exists(decomposition_dir):
                return jsonify({"error": "No decomposition found. Please run path planning first."}), 404
            
            planner = DynamicProgrammingPlanner(start=start, goal=goal, obstacles=obstacles, boundary=boundary, decomposition_dir=decomposition_dir)
            grid_data = planner.get_grid_data()
            
            # Convert cell bounds to lat/lng
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
            
            response_data = {
                'cells': cells_latlng,
                'total_cells': grid_data['total_cells']
            }

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
            DynamicProgrammingPlanner(dummy_start, dummy_goal, obstacles, boundary, decomposition_dir=decomposition_dir)
            response_data = {"success": True}

        elif operation == "load-map":
            name = params_data.get("name")
            map_dir = os.path.join("saved_maps", name)
            json_path = os.path.join(map_dir, f"{name}.json")
            if not os.path.exists(json_path):
                return jsonify({"error": "Map not found"}), 404
            with open(json_path, "r") as f:
                response_data = json.load(f)

        elif operation == "list-maps":
            if not os.path.exists("saved_maps"):
                response_data = []
            else:
                response_data = [d for d in os.listdir("saved_maps") if os.path.isdir(os.path.join("saved_maps", d))]
            logger.info(f"list-maps response: {response_data}")

        elif operation == "delete-map":
            name = params_data.get("name")
            map_dir = os.path.join("saved_maps", name)
            if not os.path.exists(map_dir):
                return jsonify({"error": "Map not found"}), 404
            shutil.rmtree(map_dir)
            response_data = {"success": True}

        else:
            return jsonify({"error": f"Unknown operation: {operation}"}), 400

    except ValueError as e:
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        logger.error(f"Error processing task {operation}: {e}", exc_info=True)
        return jsonify({"error": f"An error occurred during task {operation}."}), 500

    return jsonify({
        "id": task_id,
        "status": {"state": "completed"},
        "messages": [
            task["message"],
            {
                "role": "agent",
                "parts": [{"text": json.dumps(response_data)}]
            }
        ]
    }), status_code

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
        logger.info(f"Loaded PCD file: {pcd_path}")
        pcd = o3d.io.read_point_cloud(pcd_path)
        if pcd.is_empty():
            raise ValueError(f"PCD file {pcd_path} contains no points or is invalid.")
        PCD_PROCESSING_RESOLUTION = 0.005
        pcd = pcd.voxel_down_sample(voxel_size=PCD_PROCESSING_RESOLUTION)
        points_3d = np.asarray(pcd.points)
        if points_3d.size == 0:
            raise ValueError("No valid points remain after downsampling.")
        logger.info(f"Number of points after downsampling: {points_3d.shape[0]}")
        plane_model, inliers = pcd.segment_plane(distance_threshold=0.01, ransac_n=3, num_iterations=1000)
        inlier_cloud = pcd.select_by_index(inliers)
        outlier_cloud = pcd.select_by_index(inliers, invert=True)
        points_3d_filtered = np.asarray(outlier_cloud.points)
        if points_3d_filtered.size == 0:
            logger.info("No points remain after RANSAC ground plane removal.")
            points_2d = np.array([]).reshape(0, 2)
        else:
            z_range = (0.1, 2.0)
            filtered_points = points_3d_filtered[(points_3d_filtered[:, 2] > z_range[0]) & (points_3d_filtered[:, 2] <= z_range[1])]
            if filtered_points.size == 0:
                logger.info("No points remain after z-range filtering.")
                points_2d = np.array([]).reshape(0, 2)
            else:
                points_2d = filtered_points[:, :2]
        logger.info(f"Number of points after RANSAC and z-range filtering: {points_2d.shape[0] if points_2d.size > 0 else 0}")
        obstacles: List[Dict[str, Any]] = []
        all_points_2d = points_3d[:, :2]
        if all_points_2d.size == 0:
            raise ValueError("PCD file is empty.")
        min_x_overall, min_y_overall = all_points_2d.min(axis=0)
        max_x_overall, max_y_overall = all_points_2d.max(axis=0)
        if points_2d.size > 0:
            min_x_grid, min_y_grid = points_2d.min(axis=0)
            max_x_grid, max_y_grid = points_2d.max(axis=0)
            width = int((max_x_grid - min_x_grid) / PCD_PROCESSING_RESOLUTION) + 1
            height = int((max_y_grid - min_y_grid) / PCD_PROCESSING_RESOLUTION) + 1
            if width <= 0 or height <= 0:
                logger.warning("Invalid grid dimensions for obstacles.")
            else:
                grid = np.zeros((height, width), dtype=np.uint8)
                for pt in points_2d:
                    ix = int((pt[0] - min_x_grid) / PCD_PROCESSING_RESOLUTION)
                    iy = int((pt[1] - min_y_grid) / PCD_PROCESSING_RESOLUTION)
                    if 0 <= ix < width and 0 <= iy < height:
                        grid[iy, ix] = 255
                kernel = np.ones((6, 6), np.uint8)
                grid = cv2.dilate(grid, kernel, iterations=3)
                grid_image_path = os.path.join(map_dir, f"{name}_grid.png")
                cv2.imwrite(grid_image_path, grid)
                logger.info(f"Saved 2D grid image: {grid_image_path}")
                contours, _ = cv2.findContours(grid, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
                for contour in contours:
                    if cv2.contourArea(contour) < 5:
                        continue
                    approx = cv2.approxPolyDP(contour, 0.3, True)
                    hull_points_latlng = []
                    for p in approx.squeeze(axis=1):
                        pixel_x, pixel_y = p[0], p[1]
                        meter_x = min_x_grid + pixel_x * PCD_PROCESSING_RESOLUTION
                        meter_y = min_y_grid + pixel_y * PCD_PROCESSING_RESOLUTION
                        lat, lon = meters_to_latlng(meter_x, meter_y, ref_lat, ref_lon)
                        hull_points_latlng.append({"latitude": lat, "longitude": lon})
                    if len(hull_points_latlng) >= 3:
                        area = cv2.contourArea(contour)
                        object_type = "wall" if area > 20 else "door"
                        obstacles.append({"type": "polygon", "object_type": object_type, "points": hull_points_latlng})
        else:
            logger.info("No significant obstacles detected after RANSAC and z-range filtering.")
        boundary_points_m = [
            (min_x_overall, min_y_overall),
            (max_x_overall, min_y_overall),
            (max_x_overall, max_y_overall),
            (min_x_overall, max_y_overall)
        ]
        boundary = {
            "type": "polygon",
            "points": [
                {"latitude": lat, "longitude": lon}
                for lat, lon in [meters_to_latlng(x, y, ref_lat, ref_lon) for x, y in boundary_points_m]
            ]
        }
        map_data = {
            "name": name,
            "boundary": boundary,
            "obstacles": obstacles,
            "start": None,
            "goal": None
        }
        json_path = os.path.join(map_dir, f"{name}.json")
        with open(json_path, "w") as f:
            json.dump(map_data, f)
        try:
            dummy_start_m = (min_x_overall, min_y_overall)
            dummy_goal_m = (max_x_overall, max_y_overall)
            map_data["start"] = {
                "latitude": meters_to_latlng1(dummy_start_m[0], dummy_start_m[1], ref_lat, ref_lon)[0],
                "longitude": meters_to_latlng1(dummy_start_m[0], dummy_start_m[1], ref_lat, ref_lon)[1]
            }
            map_data["goal"] = {
                "latitude": meters_to_latlng1(dummy_goal_m[0], dummy_goal_m[1], ref_lat, ref_lon)[0],
                "longitude": meters_to_latlng1(dummy_goal_m[0], dummy_goal_m[1], ref_lat, ref_lon)[1]
            }
            _, _, obstacles_processed, boundary_processed, _, _ = process_request_data(map_data)
            decomposition_dir = os.path.join(map_dir, "decomposition")
            os.makedirs(decomposition_dir, exist_ok=True)
            DynamicProgrammingPlanner(dummy_start_m, dummy_goal_m, obstacles_processed, boundary_processed, decomposition_dir=decomposition_dir)
            logger.info(f"Precomputed DP decomposition for PCD map: {name}")
        except Exception as e:
            logger.warning(f"Failed to precompute DP for PCD: {e}")
        response_data = {"boundary": boundary, "obstacles": obstacles}
        return jsonify({
            "id": request.form.get("task_id", "unknown"),
            "status": {"state": "completed"},
            "messages": [
                {
                    "role": "user",
                    "parts": [
                        {"text": "upload-pcd"},
                        {"text": json.dumps({"name": name, "ref_lat": ref_lat, "ref_lon": ref_lon})}
                    ]
                },
                {
                    "role": "agent",
                    "parts": [{"text": json.dumps(response_data)}]
                }
            ]
        })
    except ValueError as e:
        logger.error(f"ValueError in upload-pcd: {e}")
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        logger.error(f"Unexpected error in upload-pcd: {e}", exc_info=True)
        return jsonify({"error": "An unexpected error occurred during PCD processing."}), 500

if __name__ == "__main__":
    startup_logging()
    app.run(debug=True)