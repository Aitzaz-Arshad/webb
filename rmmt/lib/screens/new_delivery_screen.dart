// lib/screens/new_delivery_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_planning/providers/auth_provider.dart';
import 'package:path_planning/api/api_service.dart';

const Color kNavyDark = Color(0xFF0A1526);
const Color kNavyMid = Color(0xFF122140);
const Color kAccent = Color(0xFF2FE0C6);

class NewDeliveryScreen extends StatefulWidget {
  const NewDeliveryScreen({super.key});

  @override
  State<NewDeliveryScreen> createState() => _NewDeliveryScreenState();
}

class _NewDeliveryScreenState extends State<NewDeliveryScreen> {
  final ApiService _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _recipientNameController = TextEditingController();

  List<dynamic> _rooms = [];
  bool _isLoadingRooms = false;
  bool _isSubmitting = false;

  String _deliveryType = 'home_to_room'; // 'home_to_room' or 'room_to_room'
  int? _selectedRecipientRoomId;
  int? _selectedPickupRoomId;
  String _mapSelectFocus = 'recipient'; // 'pickup' or 'recipient'

  bool _isScheduled = false;
  DateTime? _scheduledDateTime;

  @override
  void dispose() {
    _recipientNameController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchRooms();
  }

  Future<void> _fetchRooms() async {
    setState(() {
      _isLoadingRooms = true;
    });

    try {
      // Fetch public room geometries
      final list = await _apiService.getRooms(public: true);
      setState(() {
        _rooms = list;
        _initPickupForHomeToRoom();
      });
    } catch (e) {
      print('Failed to load rooms: $e');
    } finally {
      setState(() {
        _isLoadingRooms = false;
      });
    }
  }

  void _initPickupForHomeToRoom() {
    if (_deliveryType == 'home_to_room') {
      final robotHomeMatches = _rooms.where((r) => r['is_robot_home'] == true);
      final robotRoom = robotHomeMatches.isNotEmpty ? robotHomeMatches.first : null;
      if (robotRoom != null) {
        _selectedPickupRoomId = robotRoom['id'];
      }
    }
  }



