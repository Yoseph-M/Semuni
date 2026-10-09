import '../../core/network/api_client.dart';

class MapDirectionResult {
  const MapDirectionResult({
    required this.distanceKm,
    required this.durationMinutes,
    required this.coordinates,
    this.source = 'gebeta',
  });

  final double distanceKm;
  final int durationMinutes;
  final List<MapLatLng> coordinates;
  final String source;
}

class MapLatLng {
  const MapLatLng(this.latitude, this.longitude);
  final double latitude;
  final double longitude;

  @override
  String toString() => '$latitude,$longitude';
}

class MapsApiService {
  MapsApiService({required this.client});

  final ApiClient client;

  Future<Map<String, dynamic>> getConfig() async {
    try {
      final res = await client.get('/maps/config');
      return res.asMap;
    } catch (_) {
      return {
        'configured': false,
        'styleUrl': 'https://tiles.gebeta.app/style.json',
        'defaultCenter': {'latitude': 9.0222, 'longitude': 38.7468},
        'defaultZoom': 12.5,
      };
    }
  }

  Future<MapDirectionResult?> getDirections({
    required double originLat,
    required double originLon,
    required double destinationLat,
    required double destinationLon,
  }) async {
    try {
      final origin = '$originLat,$originLon';
      final dest = '$destinationLat,$destinationLon';
      final res = await client.get(
        '/maps/directions?origin=$origin&destination=$dest',
      );
      final data = res.asMap;

      final coordsRaw = data['coordinates'] as List? ?? [];
      final coords = <MapLatLng>[];
      for (final pt in coordsRaw) {
        if (pt is List && pt.length >= 2) {
          // Gebeta/GeoJSON coordinates are [lon, lat]
          final lon = (pt[0] as num).toDouble();
          final lat = (pt[1] as num).toDouble();
          coords.add(MapLatLng(lat, lon));
        }
      }

      return MapDirectionResult(
        distanceKm: ((data['distanceKm'] as num?)?.toDouble()) ?? 0.0,
        durationMinutes: ((data['durationMinutes'] as num?)?.toInt()) ?? 15,
        coordinates: coords,
        source: data['source']?.toString() ?? 'unknown',
      );
    } catch (_) {
      return null;
    }
  }
}
