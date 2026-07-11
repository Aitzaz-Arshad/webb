import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import 'package:path_planning/models/map_data.dart';
import 'package:logger/logger.dart';

class ApiService {
  final Logger _logger = Logger();
  
  // ✓ CHANGED: Back to localhost from Firebase
  final String _baseUrl = 'http://localhost:5000';
  // Previous Firebase URL was: 'https://autonomous-robot-2b4c4.web.app'
  
  final Uuid _uuid = Uuid();

  Future<dynamic> _sendA2ATask(
    String operation,
    Map<String, dynamic> params,
  ) async {
    final discoveryUrl = '$_baseUrl/.well-known/agent.json';
    final taskUrl = '$_baseUrl/tasks/send';

    // Discover the agent with retry
    const maxRetries = 3;
    dynamic agentInfo;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      _logger.d('Discovery attempt $attempt for URL: $discoveryUrl');
      final discoveryResponse = await http.get(Uri.parse(discoveryUrl));
      _logger.d(
        'Discovery status: ${discoveryResponse.statusCode}, body preview: ${discoveryResponse.body.substring(0, min(200, discoveryResponse.body.length))}...',
      );
      if (discoveryResponse.statusCode == 200) {
        try {
          agentInfo = json.decode(discoveryResponse.body);
          _logger.i(
            'Connected to A2A agent: ${agentInfo['name']} - ${agentInfo['description']}',
          );
          break;
        } catch (e) {
          throw Exception(
            'Failed to parse agent info: ${discoveryResponse.body}, error: $e',
          );
        }
      } else if (attempt == maxRetries) {
        throw Exception(
          'Failed to discover A2A agent after $maxRetries attempts: Status ${discoveryResponse.statusCode}, Body: ${discoveryResponse.body}',
        );
      }
      await Future.delayed(Duration(seconds: 1)); // Wait before retry
    }

    // Prepare the task
    final taskId = _uuid.v4();
    final taskPayload = {
      'id': taskId,
      'message': {
        'role': 'user',
        'parts': [
          {'text': operation},
          {'text': json.encode(params)},
        ],
      },
    };

    // Send the task
    _logger.d('Sending A2A task for $operation: $taskPayload');
    final taskResponse = await http.post(
      Uri.parse(taskUrl),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(taskPayload),
    );
    _logger.d(
      'Task response status: ${taskResponse.statusCode}, body: ${taskResponse.body}',
    );
    if (taskResponse.statusCode != 200) {
      throw Exception('A2A task failed for $operation: ${taskResponse.body}');
    }

    // Parse the response
    dynamic responseData;
    try {
      responseData = json.decode(taskResponse.body);
    } catch (e) {
      throw Exception(
        'Failed to parse raw A2A response for $operation: ${taskResponse.body}, error: $e',
      );
    }
    _logger.d('Raw A2A response for $operation: $responseData');

    // Validate response structure
    if (responseData is! Map<String, dynamic> ||
        !responseData.containsKey('messages')) {
      throw Exception(
        'Invalid A2A response format for $operation: $responseData',
      );
    }
    final messages = responseData['messages'] as List;
    if (messages.isEmpty ||
        messages.last['parts'] == null ||
        (messages.last['parts'] as List).isEmpty) {
      throw Exception(
        'No valid parts in A2A response for $operation: $responseData',
      );
    }
    final responseText = messages.last['parts'][0]['text'] as String?;
    if (responseText == null) {
      throw Exception(
        'No text in A2A response parts for $operation: $responseData',
      );
    }

