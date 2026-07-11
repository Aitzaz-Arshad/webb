// lib/utils/geo_utils.dart

import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

class GeoUtils {
  static double calculateDistance(LatLng pos1, LatLng pos2) {
    const distance = Distance();
    return distance.as(LengthUnit.Meter, pos1, pos2);
  }

  // Convert LatLng to meters relative to a reference coordinate
  static Map<String, double> latLngToMeters(LatLng point, LatLng ref) {
    final double refLatRad = ref.latitude * math.pi / 180.0;
    final double mPerDegLat = 111132.954 - 559.822 * math.cos(2 * refLatRad) + 1.175 * math.cos(4 * refLatRad);
    final double mPerDegLon = 111319.488 * math.cos(refLatRad);
    
    final double x = (point.longitude - ref.longitude) * mPerDegLon;
    final double y = (point.latitude - ref.latitude) * mPerDegLat;
    return {'x': x, 'y': y};
  }

  // Convert meters relative to a reference coordinate back to LatLng
  static LatLng metersToLatLng(double x, double y, LatLng ref) {
    final double refLatRad = ref.latitude * math.pi / 180.0;
    final double mPerDegLat = 111132.954 - 559.822 * math.cos(2 * refLatRad) + 1.175 * math.cos(4 * refLatRad);
    final double mPerDegLon = 111319.488 * math.cos(refLatRad);
    
    final double lon = x / mPerDegLon + ref.longitude;
    final double lat = y / mPerDegLat + ref.latitude;
    return LatLng(lat, lon);
  }
}