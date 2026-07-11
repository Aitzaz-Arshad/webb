// lib/models/obstacle.dart
import 'package:latlong2/latlong.dart';

enum ObstacleType { rectangle, circle, polygon } // 'polygon' included

class Obstacle {
  final ObstacleType type;
  final List<LatLng>? points;
  final LatLng? center;
  final double? radius;

  Obstacle({required this.type, this.points, this.center, this.radius});

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {'type': type.toString().split('.').last};
    if (type == ObstacleType.rectangle || type == ObstacleType.polygon) {
      json['points'] = points
          ?.map((p) => {'latitude': p.latitude, 'longitude': p.longitude})
          .toList();
    } else if (type == ObstacleType.circle) {
      json['center'] = center != null
          ? {'latitude': center!.latitude, 'longitude': center!.longitude}
          : null;
      json['radius'] = radius;
    }
    return json;
  }

  factory Obstacle.fromJson(Map<String, dynamic> json) {
    final String typeStr = json['type'] as String? ?? 'rectangle';
    final ObstacleType type = ObstacleType.values.firstWhere(
      (t) => t.toString().split('.').last == typeStr,
      orElse: () => ObstacleType.rectangle,
    );

    switch (type) {
      case ObstacleType.rectangle:
      case ObstacleType.polygon: // Handles polygon data from the PCD server
        final pointsList = json['points'] as List?;
        return Obstacle(
          type: type,
          points: pointsList
              ?.map((p) {
                final lat = (p?['latitude'] as num?)?.toDouble();
                final lon = (p?['longitude'] as num?)?.toDouble();
                return lat != null && lon != null ? LatLng(lat, lon) : null;
              })
              .whereType<LatLng>()
              .toList(),
        );
      case ObstacleType.circle:
        final centerMap = json['center'] as Map<String, dynamic>?;
        final lat = (centerMap?['latitude'] as num?)?.toDouble();
        final lon = (centerMap?['longitude'] as num?)?.toDouble();
        return Obstacle(
          type: ObstacleType.circle,
          center: lat != null && lon != null ? LatLng(lat, lon) : null,
          radius: (json['radius'] as num?)?.toDouble(),
        );
    }
  }
}
