import 'store.dart';
import 'todo_item.dart';

/// Single stop along an active errand itinerary
class RouteStop {
  final String id;
  final String routeId;
  final int stopSequence;
  final String storeId;
  final DateTime estimatedArrival;
  final DateTime estimatedDeparture;
  final bool isCompleted;

  // Joined/populated metadata for visual overlays
  final Store? store;
  final List<TodoItem> itemsToPick;
  final bool hasPerishable;
  final bool isUserPinned;
  final bool violatesClosingTime;
  final int waitSeconds; // Waiting for the store to open
  final String? warningMessage;

  const RouteStop({
    required this.id,
    required this.routeId,
    required this.stopSequence,
    required this.storeId,
    required this.estimatedArrival,
    required this.estimatedDeparture,
    this.isCompleted = false,
    this.store,
    this.itemsToPick = const [],
    this.hasPerishable = false,
    this.isUserPinned = false,
    this.violatesClosingTime = false,
    this.waitSeconds = 0,
    this.warningMessage,
  });

  RouteStop copyWith({
    String? id,
    String? routeId,
    int? stopSequence,
    String? storeId,
    DateTime? estimatedArrival,
    DateTime? estimatedDeparture,
    bool? isCompleted,
    Store? store,
    List<TodoItem>? itemsToPick,
    bool? hasPerishable,
    bool? isUserPinned,
    bool? violatesClosingTime,
    int? waitSeconds,
    String? warningMessage,
  }) {
    return RouteStop(
      id: id ?? this.id,
      routeId: routeId ?? this.routeId,
      stopSequence: stopSequence ?? this.stopSequence,
      storeId: storeId ?? this.storeId,
      estimatedArrival: estimatedArrival ?? this.estimatedArrival,
      estimatedDeparture: estimatedDeparture ?? this.estimatedDeparture,
      isCompleted: isCompleted ?? this.isCompleted,
      store: store ?? this.store,
      itemsToPick: itemsToPick ?? this.itemsToPick,
      hasPerishable: hasPerishable ?? this.hasPerishable,
      isUserPinned: isUserPinned ?? this.isUserPinned,
      violatesClosingTime: violatesClosingTime ?? this.violatesClosingTime,
      waitSeconds: waitSeconds ?? this.waitSeconds,
      warningMessage: warningMessage ?? this.warningMessage,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'route_id': routeId,
      'stop_sequence': stopSequence,
      'store_id': storeId,
      'estimated_arrival': estimatedArrival.toIso8601String(),
      'estimated_departure': estimatedDeparture.toIso8601String(),
      'is_completed': isCompleted ? 1 : 0,
      'item_ids': itemsToPick.map((i) => i.id).join(','),
      'has_perishable': hasPerishable ? 1 : 0,
      'is_user_pinned': isUserPinned ? 1 : 0,
      'violates_closing_time': violatesClosingTime ? 1 : 0,
      'wait_seconds': waitSeconds,
      'warning_message': warningMessage,
    };
  }

  /// Item ids persisted for this stop (resolved against the items table on load).
  static List<String> itemIdsFromMap(Map<String, dynamic> map) {
    final raw = map['item_ids'] as String?;
    if (raw == null || raw.isEmpty) return const [];
    return raw.split(',');
  }

  factory RouteStop.fromMap(
    Map<String, dynamic> map, {
    Store? store,
    List<TodoItem> itemsToPick = const [],
  }) {
    return RouteStop(
      id: map['id'] as String,
      routeId: map['route_id'] as String,
      stopSequence: map['stop_sequence'] as int,
      storeId: map['store_id'] as String,
      estimatedArrival: DateTime.parse(map['estimated_arrival'] as String),
      estimatedDeparture: DateTime.parse(map['estimated_departure'] as String),
      isCompleted: (map['is_completed'] as int? ?? 0) == 1,
      store: store,
      itemsToPick: itemsToPick,
      hasPerishable: (map['has_perishable'] as int? ?? 0) == 1,
      isUserPinned: (map['is_user_pinned'] as int? ?? 0) == 1,
      violatesClosingTime: (map['violates_closing_time'] as int? ?? 0) == 1,
      waitSeconds: map['wait_seconds'] as int? ?? 0,
      warningMessage: map['warning_message'] as String?,
    );
  }
}
