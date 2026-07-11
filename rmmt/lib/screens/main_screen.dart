import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_planning/models/obstacle.dart';
import 'package:path_planning/providers/map_provider.dart';
import 'package:path_planning/widgets/drawing_tools_widget.dart';
import 'package:path_planning/widgets/path_planning_widget.dart';
import 'package:path_planning/widgets/save_map_widget.dart';
import 'package:path_planning/widgets/saved_maps_widget.dart';
import 'package:path_planning/widgets/indoor_map_widget.dart';
import 'package:provider/provider.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  // Helper function to generate distinct colors for each cell
  Color _getCellColor(int cellNumber, int totalCells) {
    final hue = (cellNumber * 360.0 / totalCells) % 360;
    return HSVColor.fromAHSV(0.4, hue, 0.7, 0.9).toColor();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 300,
            color: Colors.white,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Path Planner',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const DrawingToolsWidget(),
                  const Divider(),
                  const SaveMapWidget(),
                  const Divider(),
                  const PathPlanningWidget(),
                  const Divider(),
                  const SavedMapsWidget(),
                  IndoorMapWidget(),
                ],
              ),
            ),
          ),
          // Main Map View
          Expanded(
            child: Consumer<MapProvider>(
              builder: (context, mapProvider, child) {
                // Debug: Log obstacles for inspection
                print(
                  'Obstacles: ${mapProvider.obstacles.length} items. Current drawing mode: ${mapProvider.drawingMode}',
                );

                return FlutterMap(
                  options: MapOptions(
                    initialCenter: mapProvider.initialCenter,
                    initialZoom: 15.0,
                    onTap: (tapPosition, point) =>
                        mapProvider.handleMapTap(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.path_planner_app',
                    ),

                    // --- BOUNDARY LAYER ---
                    if (mapProvider.boundary != null &&
                        mapProvider.boundary!.points != null &&
                        mapProvider.boundary!.points!.isNotEmpty)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: mapProvider.boundary!.points!,
                            color: Colors.white.withOpacity(
                              0.0,
                            ), // Transparent working area
                            borderColor: Colors.green,
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),

                    // --- GRID CELL LAYER (NEW - Shows before obstacles) ---
                    if (mapProvider.showGrid && mapProvider.gridCells.isNotEmpty)
                      PolygonLayer(
                        polygons: mapProvider.gridCells.map((cell) {
                          // Create rectangle from bounds
                          final points = [
                            cell.minBound,
                            LatLng(cell.minBound.latitude, cell.maxBound.longitude),
                            cell.maxBound,
                            LatLng(cell.maxBound.latitude, cell.minBound.longitude),
                          ];

                          return Polygon(
                            points: points,
                            color: _getCellColor(cell.cellNumber, mapProvider.gridCells.length),
                            borderColor: Colors.black.withOpacity(0.3),
                            borderStrokeWidth: 1,
                          );
                        }).toList(),
                      ),

                    // --- OBSTACLE POLYGON/RECTANGLE LAYER (MODIFIED) ---
                    PolygonLayer(
                      polygons: mapProvider.obstacles
                          .where(
                            (o) =>
                                // FIX: Include ObstacleType.rectangle
                                (o.type == ObstacleType.polygon ||
                                    o.type == ObstacleType.rectangle) &&
                                o.points != null &&
                                o.points!.isNotEmpty,
                          )
                          .map((obs) {
                            print(
                              'Rendering ${obs.type} with points: ${obs.points?.length}',
                            );
                            return Polygon(
                              points: obs.points!,
                              color: Colors.red.withOpacity(0.5),
                              borderColor: Colors.red,
                              borderStrokeWidth: 2,
                            );
                          })
                          .toList(),
                    ),

                    // --- OBSTACLE CIRCLE LAYER ---
                    CircleLayer(
                      circles: mapProvider.obstacles
                          .where(
                            (o) =>
                                o.type == ObstacleType.circle &&
                                o.center != null &&
                                o.radius != null,
                          )
                          .map((obs) {
                            return CircleMarker(
                              point: obs.center!,
                              radius: obs.radius!,
                              color: Colors.red.withOpacity(0.5),
                              borderColor: Colors.red,
                              borderStrokeWidth: 2,
                              useRadiusInMeter: true,
                            );
                          })
                          .toList(),
                    ),

                    // --- GRID CELL CENTERS (NEW - Optional: shows cell numbers) ---
                    if (mapProvider.showGrid && mapProvider.gridCells.isNotEmpty)
                      MarkerLayer(
                        markers: mapProvider.gridCells.map((cell) {
                          return Marker(
                            point: cell.center,
                            width: 40,
                            height: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.8),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black, width: 1),
                              ),
                              child: Center(
                                child: Text(
                                  '${cell.cellNumber}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                    // --- PATH LAYER (CRITICALLY CORRECTED) ---
                    if (mapProvider.unprunedPath.isNotEmpty ||
                        mapProvider.smoothPath.isNotEmpty) // Check smoothPath
                      PolylineLayer(
                        polylines: [
                          if (mapProvider.unprunedPath.isNotEmpty)
                            Polyline(
                              points: mapProvider.unprunedPath,
                              color: Colors.green.withOpacity(0.8),
                              strokeWidth: 4,
                            ),

                          // FIX: Draw the smoothPath instead of prunedPath
                          if (mapProvider.smoothPath.isNotEmpty)
                            Polyline(
                              points: mapProvider.smoothPath, // <--- DRAW THE SMOOTH PATH
                              color: Colors.blue,             // <--- Use blue for the final path
                              strokeWidth: 4,
                            ),
                            
                          // Optional: Draw the pruned path as a dotted line
                          /*
                          else if (mapProvider.prunedPath.isNotEmpty)
                            Polyline(
                              points: mapProvider.prunedPath,
                              color: Colors.blue.withOpacity(0.5), 
                              strokeWidth: 2,
                              isDotted: true,
                            ),
                          */
                        ],
                      ),

                    // --- MARKER LAYER (Start/End) ---
                    MarkerLayer(
                      markers: [
                        if (mapProvider.startPoint != null)
                          Marker(
                            point: mapProvider.startPoint!,
                            width: 80,
                            height: 80,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.green,
                              size: 40,
                            ),
                          ),
                        if (mapProvider.endPoint != null)
                          Marker(
                            point: mapProvider.endPoint!,
                            width: 80,
                            height: 80,
                            child: const Icon(
                              Icons.flag,
                              color: Colors.red,
                              size: 40,
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
