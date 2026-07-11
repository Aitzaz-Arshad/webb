// lib/widgets/saved_maps_widget.dart

import 'package:flutter/material.dart';
import 'package:path_planning/providers/map_provider.dart';
import 'package:provider/provider.dart';

class SavedMapsWidget extends StatelessWidget {
  const SavedMapsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MapProvider>(
      builder: (context, mapProvider, child) {
        final savedMapNames = mapProvider.savedMapNames;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'List of Saved Maps',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              if (savedMapNames.isEmpty)
                const Text('No maps saved yet.')
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: savedMapNames.length,
                  itemBuilder: (context, index) {
                    final mapName = savedMapNames[index];
                    return Card(
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(mapName),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Load map icon (existing)
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                              ),
                              onPressed: () {
                                print('Tapped map: $mapName'); // Debug log
                                mapProvider.loadMap(mapName);
                              },
                            ),
                            // New: Red trash bin icon for deletion
                            IconButton(
                              icon: const Icon(
                                Icons.delete, // Bin-shaped trash icon
                                color: Colors.red,
                                size: 20, // Small size
                              ),
                              onPressed: () {
                                print('Deleting map: $mapName'); // Debug log
                                mapProvider.deleteMap(
                                  mapName,
                                ); // Call new delete method
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Deleted map: $mapName'),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