    // Parse the response text
    dynamic parsedData;
    try {
      parsedData = json.decode(responseText);
      _logger.d(
        'Parsed A2A data for $operation: $parsedData, type: ${parsedData.runtimeType}',
      );
    } catch (e) {
      throw Exception(
        'Failed to parse A2A response text for $operation: $responseText, error: $e',
      );
    }
    return parsedData;
  }

  Future<Map<String, dynamic>> getPath(MapData mapData) async {
    final data = await _sendA2ATask('plan-path', mapData.toJson());
    if (data is! Map<String, dynamic>) {
      throw Exception(
        'Unexpected response format for plan-path: $data, type: ${data.runtimeType}',
      );
    }
    List<LatLng> path = (data['path'] as List)
        .map(
          (p) => LatLng(
            (p['latitude'] as num).toDouble(),
            (p['longitude'] as num).toDouble(),
          ),
        )
        .toList();
    List<LatLng> prunedPath = (data['pruned_path'] as List)
        .map(
          (p) => LatLng(
            (p['latitude'] as num).toDouble(),
            (p['longitude'] as num).toDouble(),
          ),
        )
        .toList();

    // Parse the smooth_path
    List<LatLng> smoothPath = (data['smooth_path'] as List)
        .map(
          (p) => LatLng(
            (p['latitude'] as num).toDouble(),
            (p['longitude'] as num).toDouble(),
          ),
        )
        .toList();

    // Parse the control_path
    List<LatLng> controlPath = (data['control_path'] as List)
        .map(
          (p) => LatLng(
            (p['latitude'] as num).toDouble(),
            (p['longitude'] as num).toDouble(),
          ),
        )
        .toList();

    return {
      'path': path,
      'pruned_path': prunedPath,
      'smooth_path': smoothPath,
      'control_path': controlPath,
    };
  }

  Future<Map<String, dynamic>> getPathWithDP(MapData mapData) async {
    final data = await _sendA2ATask('plan-path-dp', mapData.toJson());
    if (data is! Map<String, dynamic>) {
      throw Exception(
        'Unexpected response format for plan-path-dp: $data, type: ${data.runtimeType}',
      );
    }
    List<LatLng> path = (data['path'] as List)
        .map(
          (p) => LatLng(
            (p['latitude'] as num).toDouble(),
            (p['longitude'] as num).toDouble(),
          ),
        )
        .toList();
    List<LatLng> prunedPath = (data['pruned_path'] as List)
        .map(
          (p) => LatLng(
            (p['latitude'] as num).toDouble(),
            (p['longitude'] as num).toDouble(),
          ),
        )
        .toList();
    return {'path': path, 'pruned_path': prunedPath};
  }

  Future<Map<String, dynamic>> getGridData(MapData mapData) async {
    final data = await _sendA2ATask('get-grid', mapData.toJson());
    if (data is! Map<String, dynamic>) {
      throw Exception(
        'Unexpected response format for get-grid: $data, type: ${data.runtimeType}',
      );
    }
    if (data.containsKey('error')) {
      throw Exception('Server error for get-grid: ${data['error']}');
    }
    _logger.i('Fetched grid data: ${data['total_cells']} cells');
    return data;
  }

  Future<void> saveMap(MapData mapData) async {
    final data = await _sendA2ATask('save-map', mapData.toJson());
    if (data is Map<String, dynamic> && data.containsKey('error')) {
      throw Exception('Server error for save-map: ${data['error']}');
    }
    _logger.i('Saved map: ${mapData.name}');
  }

  Future<Map<String, dynamic>> loadMap(String name) async {
    final data = await _sendA2ATask('load-map', {'name': name});
    if (data is Map<String, dynamic> && data.containsKey('error')) {
      throw Exception('Server error for load-map: ${data['error']}');
    }
    return data as Map<String, dynamic>;
  }

  Future<List<String>> listMaps() async {
    final data = await _sendA2ATask('list-maps', {});
    _logger.d('listMaps raw data: $data, type: ${data.runtimeType}');
    if (data is List) {
      return List<String>.from(data.cast<String>());
    } else if (data is Map<String, dynamic> && data.containsKey('maps')) {
      return List<String>.from(data['maps'] as List);
    } else if (data is Map<String, dynamic> && data.containsKey('error')) {
      throw Exception('Server error for list-maps: ${data['error']}');
    } else {
      throw Exception(
        'Unexpected response format for list-maps: $data, type: ${data.runtimeType}',
      );
    }
  }

  Future<void> deleteMap(String name) async {
    final data = await _sendA2ATask('delete-map', {'name': name});
    if (data is Map<String, dynamic> && data.containsKey('error')) {
      throw Exception('Server error for delete-map: ${data['error']}');
    }
    _logger.i('Deleted map: $name');
  }

  Future<Map<String, dynamic>> uploadPcd(
    String name,
    double refLat,
    double refLon,
    Uint8List? fileBytes,
    String fileName,
  ) async {
    if (fileBytes == null || fileBytes.isEmpty) {
      throw Exception('File bytes are null or empty');
    }
    final url = Uri.parse('$_baseUrl/upload-pcd');
    var request = http.MultipartRequest('POST', url);
    request.fields['name'] = name;
    request.fields['ref_lat'] = refLat.toString();
    request.fields['ref_lon'] = refLon.toString();
    request.fields['task_id'] = _uuid.v4();
    request.files.add(
      http.MultipartFile.fromBytes(
        'pcd_file',
        fileBytes,
        filename: fileName,
        contentType: MediaType('application', 'octet-stream'),
      ),
    );
    try {
      final response = await request.send();
      final respStr = await response.stream.bytesToString();
      _logger.d('PCD response status: ${response.statusCode}, body: $respStr');
      if (response.statusCode != 200) {
        final error = json.decode(respStr);
        throw Exception(
          'Failed to upload PCD: ${error['error'] ?? 'Unknown error'}. Status code: ${response.statusCode}',
        );
      }
      final data = json.decode(respStr);
      _logger.d('Raw PCD response: $data');
      final messages = data['messages'] as List;
      if (messages.isEmpty || messages.last['parts'].isEmpty) {
        throw Exception('No response received from PCD upload: $data');
      }
      final responseText = messages.last['parts'][0]['text'] as String?;
      if (responseText == null) {
        throw Exception('No text in PCD response parts: $data');
      }
      try {
        final parsedData = json.decode(responseText);
        _logger.d('Parsed PCD data: $parsedData');
        return parsedData as Map<String, dynamic>;
      } catch (e) {
        throw Exception(
          'Failed to parse PCD response text: $responseText, error: $e',
        );
      }
    } catch (e) {
      _logger.e('Error uploading PCD: $e');
      throw Exception('Failed to upload PCD: $e');
    }
  }

  // --- REST API FOR AUTONOMOUS DELIVERY SYSTEM ---

  Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password,
    String role,
  ) async {
    final url = Uri.parse('$_baseUrl/auth/register');
    _logger.d('Registering user: $email ($role)');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'name': name,
        'email': email,
        'password': password,
        'role': role,
      }),
    );
    final data = json.decode(response.body);
    if (response.statusCode != 201) {
      throw Exception(data['error'] ?? 'Registration failed');
    }
    return data;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final url = Uri.parse('$_baseUrl/auth/login');
    _logger.d('Logging in user: $email');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'email': email,
        'password': password,
      }),
    );
    final data = json.decode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Login failed');
    }
    return data;
  }

  Future<List<dynamic>> getRooms({bool public = false, int? requesterId, String? requesterRole}) async {
    final Map<String, String> headers = {'Content-Type': 'application/json'};
    if (requesterId != null && requesterRole != null) {
      headers['X-User-Id'] = requesterId.toString();
      headers['X-User-Role'] = requesterRole;
    }
    
    final url = Uri.parse('$_baseUrl/rooms${public ? "?public=true" : ""}');
    final response = await http.get(url, headers: headers);
    if (response.statusCode != 200) {
      throw Exception(json.decode(response.body)['error'] ?? 'Failed to load rooms');
    }
    return json.decode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> createRoom(
    String name,
    double x,
    double y,
    double theta,
    bool isRobotHome, {
    double? labelX,
    double? labelY,
    double? regionWidth,
    double? regionHeight,
  }) async {
    final url = Uri.parse('$_baseUrl/rooms');
    _logger.d('Creating room: $name ($x, $y)');
    final Map<String, dynamic> body = {
      'name': name,
      'x': x,
      'y': y,
      'theta': theta,
      'is_robot_home': isRobotHome,
    };
    if (labelX != null) body['label_x'] = labelX;
    if (labelY != null) body['label_y'] = labelY;
    if (regionWidth != null) body['region_width'] = regionWidth;
    if (regionHeight != null) body['region_height'] = regionHeight;

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    final data = json.decode(response.body);
    if (response.statusCode != 201) {
      throw Exception(data['error'] ?? 'Failed to create room');
    }
    return data;
  }

  Future<Map<String, dynamic>> updateRoom(
    int requesterId,
    String requesterRole,
    int roomId, {
    String? name,
    double? x,
    double? y,
    double? theta,
    bool? isRobotHome,
    double? labelX,
    double? labelY,
    double? regionWidth,
    double? regionHeight,
  }) async {
    final url = Uri.parse('$_baseUrl/rooms/$roomId');
    _logger.d('Updating room $roomId');
    final Map<String, dynamic> body = {};
    if (name != null) body['name'] = name;
    if (x != null) body['x'] = x;
    if (y != null) body['y'] = y;
    if (theta != null) body['theta'] = theta;
    if (isRobotHome != null) body['is_robot_home'] = isRobotHome;
    if (labelX != null) body['label_x'] = labelX;
    if (labelY != null) body['label_y'] = labelY;
    if (regionWidth != null) body['region_width'] = regionWidth;
    if (regionHeight != null) body['region_height'] = regionHeight;

    final response = await http.put(
      url,
      headers: {
        'Content-Type': 'application/json',
        'X-User-Id': requesterId.toString(),
        'X-User-Role': requesterRole,
      },
      body: json.encode(body),
    );
    final data = json.decode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Failed to update room');
    }
    return data;
  }

  Future<void> deleteRoom(int roomId) async {
    final url = Uri.parse('$_baseUrl/rooms/$roomId');
    final response = await http.delete(url);
    if (response.statusCode != 200) {
      throw Exception(json.decode(response.body)['error'] ?? 'Failed to delete room');
    }
  }

  Future<Map<String, dynamic>> createDelivery(
    int senderId,
    int recipientRoomId,
    int? pickupRoomId,
    String deliveryType,
    String recipientName, {
    DateTime? scheduledAt,
  }) async {
    final url = Uri.parse('$_baseUrl/deliveries');
    _logger.d('Requesting delivery: $deliveryType to $recipientName, scheduled: $scheduledAt');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'sender_id': senderId,
        'recipient_room_id': recipientRoomId,
        'pickup_room_id': pickupRoomId,
        'delivery_type': deliveryType,
        'recipient_name': recipientName,
        'scheduled_at': scheduledAt?.toIso8601String(),
      }),
    );
    final data = json.decode(response.body);
    if (response.statusCode != 201) {
      throw Exception(data['error'] ?? 'Failed to create delivery');
    }
    return data;
  }

  Future<List<dynamic>> getDeliveries({
    int? requesterId,
    String? requesterRole,
    int? senderId,
    String? status,
    String? dateFrom,
    String? dateTo,
  }) async {
    final List<String> params = [];
    if (senderId != null) params.add('sender_id=$senderId');
    if (status != null) params.add('status=$status');
    if (dateFrom != null) params.add('date_from=$dateFrom');
    if (dateTo != null) params.add('date_to=$dateTo');
    
    final query = params.isEmpty ? '' : '?${params.join('&')}';
    final url = Uri.parse('$_baseUrl/deliveries$query');
    
    final Map<String, String> headers = {'Content-Type': 'application/json'};
    if (requesterId != null && requesterRole != null) {
      headers['X-User-Id'] = requesterId.toString();
      headers['X-User-Role'] = requesterRole;
    }

    final response = await http.get(url, headers: headers);
    if (response.statusCode != 200) {
      throw Exception(json.decode(response.body)['error'] ?? 'Failed to load deliveries');
    }
    return json.decode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> updateDeliveryStatus(
    int deliveryId,
    String status,
  ) async {
    final url = Uri.parse('$_baseUrl/deliveries/$deliveryId');
    _logger.d('Updating delivery $deliveryId status to: $status');
    final response = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'status': status}),
    );
    final data = json.decode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Failed to update delivery');
    }
    return data;
  }

  Future<List<dynamic>> getUsers(int requesterId, String requesterRole) async {
    final url = Uri.parse('$_baseUrl/users');
    final response = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        'X-User-Id': requesterId.toString(),
        'X-User-Role': requesterRole,
      },
    );
    if (response.statusCode != 200) {
      throw Exception(json.decode(response.body)['error'] ?? 'Failed to load users');
    }
    return json.decode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> updateUser(
    int requesterId,
    String requesterRole,
    int targetUserId, {
    String? role,
    bool? isActive,
  }) async {
    final url = Uri.parse('$_baseUrl/users/$targetUserId');
    _logger.d('Updating user $targetUserId: role=$role, isActive=$isActive');
    final Map<String, dynamic> body = {};
    if (role != null) body['role'] = role;
    if (isActive != null) body['is_active'] = isActive;

    final response = await http.put(
      url,
      headers: {
        'Content-Type': 'application/json',
        'X-User-Id': requesterId.toString(),
        'X-User-Role': requesterRole,
      },
      body: json.encode(body),
    );
    final data = json.decode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Failed to update user');
    }
    return data;
  }
}