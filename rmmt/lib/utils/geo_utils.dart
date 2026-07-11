// lib/utils/geo_utils.dart

import 'package:latlong2/latlong.dart';

class GeoUtils {
  static double calculateDistance(LatLng pos1, LatLng pos2) {
    const distance = Distance();
    return distance.as(LengthUnit.Meter, pos1, pos2);
  }
}