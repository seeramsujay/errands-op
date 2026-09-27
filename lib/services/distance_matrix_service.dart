import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../core/geohash.dart';
import '../core/haversine.dart';
import '../data/database/app_database.dart';

class MatrixResult {
  final List<List<double>> distances; // In meters
  final List<List<double>> durations; // In seconds

  const MatrixResult({
    required this.distances,
    required this.durations,
  });
}

/// Geospatial Matrix Engine with Geohash Caching, 500m displacement checks,
/// and Haversine tortuosity fallback.
class DistanceMatrixService {
  final AppDatabase database;
  final String? osrmEndpoint; // Optional external OSRM / GraphHopper server

  List<double>? _lastOriginCoords;

  DistanceMatrixService({
    required this.database,
    this.osrmEndpoint,
  });

  /// Check if physical displacement exceeds 500m threshold from last calculation
  bool shouldRecalculate(double currentLat, double currentLon) {
    if (_lastOriginCoords == null) return true;
    final displacement = HaversineUtils.directDistance(
      _lastOriginCoords![0],
      _lastOriginCoords![1],
      currentLat,
      currentLon,
    );
    return displacement > AppConstants.displacementThresholdMeters;
  }

  /// Compute N x N distance and duration matrix for a list of [lat, lon] coordinates
  Future<MatrixResult> computeMatrix(List<List<double>> nodes) async {
    final n = nodes.length;
    final distances = List.generate(n, (_) => List.filled(n, 0.0));
    final durations = List.generate(n, (_) => List.filled(n, 0.0));

    if (nodes.isNotEmpty) {
      _lastOriginCoords = [nodes[0][0], nodes[0][1]];
    }

    // Try external matrix API if configured
    if (osrmEndpoint != null && osrmEndpoint!.isNotEmpty) {
      try {
        final result = await _fetchExternalMatrix(nodes);
        if (result != null) return result;
      } catch (_) {
        // Fallback to local cached / Haversine calculation
      }
    }

    // Compute pairwise matrix with 6-char Geohash spatial caching & Haversine fallback
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        if (i == j) {
          distances[i][j] = 0.0;
          durations[i][j] = 0.0;
          continue;
        }

        final gOrigin = Geohash.encode(nodes[i][0], nodes[i][1], precision: AppConstants.geohashPrecision);
        final gDest = Geohash.encode(nodes[j][0], nodes[j][1], precision: AppConstants.geohashPrecision);

        // Check local database cache
        final cached = await database.getCachedMatrix(gOrigin, gDest);
        if (cached != null) {
          distances[i][j] = cached['distance']!;
          durations[i][j] = cached['duration']!;
        } else {
          // Haversine fallback with road tortuosity
          final dist = HaversineUtils.roadDistance(
            nodes[i][0],
            nodes[i][1],
            nodes[j][0],
            nodes[j][1],
          );
          final dur = HaversineUtils.travelDurationSeconds(
            nodes[i][0],
            nodes[i][1],
            nodes[j][0],
            nodes[j][1],
          );

          distances[i][j] = dist;
          durations[i][j] = dur;

          // Save to 7-day TTL cache
          await database.cacheMatrixResult(gOrigin, gDest, dist, dur);
        }
      }
    }

    return MatrixResult(distances: distances, durations: durations);
  }

  Future<MatrixResult?> _fetchExternalMatrix(List<List<double>> nodes) async {
    final coordStr = nodes.map((c) => '${c[1]},${c[0]}').join(';');
    final url = Uri.parse('$osrmEndpoint/table/v1/driving/$coordStr?annotations=distance,duration');

    final response = await http.get(url).timeout(const Duration(seconds: 3));
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['code'] == 'Ok') {
        final dists = (json['distances'] as List)
            .map((row) => (row as List).map((v) => (v as num).toDouble()).toList())
            .toList();
        final durs = (json['durations'] as List)
            .map((row) => (row as List).map((v) => (v as num).toDouble()).toList())
            .toList();
        return MatrixResult(distances: dists, durations: durs);
      }
    }
    return null;
  }
}