  void _clearSelection() {
    setState(() {
      if (_deliveryType == 'home_to_room') {
        _initPickupForHomeToRoom();
        _selectedRecipientRoomId = null;
      } else {
        _selectedPickupRoomId = null;
        _selectedRecipientRoomId = null;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _formKey.currentState?.validate();
    });
  }

  void _showDispatchOptionsDialog() {
    bool localIsScheduled = false;
    DateTime? localScheduledDateTime;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: kNavyMid,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text(
                'Choose Delivery Option',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioListTile<bool>(
                    title: const Text('Dispatch Immediately', style: TextStyle(color: Colors.white, fontSize: 14)),
                    subtitle: const Text('Send the robot on delivery right now', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    value: false,
                    groupValue: localIsScheduled,
                    activeColor: kAccent,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      setDialogState(() {
                        localIsScheduled = val!;
                      });
                    },
                  ),
                  RadioListTile<bool>(
                    title: const Text('Schedule for Later', style: TextStyle(color: Colors.white, fontSize: 14)),
                    subtitle: const Text('Pick a specific future date and time', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    value: true,
                    groupValue: localIsScheduled,
                    activeColor: kAccent,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      setDialogState(() {
                        localIsScheduled = val!;
                      });
                    },
                  ),
                  if (localIsScheduled) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          backgroundColor: kNavyDark,
                        ),
                        icon: const Icon(Icons.date_range_rounded, color: kAccent, size: 18),
                        label: Text(
                          localScheduledDateTime == null
                              ? 'Select Date & Time'
                              : localScheduledDateTime.toString().split('.')[0],
                          style: const TextStyle(fontSize: 13),
                        ),
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now().add(const Duration(minutes: 5)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 30)),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: kAccent,
                                    onPrimary: kNavyDark,
                                    surface: kNavyMid,
                                    onSurface: Colors.white,
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (date == null) return;
                          
                          if (!context.mounted) return;
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 5))),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: kAccent,
                                    onPrimary: kNavyDark,
                                    surface: kNavyMid,
                                    onSurface: Colors.white,
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (time == null) return;
                          
                          setDialogState(() {
                            localScheduledDateTime = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              time.hour,
                              time.minute,
                            );
                          });
                        },
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccent,
                    foregroundColor: kNavyDark,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    // Validation for Scheduled option
                    if (localIsScheduled && localScheduledDateTime == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a scheduled date and time.'),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                      return;
                    }
                    if (localIsScheduled && localScheduledDateTime!.isBefore(DateTime.now())) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Scheduled time must be in the future.'),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                      return;
                    }

                    // Save state and submit
                    setState(() {
                      _isScheduled = localIsScheduled;
                      _scheduledDateTime = localScheduledDateTime;
                    });
                    
                    Navigator.of(context).pop(); // Close dialog
                    _submit(); // Trigger submit
                  },
                  child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRecipientRoomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a destination room on the floor plan.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (_deliveryType == 'room_to_room' && _selectedPickupRoomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a pickup room on the floor plan.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_isScheduled) {
      if (_scheduledDateTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a scheduled date and time.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      if (_scheduledDateTime!.isBefore(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Scheduled time must be in the future.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.userId == null) return;

    final recipientName = _recipientNameController.text.trim();

    setState(() {
      _isSubmitting = true;
    });

    try {
      final response = await _apiService.createDelivery(
        auth.userId!,
        _selectedRecipientRoomId!,
        _deliveryType == 'room_to_room' ? _selectedPickupRoomId : null,
        _deliveryType,
        recipientName,
        scheduledAt: _isScheduled ? _scheduledDateTime : null,
      );

      if (mounted) {
        String confirmMessage = 'Delivery request submitted successfully!';
        final robotStatus = response['robot_status'] as String?;
        if (_isScheduled || robotStatus == 'Scheduled') {
          confirmMessage = 'Your delivery has been scheduled successfully.';
        } else if (robotStatus == 'Available') {
          confirmMessage = 'Robot is available. Your delivery will begin immediately.';
        } else if (robotStatus == 'Busy') {
          confirmMessage = 'Robot is currently completing another delivery. Your request has been added to the queue. It will start automatically when the robot becomes available.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(confirmMessage),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    // Include all rooms (including Robot Room)
    final interactiveRooms = _rooms;
    
    return Scaffold(
      backgroundColor: kNavyDark,
      appBar: AppBar(
        title: const Text('Request Robot Delivery'),
        backgroundColor: kNavyMid,
        elevation: 0,
      ),
      body: _isLoadingRooms
          ? const Center(child: CircularProgressIndicator(color: kAccent))
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  // 1. Interactive 2D Map (Left Side)
                  Expanded(
                    flex: 3,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kNavyMid,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Interactive Floor Plan',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_selectedPickupRoomId != null || _selectedRecipientRoomId != null)
                                TextButton.icon(
                                  onPressed: _clearSelection,
                                  icon: const Icon(Icons.clear_rounded, size: 16, color: Colors.redAccent),
                                  label: const Text('Reset Selection', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Center(
                              child: AspectRatio(
                                aspectRatio: 682 / 1024,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final parentW = constraints.maxWidth;
                                    final parentH = constraints.maxHeight;

                                    return Stack(
                                      children: [
                                        // Floor plan image (network-fetched with bounded layout)
                                        Positioned.fill(
                                          child: Image.network(
                                            '${_apiService.baseUrl}/floorplan',
                                            fit: BoxFit.fill,
                                            errorBuilder: (context, error, stackTrace) {
                                              return const Center(
                                                child: Text(
                                                  'Failed to load floor plan from server',
                                                  style: TextStyle(color: Colors.redAccent, fontSize: 13),
                                                ),
                                              );
                                            },
                                            loadingBuilder: (context, child, loadingProgress) {
                                              if (loadingProgress == null) return child;
                                              return const Center(
                                                child: CircularProgressIndicator(color: kAccent),
                                              );
                                            },
                                          ),
                                        ),
                                        // Overlaid interactive room regions
                                        for (var room in interactiveRooms)
                                          _buildInteractiveRoomOverlay(room, parentW, parentH),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // 2. Delivery Options Form (Right Side)
                  Expanded(
                    flex: 2,
                    child: Container(
                      margin: const EdgeInsets.only(left: 24),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: kNavyMid,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: SingleChildScrollView(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Delivery Details',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Select rooms visually on the 2D floor plan layout.',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 13,
                              ),
                            ),
                            const Divider(color: Colors.white24, height: 32),

                            // Sender Name (Read-Only)
                            const Text(
                              'Sending as',
                              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              decoration: BoxDecoration(
                                color: kNavyDark.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.account_circle_rounded, color: kAccent, size: 20),
                                  const SizedBox(width: 12),
                                  Text(
                                    auth.userName ?? 'Anonymous User',
                                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Recipient Name Field
                            const Text(
                              'Recipient Name',
                              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _recipientNameController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: kNavyDark,
                                hintText: 'Enter recipient full name',
                                hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: Colors.white10),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: kAccent, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: Colors.redAccent),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: Colors.redAccent, width: 2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Please enter recipient name';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),
                            
                            // Delivery Type Selection (Toggle)
                            const Text(
                              'Delivery Dispatch Type',
                              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Text('Home to Room'),
                                    selected: _deliveryType == 'home_to_room',
                                    selectedColor: kAccent,
                                    backgroundColor: kNavyDark,
                                    labelStyle: TextStyle(
                                      color: _deliveryType == 'home_to_room' ? kNavyDark : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _deliveryType = 'home_to_room';
                                          _mapSelectFocus = 'recipient';
                                          _clearSelection();
                                        });
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Text('Room to Room'),
                                    selected: _deliveryType == 'room_to_room',
                                    selectedColor: kAccent,
                                    backgroundColor: kNavyDark,
                                    labelStyle: TextStyle(
                                      color: _deliveryType == 'room_to_room' ? kNavyDark : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _deliveryType = 'room_to_room';
                                          _mapSelectFocus = 'pickup';
                                          _clearSelection();
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // Dropdown selections for rooms
                            if (_deliveryType == 'home_to_room') ...[
                              const Text(
                                'Select Destination Room',
                                style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<int>(
                                value: _selectedRecipientRoomId,
                                dropdownColor: kNavyMid,
                                icon: const Icon(Icons.arrow_drop_down, color: kAccent),
                                style: const TextStyle(color: Colors.white),
                                hint: const Text('Choose a room...', style: TextStyle(color: Color(0xFF8A94A6), fontSize: 13)),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: kNavyDark,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: _mapSelectFocus == 'recipient' ? Colors.redAccent : Colors.white10,
                                      width: _mapSelectFocus == 'recipient' ? 2.0 : 1.0,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(color: kAccent, width: 2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(color: Colors.redAccent),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(color: Colors.redAccent, width: 2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onTap: () {
                                  setState(() {
                                    _mapSelectFocus = 'recipient';
                                  });
                                },
                                items: interactiveRooms.where((r) => r['is_robot_home'] == false).map<DropdownMenuItem<int>>((room) {
                                  return DropdownMenuItem<int>(
                                    value: room['id'] as int,
                                    child: Text(room['name'] as String),
                                  );
                                }).toList(),
                                onChanged: (int? newValue) {
                                  setState(() {
                                    _selectedRecipientRoomId = newValue;
                                    _mapSelectFocus = 'recipient';
                                  });
                                  _formKey.currentState?.validate();
                                },
                                validator: (value) {
                                  if (value == null) {
                                    return 'Please select a destination room';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                            ] else if (_deliveryType == 'room_to_room') ...[
                              const Text(
                                'Pickup Room',
                                style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<int>(
                                value: _selectedPickupRoomId,
                                dropdownColor: kNavyMid,
                                icon: const Icon(Icons.arrow_drop_down, color: kAccent),
                                style: const TextStyle(color: Colors.white),
                                hint: const Text('Choose pickup room...', style: TextStyle(color: Color(0xFF8A94A6), fontSize: 13)),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: kNavyDark,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: _mapSelectFocus == 'pickup' ? Colors.green : Colors.white10,
                                      width: _mapSelectFocus == 'pickup' ? 2.0 : 1.0,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(color: kAccent, width: 2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(color: Colors.redAccent),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(color: Colors.redAccent, width: 2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onTap: () {
                                  setState(() {
                                    _mapSelectFocus = 'pickup';
                                  });
                                },
                                items: interactiveRooms.map<DropdownMenuItem<int>>((room) {
                                  return DropdownMenuItem<int>(
                                    value: room['id'] as int,
                                    child: Text(room['name'] as String),
                                  );
                                }).toList(),
                                onChanged: (int? newValue) {
                                  setState(() {
                                    _selectedPickupRoomId = newValue;
                                    _mapSelectFocus = 'pickup';
                                  });
                                  _formKey.currentState?.validate();
                                },
                                validator: (value) {
                                  if (value == null) {
                                    return 'Please select a pickup room';
                                  }
                                  if (value == _selectedRecipientRoomId) {
                                    return 'Pickup room cannot be the same as destination';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'Select Destination Room',
                                style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<int>(
                                value: _selectedRecipientRoomId,
                                dropdownColor: kNavyMid,
                                icon: const Icon(Icons.arrow_drop_down, color: kAccent),
                                style: const TextStyle(color: Colors.white),
                                hint: const Text('Choose destination room...', style: TextStyle(color: Color(0xFF8A94A6), fontSize: 13)),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: kNavyDark,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: _mapSelectFocus == 'recipient' ? Colors.redAccent : Colors.white10,
                                      width: _mapSelectFocus == 'recipient' ? 2.0 : 1.0,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(color: kAccent, width: 2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(color: Colors.redAccent),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(color: Colors.redAccent, width: 2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onTap: () {
                                  setState(() {
                                    _mapSelectFocus = 'recipient';
                                  });
                                },
                                items: interactiveRooms.where((r) => r['is_robot_home'] == false).map<DropdownMenuItem<int>>((room) {
                                  return DropdownMenuItem<int>(
                                    value: room['id'] as int,
                                    child: Text(room['name'] as String),
                                  );
                                }).toList(),
                                onChanged: (int? newValue) {
                                  setState(() {
                                    _selectedRecipientRoomId = newValue;
                                    _mapSelectFocus = 'recipient';
                                  });
                                  _formKey.currentState?.validate();
                                },
                                validator: (value) {
                                  if (value == null) {
                                    return 'Please select a destination room';
                                  }
                                  if (value == _selectedPickupRoomId) {
                                    return 'Destination room cannot be the same as pickup';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                            ],

                            // Dynamic Helper Instructions & Status Card
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: kNavyDark.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Selection Status',
                                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const SizedBox(height: 10),
                                  _buildSelectionStatusWidget(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            const SizedBox(height: 32),
                            // Submit Button
                            ElevatedButton.icon(
                              onPressed: _isSubmitting || !_isSelectionComplete() ? null : _showDispatchOptionsDialog,
                              icon: _isSubmitting 
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kNavyDark))
                                  : const Icon(Icons.local_shipping_rounded),
                              label: const Text('Confirm Delivery'),
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
                ),
                ],
              ),
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

  Widget _buildInteractiveRoomOverlay(Map<String, dynamic> room, double parentWidth, double parentHeight) {
    // Check if room coordinates exist
    final double? labelX = room['label_x'] != null ? (room['label_x'] as num).toDouble() : null;
    final double? labelY = room['label_y'] != null ? (room['label_y'] as num).toDouble() : null;
    final double? regW = room['region_width'] != null ? (room['region_width'] as num).toDouble() : null;
    final double? regH = room['region_height'] != null ? (room['region_height'] as num).toDouble() : null;

    // Do not draw if not configured visually by admin
    if (labelX == null || labelY == null || regW == null || regH == null) {
      return const SizedBox.shrink();
    }

    final double left = labelX * parentWidth;
    final double top = labelY * parentHeight;
    final double width = regW * parentWidth;
    final double height = regH * parentHeight;

    final Color roomColor = _getRoomColor(room);

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            // The floor map is display-only. Tapping has no effect on selections.
          },
          child: Container(
            decoration: BoxDecoration(
              color: roomColor.withOpacity(0.35),
              border: Border.all(color: roomColor, width: 1.5),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: roomColor.withOpacity(0.4),
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

  Widget _buildSelectionStatusWidget() {
    if (_deliveryType == 'home_to_room') {
      if (_selectedRecipientRoomId == null) {
        return const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: kAccent, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Pickup from Robot Room is active. Select the destination room from the dropdown menu.',
                style: TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ),
          ],
        );
      } else {
        final destMatches = _rooms.where((r) => r['id'] == _selectedRecipientRoomId);
        final destRoom = destMatches.isNotEmpty ? destMatches.first : null;
        final destName = destRoom != null ? destRoom['name'] : 'Room';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusLine('Pickup', 'Robot Room', Colors.blue),
            const SizedBox(height: 8),
            _buildStatusLine('Deliver to', destName, Colors.redAccent),
          ],
        );
      }
    } else {
      // Room to room status
      if (_selectedPickupRoomId == null) {
        return const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Colors.green, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Select a pickup room from the dropdown menu.',
                style: TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ),
          ],
        );
      } else if (_selectedRecipientRoomId == null) {
        final pickupMatches = _rooms.where((r) => r['id'] == _selectedPickupRoomId);
        final pickupRoom = pickupMatches.isNotEmpty ? pickupMatches.first : null;
        final pickupName = pickupRoom != null ? pickupRoom['name'] : 'Room';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusLine('Pickup', pickupName, Colors.green),
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.redAccent, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Select the destination room from the dropdown menu.',
                    style: TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ],
        );
      } else {
        final pickupMatches = _rooms.where((r) => r['id'] == _selectedPickupRoomId);
        final pickupRoom = pickupMatches.isNotEmpty ? pickupMatches.first : null;
        final pickupName = pickupRoom != null ? pickupRoom['name'] : 'Room';
        final destMatches = _rooms.where((r) => r['id'] == _selectedRecipientRoomId);
        final destRoom = destMatches.isNotEmpty ? destMatches.first : null;
        final destName = destRoom != null ? destRoom['name'] : 'Room';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusLine('Pickup', pickupName, Colors.green),
            const SizedBox(height: 8),
            _buildStatusLine('Deliver to', destName, Colors.redAccent),
          ],
        );
      }
    }
  }

  Widget _buildStatusLine(String label, String roomName, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        Expanded(
          child: Text(
            roomName,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
      ],
    );
  }

  bool _isSelectionComplete() {
    if (_deliveryType == 'home_to_room') {
      return _selectedRecipientRoomId != null;
    } else {
      return _selectedPickupRoomId != null && _selectedRecipientRoomId != null;
    }
  }
}
