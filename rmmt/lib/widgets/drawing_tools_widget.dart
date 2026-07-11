// lib/widgets/drawing_tools_widget.dart

import 'package:flutter/material.dart';
import 'package:path_planning/providers/map_provider.dart';
import 'package:provider/provider.dart';

class DrawingToolsWidget extends StatelessWidget {
  const DrawingToolsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final mapProvider = Provider.of<MapProvider>(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Drawing Tools',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.crop_square),
            label: const Text('Draw Boundary'),
            onPressed: () => mapProvider.setDrawingMode(DrawingMode.boundary),
            style: ElevatedButton.styleFrom(
                backgroundColor:
                    mapProvider.drawingMode == DrawingMode.boundary
                        ? Colors.blue[100]
                        : Colors.white,
                minimumSize: const Size(double.infinity, 40)),
          ),
          const SizedBox(height: 8),
          const Text('Draw Obstacles', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.rectangle_outlined),
            label: const Text('Rectangle'),
            onPressed: () => mapProvider.setDrawingMode(DrawingMode.obstacleRect),
            style: ElevatedButton.styleFrom(
                backgroundColor:
                    mapProvider.drawingMode == DrawingMode.obstacleRect
                        ? Colors.blue[100]
                        : Colors.white,
                minimumSize: const Size(double.infinity, 40)),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.circle_outlined),
            label: const Text('Circle'),
            onPressed: () => mapProvider.setDrawingMode(DrawingMode.obstacleCircle),
            style: ElevatedButton.styleFrom(
                backgroundColor:
                    mapProvider.drawingMode == DrawingMode.obstacleCircle
                        ? Colors.blue[100]
                        : Colors.white,
                minimumSize: const Size(double.infinity, 40)),
          ),
        ],
      ),
    );
  }
}