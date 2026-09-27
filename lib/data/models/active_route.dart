import 'route_stop.dart';

/// Active Route Execution Record
class ActiveRoute {
  final String id;
  final DateTime generatedAt;
  final double totalDistanceMeters;
  final double totalDurationSeconds;
  final String solverStatus; // 'OPTIMAL', 'RELAXED_CONSTRAINTS', 'INFEASIBLE'
  final List<RouteStop> stops;
  final List<String> warnings;

  const ActiveRoute({
    required this.id,
    required this.generatedAt,
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
    required this.solverStatus,
    this.stops = const [],
    this.warnings = const [],
  });

  bool get hasWarnings => warnings.isNotEmpty || solverStatus == 'RELAXED_CONSTRAINTS';

  ActiveRoute copyWith({
    String? id,
    DateTime? generatedAt,
    double? totalDistanceMeters,
    double? totalDurationSeconds,
    String? solverStatus,
    List<RouteStop>? stops,
    List<String>? warnings,
  }) {
    return ActiveRoute(
      id: id ?? this.id,
      generatedAt: generatedAt ?? this.generatedAt,
      totalDistanceMeters: totalDistanceMeters ?? this.totalDistanceMeters,
      totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
      solverStatus: solverStatus ?? this.solverStatus,
      stops: stops ?? this.stops,
      warnings: warnings ?? this.warnings,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'generated_at': generatedAt.toIso8601String(),
      'total_distance_meters': totalDistanceMeters,
      'total_duration_seconds': totalDurationSeconds,
      'solver_status': solverStatus,
    };
  }

  factory ActiveRoute.fromMap(Map<String, dynamic> map, {List<RouteStop> stops = const []}) {
    return ActiveRoute(
      id: map['id'] as String,
      generatedAt: DateTime.parse(map['generated_at'] as String),
      totalDistanceMeters: (map['total_distance_meters'] as num).toDouble(),
      totalDurationSeconds: (map['total_duration_seconds'] as num).toDouble(),
      solverStatus: map['solver_status'] as String,
      stops: stops,
    );
  }
}
