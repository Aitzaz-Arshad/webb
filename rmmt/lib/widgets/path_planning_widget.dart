// lib/widgets/path_planning_widget.dart

import 'package:flutter/material.dart';
import 'package:path_planning/providers/map_provider.dart';
import 'package:provider/provider.dart';

class PathPlanningWidget extends StatelessWidget {
  const PathPlanningWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final mapProvider = Provider.of<MapProvider>(context);

    Widget buildLoadingIndicator() {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Path Planning',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.location_on, color: Colors.green),
            label: const Text('Set Start Point'),
            onPressed: () => mapProvider.setDrawingMode(DrawingMode.setStart),
            style: ElevatedButton.styleFrom(
                backgroundColor:
                    mapProvider.drawingMode == DrawingMode.setStart
                        ? Colors.blue[100]
                        : Colors.white,
                minimumSize: const Size(double.infinity, 40)),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.flag, color: Colors.red),
            label: const Text('Set End Point'),
            onPressed: () => mapProvider.setDrawingMode(DrawingMode.setEnd),
            style: ElevatedButton.styleFrom(
                backgroundColor:
                    mapProvider.drawingMode == DrawingMode.setEnd
                        ? Colors.blue[100]
                        : Colors.white,
                minimumSize: const Size(double.infinity, 40)),
          ),
          const SizedBox(height: 16),
          const Text('Path Planning using:', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.star_border),
            onPressed: mapProvider.isLoading ? null : () => mapProvider.calculatePath(PlanningAlgorithm.aStar),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 40)),
            label: (mapProvider.isLoading && mapProvider.loadingAlgorithm == PlanningAlgorithm.aStar)
                ? buildLoadingIndicator()
                : const Text('A* Algorithm'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.memory),
            onPressed: mapProvider.isLoading ? null : () => mapProvider.calculatePath(PlanningAlgorithm.dynamicProgramming),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 40)),
             label: (mapProvider.isLoading && mapProvider.loadingAlgorithm == PlanningAlgorithm.dynamicProgramming)
                ? buildLoadingIndicator()
                : const Text('Dynamic Programming'),
          ),

          // NEW: Show Grid button (appears after DP is used)
          if (mapProvider.lastUsedAlgorithm == PlanningAlgorithm.dynamicProgramming &&
              mapProvider.prunedPath.isNotEmpty) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: Icon(mapProvider.showGrid ? Icons.grid_off : Icons.grid_on),
              onPressed: mapProvider.isLoadingGrid
                  ? null
                  : () async {
                      if (mapProvider.gridCells.isEmpty) {
                        // Fetch grid data if not already loaded
                        await mapProvider.fetchGridData();
                      } else {
                        // Toggle visibility if already loaded
                        mapProvider.toggleGridVisibility();
                      }
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: mapProvider.showGrid ? Colors.orange : Colors.teal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 40)),
              label: mapProvider.isLoadingGrid
                  ? buildLoadingIndicator()
                  : Text(mapProvider.showGrid ? 'Hide Grid' : 'Show Grid'),
            ),
          ],

          if (mapProvider.errorMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                mapProvider.errorMessage,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: mapProvider.clearAll,
            style: TextButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}