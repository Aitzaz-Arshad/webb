# 2D Obstacle Mapping from Point Cloud Data (PCD)

[![ROS2](https://img.shields.io/badge/ROS2-Humble%20%7C%20Iron%20%7C%20Foxy-blue)](https://docs.ros.org/en/humble/index.html)
[![Gazebo](https://img.shields.io/badge/Gazebo-11%20Classic-orange)](https://classic.gazebosim.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **Perfect for Nav2 testing, simulation validation, and rapid map prototyping.**

---

## 📋 Complete Workflow: From Gazebo World to 2D Obstacle Map

This project provides a complete pipeline that starts with **Gazebo simulation environments** and ends with **ready-to-use 2D obstacle maps** for robot navigation. Here's how the entire process works:

### Step 1: Generate 3D Point Cloud from Gazebo World

First, we use the **[gazebo_map_creator](https://github.com/arshadlab/gazebo_map_creator)** tool to extract 3D point cloud data directly from your Gazebo simulation:

```bash
# Terminal A: Start Gazebo with your world
source ./install/setup.bash
gazebo -s libgazebo_map_creator.so myworld.world

# Terminal B: Generate 3D point cloud map
source ./install/setup.bash
ros2 run gazebo_map_creator request_map.py \
  -c '(-4.8,-4.5,0.03)(4.8,4.5,8.0)' \  # Capture area coordinates
  -r 0.01 \                             # Resolution (10mm)
  -f $PWD/map                           # Output filename

# Results: map.pcd (3D point cloud) + map.pgm (2D occupancy grid)
```

**What happens during 3D map generation:**
- Gazebo plugin captures all visible surfaces in the specified volume
- Creates a dense 3D point cloud with (x,y,z) coordinates for every surface point
- Outputs `map.pcd` file containing the complete 3D environment data

### Step 2: Convert 3D Point Cloud to 2D Obstacle Map

Now we process the generated `map.pcd` file through our 2D mapping pipeline:

##  Overview

When working with robot navigation in ROS2 and Gazebo, we often need 2D maps for path planning algorithms like Nav2. While SLAM is commonly used, this tool provides a direct way to generate 2D obstacle maps from existing 3D point cloud data.

##  How It Works: The Complete Pipeline

### 1. **Input: 3D Point Cloud Data**
- Starts with a `.pcd` file generated from Gazebo using `gazebo_map_creator`
- Each point has (x, y, z) coordinates representing surfaces in the 3D world
- Contains millions of points capturing walls, floors, furniture, and other objects

### 2. **Point Cloud Preprocessing**
```python
# Reduce data density for efficient processing
PCD_PROCESSING_RESOLUTION = 0.005  # 5mm grid
pcd = pcd.voxel_down_sample(voxel_size=PCD_PROCESSING_RESOLUTION)
```
- **Voxel Downsampling**: Reduces point density while preserving structure
- Creates a uniform point distribution for consistent processing
- Typical reduction: 1M+ points → 50K-100K points

### 3. **Ground Plane Removal**
```python
# Separate ground from obstacles using RANSAC algorithm
plane_model, inliers = pcd.segment_plane(
    distance_threshold=0.01, 
    ransac_n=3, 
    num_iterations=1000
)
outlier_cloud = pcd.select_by_index(inliers, invert=True)
```

**RANSAC Algorithm Explained:**
- **Random Sample Consensus**: Finds the largest flat surface (usually the ground)
- **How it works**:
  1. Randomly picks 3 points to form a plane hypothesis
  2. Checks how many other points fit this plane (within 1cm distance)
  3. Repeats 1000 times to find the best-fitting plane
  4. Removes ground points, keeping only obstacles
- **Result**: Only navigation-relevant obstacles remain

### 4. **Height Filtering**
```python
z_range = (0.1, 2.0)  # Keep obstacles between 10cm and 2m height
filtered_points = points_3d_filtered[
    (points_3d_filtered[:, 2] > z_range[0]) & 
    (points_3d_filtered[:, 2] <= z_range[1])
]
```
- **Why this matters**:
  - Removes very low objects (≤10cm) that robots can drive over
  - Removes very high objects (≥2m) that don't affect ground navigation
  - Focuses on obstacles that actually matter for robot movement

### 5. **2D Projection**
```python
points_2d = filtered_points[:, :2]  # Drop Z coordinate
```
- Converts 3D points to 2D by ignoring height information
- Creates a top-down view of obstacles
- Essential for 2D navigation planners like Nav2

### 6. **Grid Map Creation**
```python
# Create a 2D grid where each cell is 5mm x 5mm
width = int((max_x_grid - min_x_grid) / PCD_PROCESSING_RESOLUTION) + 1
height = int((max_y_grid - min_y_grid) / PCD_PROCESSING_RESOLUTION) + 1
grid = np.zeros((height, width), dtype=np.uint8)

# Mark obstacle cells
for pt in points_2d:
    ix = int((pt[0] - min_x_grid) / PCD_PROCESSING_RESOLUTION)
    iy = int((pt[1] - min_y_grid) / PCD_PROCESSING_RESOLUTION)
    if 0 <= ix < width and 0 <= iy < height:
        grid[iy, ix] = 255  # Mark as occupied
```

### 7. **Obstacle Enhancement**
```python
kernel = np.ones((6, 6), np.uint8)
grid = cv2.dilate(grid, kernel, iterations=3)
```
- **Morphological Dilation**: Expands obstacle boundaries
- **Purpose**: 
  - Fills small gaps in detected obstacles
  - Creates safety margins around obstacles (important for robot clearance)
  - Makes obstacle boundaries more continuous for better path planning

### 8. **Contour Detection & Polygon Extraction**
```python
contours, _ = cv2.findContours(grid, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
for contour in contours:
    if cv2.contourArea(contour) < 5:  # Ignore very small obstacles
        continue
    approx = cv2.approxPolyDP(contour, 0.3, True)  # Simplify polygon
```

**Contour Processing:**
- **findContours**: Detects closed shapes in the binary grid
- **approxPolyDP**: Simplifies complex shapes into polygons with fewer points
- **Area Filtering**: Removes noise and small irrelevant objects

### 9. **Coordinate Conversion**
```python
for p in approx.squeeze(axis=1):
    pixel_x, pixel_y = p[0], p[1]
    meter_x = min_x_grid + pixel_x * PCD_PROCESSING_RESOLUTION
    meter_y = min_y_grid + pixel_y * PCD_PROCESSING_RESOLUTION
    lat, lon = meters_to_latlng(meter_x, meter_y, ref_lat, ref_lon)
```
- Converts from pixel coordinates back to real-world coordinates
- Optional: Converts to geographic coordinates (lat/lon) for outdoor mapping

### 10. **Obstacle Classification**
```python
area = cv2.contourArea(contour)
object_type = "wall" if area > 20 else "door"
```
- **Large areas** → classified as "walls" (typically >20 square units)
- **Small areas** → classified as "doors" or other objects
- Enables semantic understanding of the environment

##  Output Results

The system generates multiple useful outputs:

1. **JSON Map File**: Contains boundary and obstacles in geographic coordinates
2. **Grid Image**: Visual representation of the 2D obstacle map
3. **Decomposition Data**: Precomputed path planning information for fast navigation
4. **Processed PCD**: Cleaned version of the original point cloud

## 🛠 Technical Details

### Key Parameters You Can Adjust:

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `PCD_PROCESSING_RESOLUTION` | 0.005m | Grid cell size (balance detail vs performance) |
| `distance_threshold` | 0.01m | Ground detection sensitivity |
| `z_range` | (0.1, 2.0)m | Obstacle height range for navigation |
| `kernel_size` | (6,6) | Obstacle dilation amount for safety margins |
| `min_obstacle_area` | 5 | Minimum size for obstacles (removes noise) |

### Algorithm Choices:

- **RANSAC**: Robust against noise and outliers in point cloud data
- **Voxel Grid**: Maintains spatial distribution while reducing computation
- **Morphological Operations**: Improve obstacle connectivity and safety margins
- **Contour Approximation**: Balance between accuracy and computational efficiency

##  Complete Usage Example

### Method 1: Web API (Recommended)
```bash
# Process a PCD file through the web interface
curl -X POST /upload-pcd \
  -F "pcd_file=@map.pcd" \
  -F "name=my_office_map" \
  -F "ref_lat=40.7128" \
  -F "ref_lon=-74.0060"
```

### Method 2: Complete Gazebo to 2D Map Pipeline
```bash
# Step 1: Generate 3D point cloud from Gazebo
ros2 run gazebo_map_creator request_map.py -c '(-5,-5,0)(5,5,3)' -r 0.01 -f office_map

# Step 2: Convert to 2D obstacle map
curl -X POST /upload-pcd \
  -F "pcd_file=@office_map.pcd" \
  -F "name=office_navigation_map" \
  -F "ref_lat=0.0" -F "ref_lon=0.0"

# Result: office_navigation_map.json ready for Nav2!
```
Here’s a clean, polished **README-style section** for your libraries list:

---

## 📚 Libraries & Dependencies

###  Core Processing Libraries

| Library               | Purpose                                  | Key Functions / Usage                                                               |
| --------------------- | ---------------------------------------- | ----------------------------------------------------------------------------------- |
| **Open3D (`open3d`)** | 3D point cloud processing                | `read_point_cloud()`, `voxel_down_sample()`, `segment_plane()`, `select_by_index()` |
| **OpenCV (`cv2`)**    | Image processing & computer vision       | `dilate()`, `findContours()`, `approxPolyDP()`, `contourArea()`, `imwrite()`        |
| **NumPy (`numpy`)**   | Numerical computing & array manipulation | `asarray()`, `zeros()`, indexing operations, math operations                        |
| **Flask (`flask`)**   | Backend API framework                    | `request`, `jsonify`, route handling                                                |

---

###  Specialized / Supporting Libraries

| Library    | Purpose                            | Role in Pipeline                                               |
| ---------- | ---------------------------------- | -------------------------------------------------------------- |
| **Open3D** | 3D point cloud I/O & processing    | Load `.pcd` files, voxel downsampling, RANSAC plane extraction |
| **OpenCV** | 2D image analysis & operations     | Grid mapping, dilation, contour extraction, polygon fitting    |
| **NumPy**  | Coordinate math & array structures | Grid computation, point transformations, data storage          |
| **JSON**   | Data serialization                 | Output mapping results in JSON for external use                |

---

##  Why This Approach Works Well

1. **Efficient**: Processes thousands of 3D points into clean 2D obstacles
2. **Robust**: Handles noisy Gazebo data effectively using RANSAC and filtering
3. **Practical**: Focuses on navigation-relevant obstacles with safety margins
4. **Flexible**: Parameters adjustable for different environments (indoor/outdoor)
5. **Integration Ready**: Output compatible with ROS2 Nav2 and other planners
6. **Fast Development**: Skip SLAM and directly generate maps from simulation

##  Ideal Use Cases

- **Nav2 Testing**: Quick map generation for navigation stack development
- **Simulation Validation**: Compare planned vs actual robot paths
- **Rapid Prototyping**: Test different environment layouts quickly
- **Education**: Understand mapping algorithms without hardware
- **Research**: Generate synthetic datasets for algorithm development

##  Credits

**Original Gazebo Map Creator Author**: Arshad Mehmood  
**Gazebo Map Creator Guide**: [Medium Article](https://medium.com/@arshad.mehmood/ros2-gazebo-world-map-generator-a103b510a7e5)  
**Gazebo Map Creator Repository**: [https://github.com/arshadlab/gazebo_map_creator](https://github.com/arshadlab/gazebo_map_creator)

This project extends the original gazebo_map_creator by adding intelligent 2D obstacle extraction specifically optimized for robot navigation systems.

---

*This pipeline transforms raw 3D Gazebo environments into practical 2D navigation maps that robots can use for safe and efficient path planning in complex environments.*
