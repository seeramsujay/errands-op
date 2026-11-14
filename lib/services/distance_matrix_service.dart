import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../core/geohash.dart';
import '../core/haversine.dart';
import '../data/database/app_database.dart';

class MatrixResult {
  final List<List<double>> distances; // In meters
  final List<List<double>> durations; // In seconds

  const MatrixResult({required this.distances, required this.durations});
}

/// Geospatial Matrix Engine with Geohash Caching, 500m displacement checks,
/// and Haversine tortuosity fallback.
///
/// Only road-network results from the external routing server are cached
/// (keyed by 6-char geohash cells, 7-day TTL); they are the expensive part.
/// Haversine estimates are recomputed from exact coordinates every time.
class DistanceMatrixService {
  final AppDatabase database;
  String? osrmEndpoint; // Optional external OSRM-compatible /table server
  final http.Client _http;

  List<double>? _lastOriginCoords;

  DistanceMatrixService({
    required this.database,
    this.osrmEndpoint,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

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
    final known = List.generate(n, (_) => List.filled(n, false));

    if (nodes.isNotEmpty) {
      _lastOriginCoords = [nodes[0][0], nodes[0][1]];
    }

    final cells = [
      for (final c in nodes)
        Geohash.encode(c[0], c[1], precision: AppConstants.geohashPrecision),
    ];
    final hasServer = osrmEndpoint != null && osrmEndpoint!.isNotEmpty;

    // 1. Cached road-network legs. Same-cell pairs are skipped: a cell is
    // ~1.2 km wide, so the cache can't tell two nearby stores apart.
    var missing = 0;
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        if (i == j) {
          known[i][j] = true;
          continue;
        }
        if (!hasServer || cells[i] == cells[j]) continue;
        final cached = await database.getCachedMatrix(cells[i], cells[j]);
        if (cached != null) {
          distances[i][j] = cached['distance']!;
          durations[i][j] = cached['duration']!;
          known[i][j] = true;
        } else {
          missing++;
        }
      }
    }

    // 2. Ask the routing server for anything not cached.
    if (hasServer && missing > 0) {
      try {
        final result = await _fetchExternalMatrix(nodes);
        if (result != null) {
          for (var i = 0; i < n; i++) {
            for (var j = 0; j < n; j++) {
              final d = result.distances[i][j];
              final t = result.durations[i][j];
              if (i == j || known[i][j] || d == null || t == null) continue;
              distances[i][j] = d;
              durations[i][j] = t;
              known[i][j] = true;
              if (cells[i] != cells[j]) {
                await database.cacheMatrixResult(cells[i], cells[j], d, t);
              }
            }
          }
        }
      } catch (_) {
        // Offline or server error: fall through to the Haversine estimate.
      }
    }

    // 3. Haversine fallback with road tortuosity for whatever is left.
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        if (known[i][j]) continue;
        distances[i][j] = HaversineUtils.roadDistance(
          nodes[i][0],
          nodes[i][1],
          nodes[j][0],
          nodes[j][1],
        );
        durations[i][j] = HaversineUtils.travelDurationSeconds(
          nodes[i][0],
          nodes[i][1],
          nodes[j][0],
          nodes[j][1],
        );
      }
    }

    return MatrixResult(distances: distances, durations: durations);
  }

  Future<({List<List<double?>> distances, List<List<double?>> durations})?>
  _fetchExternalMatrix(List<List<double>> nodes) async {
    final base = osrmEndpoint!.endsWith('/')
        ? osrmEndpoint!.substring(0, osrmEndpoint!.length - 1)
        : osrmEndpoint!;
    final coordStr = nodes.map((c) => '${c[1]},${c[0]}').join(';');
    final url = Uri.parse(
      '$base/table/v1/driving/$coordStr?annotations=distance,duration',
    );

    final response = await _http.get(url).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['code'] != 'Ok') return null;

    // OSRM returns null for unreachable pairs.
    List<List<double?>> parse(Object? table) => (table as List)
        .map(
          (row) => (row as List).map((v) => (v as num?)?.toDouble()).toList(),
        )
        .toList();
    return (
      distances: parse(json['distances']),
      durations: parse(json['durations']),
    );
  }
}
