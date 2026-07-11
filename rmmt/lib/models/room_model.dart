// lib/models/room_model.dart

class RoomModel {
  final int id;
  final String name;
  final double x;
  final double y;
  final double theta;
  final bool isRobotHome;

  RoomModel({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.theta,
    required this.isRobotHome,
  });

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    return RoomModel(
      id: json['id'],
      name: json['name'],
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      theta: (json['theta'] as num).toDouble(),
      isRobotHome: json['is_robot_home'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'x': x,
      'y': y,
      'theta': theta,
      'is_robot_home': isRobotHome,
    };
  }
}
