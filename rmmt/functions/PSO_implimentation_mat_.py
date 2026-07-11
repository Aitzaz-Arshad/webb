from numpy import random
from helper_data_prepration_planner_random import *
from obstacle_list import obstacles_list 
import numpy as np
from copy import copy, deepcopy
from scipy.interpolate import CubicSpline


class PsoOptimizer:

    def __init__(self, waypoints, ShortestPathLenght, boundryCondition, nVar, ax, obstacles):
        """
        Initializes the PSO algorithm for path smoothing.
        CONSERVATIVE approach: Keep waypoints VERY close to original A* path
        """
        self.nVar = nVar
        self.VarSize = [1, nVar]
        self.VarMinX = boundryCondition[0]
        self.VarMaxX = boundryCondition[1]
        self.VarMinY = boundryCondition[2]
        self.VarMaxY = boundryCondition[3]
        
        self.obstacles = obstacles
        
        if ax is not None:
            ax[1, 1].plot(
                [self.VarMinX, self.VarMaxX, self.VarMaxX, self.VarMinX, self.VarMinX],
                [self.VarMinY, self.VarMinY, self.VarMaxY, self.VarMaxY, self.VarMinY],
                "-b",
                linewidth=0.5,
                label="Local area to define swarm particles",
            )
            ax[2, 0].plot(
                [self.VarMinX, self.VarMaxX, self.VarMaxX, self.VarMinX, self.VarMinX],
                [self.VarMinY, self.VarMinY, self.VarMaxY, self.VarMaxY, self.VarMinY],
                "-b",
                linewidth=0.5,
                label="Local area to define swarm particles",
            )

        self.waypoints = waypoints
        self.ShortestPathLenght = ShortestPathLenght
        self.resolution = ROBOT_BIGGEST_DIMENTION

        # Conservative PSO parameters - favor stability over exploration
        self.MaxIt = 20  
        self.nPop = 100  
        self.w = 0.4      # Low inertia
        self.wdamp = 0.99 
        self.c1 = 2.5     # Strong personal best
        self.c2 = 0.5     # Weak global best (avoid premature convergence)

        # High collision penalty
        self.COLLISION_PENALTY = 1e12

        # Initialize particles
        self.particles = []
        for i in range(self.nPop):
            self.particles.append({
                "Position": [0.0, 0.0],
                "Velocity": [0.0, 0.0],
                "Cost": np.inf,
                "Curvature_Cost": np.inf,
                "ParticalBest": {
                    "Position": [0.0, 0.0],
                    "Cost": np.inf,
                    "Curvature_Cost": np.inf,
                }
            })

        self.GlobalBest = {
            "Position": [0.0, 0.0],
            "Cost": np.inf,
            "Curvature_Cost": np.inf,
        }

        # CRITICAL: Initialize particles in a TINY radius around the A* waypoint
        initial_position = waypoints[1]
        
        # Calculate appropriate search radius based on local geometry
        dist_to_prev = np.linalg.norm(waypoints[1] - waypoints[0])
        dist_to_next = np.linalg.norm(waypoints[2] - waypoints[1])
        min_dist = min(dist_to_prev, dist_to_next)
        
        # Search radius: at most 20% of the minimum distance to neighbors, max 1 meter
        search_radius = min(min_dist * 0.2, 1.0, 
                           (self.VarMaxX - self.VarMinX) * 0.02,
                           (self.VarMaxY - self.VarMinY) * 0.02)
        
        print(f"PSO Search radius: {search_radius:.3f}m (segment lengths: {dist_to_prev:.2f}m, {dist_to_next:.2f}m)")
        
        # Initialize particles with most staying exactly on the path
        for j in range(self.nPop):
            if j < self.nPop * 0.8:  # 80% stay exactly on A* path
                offset_x = 0.0
                offset_y = 0.0
            else:  # 20% with minimal Gaussian noise
                offset_x = np.random.normal(0, search_radius/4)
                offset_y = np.random.normal(0, search_radius/4)
            
            pos_x = float(initial_position[0] + offset_x)
            pos_y = float(initial_position[1] + offset_y)
            
            pos_x = float(np.clip(pos_x, self.VarMinX + 0.01, self.VarMaxX - 0.01))
            pos_y = float(np.clip(pos_y, self.VarMinY + 0.01, self.VarMaxY - 0.01))
            
            self.particles[j]["Position"] = [pos_x, pos_y]
            self.particles[j]["Velocity"] = [0.0, 0.0]
            
            if ax is not None:
                ax[2, 0].plot(pos_x, pos_y, ".r", markersize=2)

        # Initialize costs
        initial_cost = helper_DPR_obj.lengthPath(
            self.waypoints[:, 0], 
            self.waypoints[:, 1]
        )

        for j in range(self.nPop):
            if self.check_point_in_obstacle(self.particles[j]["Position"]):
                self.particles[j]["Cost"] = self.COLLISION_PENALTY
            else:
                self.particles[j]["Cost"] = initial_cost
                
            self.particles[j]["ParticalBest"]["Position"] = [
                self.particles[j]["Position"][0],
                self.particles[j]["Position"][1]
            ]
            self.particles[j]["ParticalBest"]["Cost"] = self.particles[j]["Cost"]

            if j == 0 or (
                self.particles[j]["ParticalBest"]["Cost"] < self.GlobalBest["Cost"]
                and self.particles[j]["ParticalBest"]["Cost"] < self.COLLISION_PENALTY
            ):
                self.GlobalBest = {
                    "Position": [
                        self.particles[j]["ParticalBest"]["Position"][0],
                        self.particles[j]["ParticalBest"]["Position"][1]
                    ],
                    "Cost": self.particles[j]["ParticalBest"]["Cost"],
                    "Curvature_Cost": self.particles[j]["ParticalBest"]["Curvature_Cost"]
                }

        self.BestCost = np.zeros((self.MaxIt, 1))

    def check_point_in_obstacle(self, point):
        """Check if a point collides with any obstacle."""
        try:
            arr = np.asarray(point).reshape(-1)
        except Exception:
            return False

        if arr.size >= 2:
            x, y = float(arr[0]), float(arr[1])
        else:
            return False

        for obs in (self.obstacles or []):
            if obs.get('type') == "rectangle" or obs.get('type') == "polygon":
                try:
                    if helper_DPR_obj.pointInObstacleListRect((x, y), [np.array(obs["points"])]):
                        return True
                except Exception:
                    continue

            elif obs.get('type') == "circle":
                center = obs.get("center")
                radius = obs.get("radius")
                if center is None or radius is None:
                    continue
                try:
                    cx, cy = float(center[0]), float(center[1])
                except Exception:
                    continue
                dist = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
                if dist <= radius:
                    return True

        return False

    def check_segment_collision(self, p1, p2, num_samples=30):
        """Check collision along a straight line segment"""
        try:
            p1 = np.array(p1)
            p2 = np.array(p2)
            
            for alpha in np.linspace(0, 1, num_samples):
                point = p1 + alpha * (p2 - p1)
                if self.check_point_in_obstacle(point):
                    return True
            return False
        except Exception:
            return True

    def check_spline_segment_collision(self, waypoints, num_samples=100):
        """
        ENHANCED: Check collision on the ACTUAL cubic spline between waypoints.
        This validates the real smooth curve, not just straight line segments.
        """
        try:
            # Generate the smooth spline
            smooth_waypoints, _ = helper_DPR_obj.smoothPathLength(waypoints)
            
            if len(smooth_waypoints) < 2:
                return True  # Failed to generate spline, assume collision
            
            # Dense sampling of the spline curve
            sample_step = max(1, len(smooth_waypoints) // num_samples)
            
            for i in range(0, len(smooth_waypoints), sample_step):
                point = smooth_waypoints[i]
                if self.check_point_in_obstacle(point):
                    return True
            
            # Always check the last point
            if self.check_point_in_obstacle(smooth_waypoints[-1]):
                return True
            
            return False
            
        except Exception as e:
            print(f"Error in spline collision check: {e}")
            return True  # Conservative: assume collision on error

    def check_smooth_curve_collision(self, waypoints, num_samples=50):
        """
        DEPRECATED: Use check_spline_segment_collision instead.
        Keeping for backward compatibility.
        """
        return self.check_spline_segment_collision(waypoints, num_samples)

    def enhanced_final_validation(self, final_waypoints, num_samples=200):
        """
        ULTIMATE VALIDATION: Multi-stage check of the final smooth path.
        
        Args:
            final_waypoints: The waypoints to validate
            num_samples: Number of points to sample for collision checking
        
        Returns:
            True if path is collision-free, False otherwise
        """
        try:
            # Stage 1: Generate the final smooth spline
            smooth_path, _ = helper_DPR_obj.smoothPathLength(final_waypoints)
            
            if len(smooth_path) < 2:
                return False
            
            # Stage 2: Dense sampling (200+ points for safety)
            sample_indices = np.linspace(0, len(smooth_path) - 1, num_samples, dtype=int)
            
            for idx in sample_indices:
                if self.check_point_in_obstacle(smooth_path[idx]):
                    return False
            
            # Stage 3: Check for sharp curves that might clip obstacles
            # Sample at maximum curvature points (derivatives)
            if len(smooth_path) > 10:
                # Check midpoints between samples for extra safety
                for i in range(len(sample_indices) - 1):
                    mid_idx = (sample_indices[i] + sample_indices[i+1]) // 2
                    if mid_idx < len(smooth_path) and mid_idx > sample_indices[i]:
                        if self.check_point_in_obstacle(smooth_path[mid_idx]):
                            return False
            
            return True
            
        except Exception as e:
            print(f"Final validation error: {e}")
            return False

    def optimization_smooth_path(self, wayPoints, ax):
        """
        PSO optimization with ENHANCED collision detection using spline validation.
        """
        BestCosts = []
        original_waypoint = wayPoints[1].copy()
        
        for it in range(self.MaxIt):
            for part in range(self.nPop):
                curr_vel_x = float(self.particles[part]["Velocity"][0])
                curr_vel_y = float(self.particles[part]["Velocity"][1])
                curr_pos_x = float(self.particles[part]["Position"][0])
                curr_pos_y = float(self.particles[part]["Position"][1])
                pbest_x = float(self.particles[part]["ParticalBest"]["Position"][0])
                pbest_y = float(self.particles[part]["ParticalBest"]["Position"][1])
                gbest_x = float(self.GlobalBest["Position"][0])
                gbest_y = float(self.GlobalBest["Position"][1])
                
                # Update velocity
                inertia_x = self.w * curr_vel_x
                inertia_y = self.w * curr_vel_y
                
                r1 = np.random.uniform()
                r2 = np.random.uniform()
                
                cognitive_x = self.c1 * r1 * (pbest_x - curr_pos_x)
                cognitive_y = self.c1 * r1 * (pbest_y - curr_pos_y)
                
                social_x = self.c2 * r2 * (gbest_x - curr_pos_x)
                social_y = self.c2 * r2 * (gbest_y - curr_pos_y)
                
                new_vel_x = inertia_x + cognitive_x + social_x
                new_vel_y = inertia_y + cognitive_y + social_y
                
                # VERY restrictive velocity limits
                max_velocity = 0.2  # Only 20cm per iteration
                new_vel_x = float(np.clip(new_vel_x, -max_velocity, max_velocity))
                new_vel_y = float(np.clip(new_vel_y, -max_velocity, max_velocity))
                
                self.particles[part]["Velocity"] = [new_vel_x, new_vel_y]
                
                # Update position
                new_pos_x = curr_pos_x + new_vel_x
                new_pos_y = curr_pos_y + new_vel_y
                
                new_pos_x = float(np.clip(new_pos_x, self.VarMinX, self.VarMaxX))
                new_pos_y = float(np.clip(new_pos_y, self.VarMinY, self.VarMaxY))
                
                self.particles[part]["Position"] = [new_pos_x, new_pos_y]
                
                # Create test waypoints
                tempWayPoints = np.array(wayPoints, dtype=np.float64)
                tempWayPoints[1] = np.array([new_pos_x, new_pos_y])
                
                tempWayPoints, flip = helper_DPR_obj.XstriclyIncreasingOrder(tempWayPoints)

                # ENHANCED THREE-STAGE COLLISION DETECTION
                collision_detected = False
                
                # Stage 1: Point collision
                if self.check_point_in_obstacle([new_pos_x, new_pos_y]):
                    collision_detected = True
                
                # Stage 2: Segment collision (straight lines to neighbors)
                if not collision_detected:
                    if self.check_segment_collision(tempWayPoints[0], tempWayPoints[1], 30):
                        collision_detected = True
                    elif self.check_segment_collision(tempWayPoints[1], tempWayPoints[2], 30):
                        collision_detected = True
                
                # Stage 3: CRITICAL - Check the ACTUAL spline curve
                if not collision_detected:
                    if self.check_spline_segment_collision(tempWayPoints, num_samples=100):
                        collision_detected = True
                
                # Assign cost
                if collision_detected:
                    self.particles[part]["Cost"] = self.COLLISION_PENALTY
                else:
                    try:
                        smoothWayPoints, smothWayPointsLenght = helper_DPR_obj.smoothPathLength(
                            tempWayPoints
                        )
                        self.particles[part]["Cost"] = smothWayPointsLenght
                            
                    except Exception as e:
                        self.particles[part]["Cost"] = self.COLLISION_PENALTY
                
                # Update personal best
                if (
                    self.particles[part]["Cost"] < self.particles[part]["ParticalBest"]["Cost"]
                    and self.particles[part]["Cost"] < self.COLLISION_PENALTY
                ):
                    self.particles[part]["ParticalBest"]["Position"] = [new_pos_x, new_pos_y]
                    self.particles[part]["ParticalBest"]["Cost"] = self.particles[part]["Cost"]
                    
                    # Update global best
                    if self.particles[part]["ParticalBest"]["Cost"] < self.GlobalBest["Cost"]:
                        self.GlobalBest = {
                            "Position": [new_pos_x, new_pos_y],
                            "Cost": self.particles[part]["ParticalBest"]["Cost"],
                            "Curvature_Cost": self.particles[part]["ParticalBest"]["Curvature_Cost"]
                        }

            # Dampen inertia
            self.w = self.w * self.wdamp
            
            BestCosts.append(self.GlobalBest["Cost"])
            
            if it % 5 == 0:
                print(f"  Iteration {it}: Best Cost = {BestCosts[it]:.4f}")
            
            # Early stopping
            if it > 8 and len(BestCosts) > 4:
                recent = BestCosts[-4:]
                if max(recent) - min(recent) < 0.01:
                    print(f"  Converged at iteration {it}")
                    break
        
        if ax is not None:
            ax[2, 0].plot(
                self.GlobalBest["Position"][0],
                self.GlobalBest["Position"][1],
                "ob",
                markersize=8,
                label="Best Particle",
            )

        # FINAL VALIDATION before returning
        tempWayPoints = np.array(wayPoints, dtype=np.float64)
        
        if self.GlobalBest["Cost"] >= self.COLLISION_PENALTY:
            print(f"  WARNING: No collision-free solution found. Keeping original waypoint.")
            tempWayPoints[1] = original_waypoint
        else:
            tempWayPoints[1] = np.array(self.GlobalBest["Position"])
            
            # CRITICAL: Final comprehensive check with enhanced validation
            tempWayPoints_check, _ = helper_DPR_obj.XstriclyIncreasingOrder(tempWayPoints)
            if not self.enhanced_final_validation(tempWayPoints_check, num_samples=200):
                print(f"  WARNING: Final validation failed! Using original waypoint.")
                tempWayPoints[1] = original_waypoint
        
        return tempWayPoints