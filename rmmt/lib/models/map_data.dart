// lib/models/map_data.dart

import 'package:latlong2/latlong.dart';
import 'package:path_planning/models/obstacle.dart';

class MapData {
  String name;
  Obstacle boundary;
  List<Obstacle> obstacles;
  LatLng? startPoint;
  LatLng? endPoint;

  MapData({
    required this.name,
    required this.boundary,
    required this.obstacles,
    this.startPoint,
    this.endPoint,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'boundary': boundary.toJson(),
      'obstacles': obstacles.map((o) => o.toJson()).toList(),
      'start': startPoint != null
          ? {
              'latitude': startPoint!.latitude,
              'longitude': startPoint!.longitude,
            }
          : null,
      'goal': endPoint != null
          ? {'latitude': endPoint!.latitude, 'longitude': endPoint!.longitude}
          : null,
    };
  }

  factory MapData.fromJson(Map<String, dynamic> json) {
    return MapData(
      name: json['name'],
      boundary: Obstacle.fromJson(json['boundary']),
      obstacles: (json['obstacles'] as List)
          .map((o) => Obstacle.fromJson(o))
          .toList(),
      startPoint: json['start'] != null
          ? LatLng(json['start']['latitude'], json['start']['longitude'])
          : null,
      endPoint: json['goal'] != null
          ? LatLng(json['goal']['latitude'], json['goal']['longitude'])
          : null,
    );
  }
}
