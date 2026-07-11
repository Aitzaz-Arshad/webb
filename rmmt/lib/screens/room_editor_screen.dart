// lib/screens/room_editor_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_planning/api/api_service.dart';
import 'package:path_planning/providers/auth_provider.dart';

const Color kNavyDark = Color(0xFF0A1526);
const Color kNavyMid = Color(0xFF122140);
const Color kAccent = Color(0xFF2FE0C6);

class RoomEditorScreen extends StatefulWidget {
  const RoomEditorScreen({super.key});

  @override
  State<RoomEditorScreen> createState() => _RoomEditorScreenState();
}

class _RoomEditorScreenState extends State<RoomEditorScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _rooms = [];
  bool _isLoading = false;
  Map<String, dynamic>? _selectedRoom;

  // Controllers for editing
  final _nameController = TextEditingController();
  final _xController = TextEditingController();
  final _yController = TextEditingController();
  final _thetaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _xController.dispose();
    _yController.dispose();
    _thetaController.dispose();
    super.dispose();
  }

  Future<void> _loadRooms() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    setState(() {
      _isLoading = true;
    });

    try {
      final list = await _apiService.getRooms(
        public: false,
        requesterId: auth.userId,
        requesterRole: auth.userRole,
      );
      setState(() {
        _rooms = list.map((r) {
          // Initialize region defaults if they don't exist yet
          final map = Map<String, dynamic>.from(r);
          map['label_x'] ??= 0.4;
          map['label_y'] ??= 0.4;
          map['region_width'] ??= 0.15;
          map['region_height'] ??= 0.12;
          return map;
        }).toList();

        // Keep selection updated if it exists
        if (_selectedRoom != null) {
          final found = _rooms.firstWhere(
            (r) => r['id'] == _selectedRoom!['id'],
            orElse: () => null,
          );
          if (found != null) {
            _selectRoom(found);
          } else {
            _selectedRoom = null;
          }
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load rooms: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _selectRoom(Map<String, dynamic> room) {
    setState(() {
      _selectedRoom = room;
      _nameController.text = room['name'];
      _xController.text = room['x'].toString();
      _yController.text = room['y'].toString();
      _thetaController.text = room['theta'].toString();
    });
  }

  Future<void> _saveChanges() async {
    if (_selectedRoom == null) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);

    try {
      final name = _nameController.text.trim();
      final double? x = double.tryParse(_xController.text);
      final double? y = double.tryParse(_yController.text);
      final double? theta = double.tryParse(_thetaController.text);

      if (name.isEmpty || x == null || y == null || theta == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill out all fields with valid numbers')),
        );
        return;
      }

      await _apiService.updateRoom(
        auth.userId!,
        auth.userRole!,
        _selectedRoom!['id'],
        name: name,
        x: x,
        y: y,
        theta: theta,
        labelX: _selectedRoom!['label_x'],
        labelY: _selectedRoom!['label_y'],
        regionWidth: _selectedRoom!['region_width'],
        regionHeight: _selectedRoom!['region_height'],
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Changes saved successfully!')),
      );
      _loadRooms();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save changes: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNavyDark,
      appBar: AppBar(
        title: const Text('2D Floor Plan Layout Editor'),
        backgroundColor: kNavyMid,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file_rounded),
            tooltip: 'Upload New Floor Plan Map',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Upload feature coming soon')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadRooms,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kAccent))
          : Row(
              children: [
                // 1. Visual Floor Plan Image Panel (Left Side)
                Expanded(
                  flex: 3,
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: kNavyMid,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final parentW = constraints.maxWidth;
                        final parentH = constraints.maxHeight;

                        return Stack(
                          children: [
                            // Base Floor Plan Image
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Image.asset(
                                  'assets/images/floor_plan.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            // Overlaid interactive room boxes
                            for (var room in _rooms)
                              _buildRoomOverlay(room, parentW, parentH),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                // 2. Editor Sidebar Control Panel (Right Side)
                Expanded(
                  flex: 2,
                  child: Container(
                    margin: const EdgeInsets.only(top: 24, bottom: 24, right: 24),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: kNavyMid,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: _selectedRoom == null
                        ? Center(
                            child: Text(
                              'Select a room on the floor plan to edit its layout geometry and navigation coordinates.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 16),
                            ),
                          )
                        : SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      _selectedRoom!['is_robot_home']
                                          ? Icons.home_rounded
                                          : Icons.room_rounded,
                                      color: _selectedRoom!['is_robot_home']
                                          ? Colors.purpleAccent
                                          : kAccent,
                                      size: 28,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _selectedRoom!['is_robot_home']
                                            ? 'Robot Home Base'
                                            : 'Room Configuration',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(color: Colors.white24, height: 32),
                                
                                // Room Display Name
                                const Text('Room Display Name', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _nameController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: kNavyDark,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    hintText: 'e.g. Robotics Lab 101',
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Drag & Size Percentages Info/Sliders
                                const Text('Floor Plan Layout Adjustments', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(
                                  'Reposition by dragging the room box on the map. Adjust region dimensions below:',
                                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                                ),
                                const SizedBox(height: 12),
                                _buildSliderRow(
                                  label: 'Width (%)',
                                  val: _selectedRoom!['region_width'],
                                  min: 0.02,
                                  max: 0.5,
                                  onChanged: (newVal) {
                                    setState(() {
                                      _selectedRoom!['region_width'] = newVal;
                                      // Keep X inside bounds
                                      if (_selectedRoom!['label_x'] + newVal > 1.0) {
                                        _selectedRoom!['label_x'] = 1.0 - newVal;
                                      }
                                    });
                                  },
                                ),
                                _buildSliderRow(
                                  label: 'Height (%)',
                                  val: _selectedRoom!['region_height'],
                                  min: 0.02,
                                  max: 0.5,
                                  onChanged: (newVal) {
                                    setState(() {
                                      _selectedRoom!['region_height'] = newVal;
                                      // Keep Y inside bounds
                                      if (_selectedRoom!['label_y'] + newVal > 1.0) {
                                        _selectedRoom!['label_y'] = 1.0 - newVal;
                                      }
                                    });
                                  },
                                ),
                                const SizedBox(height: 24),

                                // Robot Navigation Coordinates
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: kNavyDark.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.precision_manufacturing_outlined, color: Colors.amber, size: 20),
                                          SizedBox(width: 8),
                                          Text(
                                            'Robot Navigation Coordinates',
                                            style: TextStyle(
                                              color: Colors.amber,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        '(Used internally by ROS2 Nav2 — not shown to users)',
                                        style: TextStyle(color: Colors.white38, fontSize: 11),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildCoordinateField(label: 'Nav X (meters)', controller: _xController),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _buildCoordinateField(label: 'Nav Y (meters)', controller: _yController),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      _buildCoordinateField(label: 'Nav Theta (radians)', controller: _thetaController),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 32),

                                // Save Changes Button
                                ElevatedButton.icon(
                                  onPressed: _saveChanges,
                                  icon: const Icon(Icons.save_rounded),
                                  label: const Text('Save Configuration'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kAccent,
                                    foregroundColor: kNavyDark,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildRoomOverlay(Map<String, dynamic> room, double parentWidth, double parentHeight) {
    final bool isSelected = _selectedRoom != null && _selectedRoom!['id'] == room['id'];
    final bool isHome = room['is_robot_home'] as bool;
    
    final double left = (room['label_x'] as double) * parentWidth;
    final double top = (room['label_y'] as double) * parentHeight;
    final double width = (room['region_width'] as double) * parentWidth;
    final double height = (room['region_height'] as double) * parentHeight;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: GestureDetector(
        onTap: () => _selectRoom(room),
        onPanUpdate: (details) {
          // Select room on drag start
          if (_selectedRoom == null || _selectedRoom!['id'] != room['id']) {
            _selectRoom(room);
          }
          
          setState(() {
            double dx = details.delta.dx / parentWidth;
            double dy = details.delta.dy / parentHeight;
            
            // Adjust and clamp coordinates inside bounds (0.0 to 1.0)
            room['label_x'] = (room['label_x'] + dx).clamp(0.0, 1.0 - room['region_width']);
            room['label_y'] = (room['label_y'] + dy).clamp(0.0, 1.0 - room['region_height']);
            
            // Sync selected room fields
            if (_selectedRoom != null && _selectedRoom!['id'] == room['id']) {
              _selectedRoom!['label_x'] = room['label_x'];
              _selectedRoom!['label_y'] = room['label_y'];
            }
          });
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.move,
          child: Container(
            decoration: BoxDecoration(
              color: isSelected 
                  ? kAccent.withOpacity(0.35) 
                  : (isHome ? Colors.purpleAccent.withOpacity(0.18) : kAccent.withOpacity(0.12)),
              border: Border.all(
                color: isSelected 
                    ? kAccent 
                    : (isHome ? Colors.purpleAccent : Colors.white24),
                width: isSelected ? 2.5 : 1.5,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Stack(
              children: [
                Center(
                  child: Text(
                    room['name'],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: Icon(
                    isHome ? Icons.home_rounded : Icons.location_on_rounded,
                    color: isHome ? Colors.purpleAccent : Colors.white30,
                    size: 14,
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double val,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13))),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: kAccent,
              thumbColor: kAccent,
              overlayColor: kAccent.withOpacity(0.12),
            ),
            child: Slider(
              value: val,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        Text(
          '${(val * 100).toStringAsFixed(0)}%',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildCoordinateField({required String label, required TextEditingController controller}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: kNavyDark,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
      ],
    );
  }
}
