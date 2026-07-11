// lib/widgets/save_map_widget.dart

import 'package:flutter/material.dart';
import 'package:path_planning/providers/map_provider.dart';
import 'package:provider/provider.dart';

class SaveMapWidget extends StatefulWidget {
  const SaveMapWidget({super.key});

  @override
  State<SaveMapWidget> createState() => _SaveMapWidgetState();
}

class _SaveMapWidgetState extends State<SaveMapWidget> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapProvider = Provider.of<MapProvider>(context, listen: false);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Save Map',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Map Name',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10)
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () {
              if (_controller.text.isNotEmpty) {
                mapProvider.saveMap(_controller.text);
                _controller.clear();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Map saved successfully!')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 40)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}