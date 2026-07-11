// lib/widgets/indoor_map_widget.dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_planning/api/api_service.dart';
import 'package:path_planning/models/obstacle.dart';
import 'package:path_planning/providers/map_provider.dart';
import 'package:provider/provider.dart';

class IndoorMapWidget extends StatefulWidget {
  const IndoorMapWidget({super.key});

  @override
  State<IndoorMapWidget> createState() => _IndoorMapWidgetState();
}

class _IndoorMapWidgetState extends State<IndoorMapWidget> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _refLatController = TextEditingController();
  final TextEditingController _refLonController = TextEditingController();
  PlatformFile? _selectedFile;
  bool _isLoading = false;
  String _errorMessage = '';

  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mapProvider = Provider.of<MapProvider>(context, listen: false);
      _refLatController.text = mapProvider.initialCenter.latitude.toString();
      _refLonController.text = mapProvider.initialCenter.longitude.toString();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _refLatController.dispose();
    _refLonController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pcd'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes == null) {
          setState(() {
            _errorMessage = 'Selected file has no readable bytes.';
          });
          return;
        }
        setState(() {
          _selectedFile = file;
          _errorMessage = '';
        });
      } else {
        setState(() {
          _errorMessage = 'No file selected or operation cancelled.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error picking file: $e';
      });
    }
  }

  Future<void> _uploadAndProcess() async {
    final name = _nameController.text.trim();
    final refLatText = _refLatController.text.trim();
    final refLonText = _refLonController.text.trim();

    if (name.isEmpty ||
        _selectedFile == null ||
        refLatText.isEmpty ||
        refLonText.isEmpty) {
      setState(() {
        _errorMessage =
            'Please provide a name, select a PCD file, and set reference coordinates.';
      });
      return;
    }

    double? refLat = double.tryParse(refLatText);
    double? refLon = double.tryParse(refLonText);

    if (refLat == null || refLon == null) {
      setState(() {
        _errorMessage = 'Invalid reference latitude or longitude.';
      });
      return;
    }

    if (_selectedFile!.bytes == null) {
      setState(() {
        _errorMessage = 'Selected file has no readable bytes.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final data = await _apiService.uploadPcd(
        name,
        refLat,
        refLon,
        _selectedFile!.bytes,
        _selectedFile!.name,
      );
      print('Raw response data: $data'); // Add this line
      if (data['boundary'] == null || data['obstacles'] == null) {
        throw Exception(
          'Invalid response from server: Missing boundary or obstacles.',
        );
      }
      final boundaryJson = data['boundary'] as Map<String, dynamic>;
      final obstaclesJson = data['obstacles'] as List;

      final boundary = Obstacle.fromJson(boundaryJson);
      final obstacles = obstaclesJson
          .map((o) => Obstacle.fromJson(o as Map<String, dynamic>))
          .toList();

      final mapProvider = Provider.of<MapProvider>(context, listen: false);
      mapProvider.setBoundaryAndObstacles(boundary, obstacles);
      mapProvider.setCurrentMapName(name);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indoor map loaded successfully!')),
      );

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('3D Visualization'),
          content: const Text(
            'To view the 3D map, download the PCD file from the saved_maps directory and run:\npcl_viewer map.pcd\nin your terminal (requires PCL installed).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to process PCD: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Indoor Maps (PCD)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Map Name',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _refLatController,
            decoration: const InputDecoration(
              labelText: 'Reference Latitude',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _refLonController,
            decoration: const InputDecoration(
              labelText: 'Reference Longitude',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _pickFile,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 40),
            ),
            child: Text(
              _selectedFile == null
                  ? 'Select PCD File'
                  : 'Selected: ${_selectedFile!.name}',
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _isLoading ? null : _uploadAndProcess,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 40),
            ),
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Upload & Process'),
          ),
          if (_errorMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                _errorMessage,
                style: const TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }
}
