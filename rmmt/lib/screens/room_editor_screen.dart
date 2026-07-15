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
          final foundMatches = _rooms.where((r) => r['id'] == _selectedRoom!['id']);
          final found = foundMatches.isNotEmpty ? foundMatches.first : null;
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
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 682 / 1024,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final parentW = constraints.maxWidth;
                            final parentH = constraints.maxHeight;

                            return Stack(
                              children: [
                                // Base Floor Plan Image
                                Positioned.fill(
                                  child: Image.asset(
                                    'assets/images/floor_plan.png',
                                    fit: BoxFit.fill,
                                  ),
                                ),
                                // Overlaid interactive room boxes
                                for (var room in _rooms)
                                  _buildRoomOverlay(room, parentW, parentH),
                                // Floating inline edit card
                                if (_selectedRoom != null)
                                  _buildInlineEditCard(_selectedRoom!, parentW, parentH),
                              ],
                            );
                          },
                        ),
                      ),
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
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12.0),
                                child: Text(
                                  'Floor Plan Rooms Map',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Text(
                                'Select a room on the map to edit. Below is the list of all registered rooms and their coordinates.',
                                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                              ),
                              const Divider(color: Colors.white24, height: 24),
                              Expanded(
                                child: _rooms.isEmpty
                                    ? Center(
                                        child: Text(
                                          'No rooms found. Seed the database to load default rooms.',
                                          style: TextStyle(color: Colors.white.withOpacity(0.3)),
                                        ),
                                      )
                                    : ListView.separated(
                                        itemCount: _rooms.length,
                                        separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                                        itemBuilder: (context, index) {
                                          final room = _rooms[index];
                                          final isHome = room['is_robot_home'] as bool;
                                          return ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: Icon(
                                              isHome ? Icons.precision_manufacturing_outlined : Icons.location_on_rounded,
                                              color: isHome ? Colors.blue : kAccent,
                                            ),
                                            title: Text(
                                              room['name'],
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                            ),
                                            subtitle: Text(
                                              'ROS Nav: X: ${room['x'].toStringAsFixed(2)}m, Y: ${room['y'].toStringAsFixed(2)}m',
                                              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                                            ),
                                            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white30),
                                            onTap: () => _selectRoom(room),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          )
                        : SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      _selectedRoom!['is_robot_home']
                                          ? Icons.precision_manufacturing_outlined
                                          : Icons.room_rounded,
                                      color: _selectedRoom!['is_robot_home']
                                          ? Colors.blue
                                          : kAccent,
                                      size: 28,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _selectedRoom!['is_robot_home']
                                            ? 'Robot Room Info'
                                            : 'Room Information',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, color: Colors.white54),
                                      onPressed: () {
                                        setState(() {
                                          _selectedRoom = null;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                const Divider(color: Colors.white24, height: 32),
                                
                                // Display-only Room attributes
                                const Text('Room Display Name', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: kNavyDark,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: Text(
                                    _selectedRoom!['name'],
                                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Drag & Size Percentages Info/Sliders
                                const Text('Visual Layout Settings (Map Only)', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(
                                  'Adjust the size of the room boundary box drawn on the floor plan map:',
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
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _saveChanges,
                                    icon: const Icon(Icons.save_rounded, size: 18),
                                    label: const Text('Save Position & Size'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kAccent,
                                      foregroundColor: kNavyDark,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Robot Navigation Coordinates (Display Only)
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
                                          Icon(Icons.precision_manufacturing_outlined, color: Colors.blueAccent, size: 20),
                                          SizedBox(width: 8),
                                          Text(
                                            'ROS Navigation coordinates',
                                            style: TextStyle(
                                              color: Colors.blueAccent,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildStaticCoordTile('X (meters)', _selectedRoom!['x'].toString()),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _buildStaticCoordTile('Y (meters)', _selectedRoom!['y'].toString()),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),
                                
                                // Informative text pointing to map
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withOpacity(0.1),
                                    border: Border.all(color: Colors.amber.withOpacity(0.3)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'To edit the room name or ROS navigation coordinates, use the inline card overlay directly on the floor plan map.',
                                          style: TextStyle(color: Colors.amber.shade200, fontSize: 12.5, height: 1.3),
                                        ),
                                      ),
                                    ],
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

  Color _getRoomColor(Map<String, dynamic> room) {
    final bool isHome = room['is_robot_home'] == true;
    final String name = (room['name'] ?? '').toString().toLowerCase();
    if (isHome || name.contains('robot')) {
      return Colors.blue;
    } else if (name.contains('1') || name.contains('3')) {
      return Colors.amber; // Yellow
    } else if (name.contains('2') || name.contains('4') || name.contains('5')) {
      return Colors.green;
    }
    return kAccent;
  }

  Widget _buildRoomOverlay(Map<String, dynamic> room, double parentWidth, double parentHeight) {
    final bool isSelected = _selectedRoom != null && _selectedRoom!['id'] == room['id'];
    
    final double left = (room['label_x'] as double) * parentWidth;
    final double top = (room['label_y'] as double) * parentHeight;
    final double width = (room['region_width'] as double) * parentWidth;
    final double height = (room['region_height'] as double) * parentHeight;

    final Color roomColor = _getRoomColor(room);

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
              color: roomColor.withOpacity(0.35),
              border: Border.all(
                color: isSelected ? kAccent : roomColor,
                width: isSelected ? 2.5 : 1.5,
              ),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: (isSelected ? kAccent : roomColor).withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Text(
                  room['name'],
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineEditCard(Map<String, dynamic> room, double parentWidth, double parentHeight) {
    final double left = (room['label_x'] as double) * parentWidth;
    final double top = (room['label_y'] as double) * parentHeight;
    final double width = (room['region_width'] as double) * parentWidth;
    final double height = (room['region_height'] as double) * parentHeight;

    const double cardWidth = 260.0;
    const double cardHeight = 240.0;

    double cardLeft = left + (width / 2) - (cardWidth / 2);
    double cardTop = top - cardHeight - 10.0;

    if (cardTop < 10.0) {
      cardTop = top + height + 10.0;
    }

    cardLeft = cardLeft.clamp(10.0, parentWidth - cardWidth - 10.0);
    cardTop = cardTop.clamp(10.0, parentHeight - cardHeight - 10.0);

    return Positioned(
      left: cardLeft,
      top: cardTop,
      width: cardWidth,
      height: cardHeight,
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(12),
        color: kNavyMid,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kAccent, width: 2.0),
            boxShadow: [
              BoxShadow(
                color: kAccent.withOpacity(0.15),
                blurRadius: 12,
                spreadRadius: 2,
              )
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_location_alt_rounded, color: kAccent, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Edit Room Config',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 16),
                    onPressed: () {
                      setState(() {
                        _selectedRoom = null;
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )
                ],
              ),
              const SizedBox(height: 10),
              const Text('Room Name', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              SizedBox(
                height: 36,
                child: TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    filled: true,
                    fillColor: kNavyDark,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white24),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: kAccent, width: 1.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Nav X (m)', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 36,
                          child: TextField(
                            controller: _xController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              filled: true,
                              fillColor: kNavyDark,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                              enabledBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: Colors.white24),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: kAccent, width: 1.5),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Nav Y (m)', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 36,
                          child: TextField(
                            controller: _yController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              filled: true,
                              fillColor: kNavyDark,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                              enabledBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: Colors.white24),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: kAccent, width: 1.5),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 32,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white30),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: () {
                        setState(() {
                          _nameController.text = room['name'];
                          _xController.text = room['x'].toString();
                          _yController.text = room['y'].toString();
                          _thetaController.text = room['theta'].toString();
                          _selectedRoom = null;
                        });
                      },
                      child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 32,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccent,
                        foregroundColor: kNavyDark,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onPressed: _saveChanges,
                      child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                ],
              )
            ],
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



  Widget _buildStaticCoordTile(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: kNavyDark,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white10),
          ),
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
