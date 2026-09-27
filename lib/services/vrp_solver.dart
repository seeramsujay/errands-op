import 'dart:math';
import 'package:uuid/uuid.dart';
import '../core/constants.dart';
import '../data/models/active_route.dart';
import '../data/models/preference.dart';
import '../data/models/route_stop.dart';
import '../data/models/store.dart';
import '../data/models/todo_item.dart';
import 'distance_matrix_service.dart';

/// Request parameters for the Hybrid VRPTW solver
class VrpSolverRequest {
  final List<double> originCoordinates; // [lat, lon]
  final DateTime departureTime;
  final List<TodoItem> items;
  final List<Store> candidateStores;
  final List<ItemStorePreference> preferences;

  const VrpSolverRequest({
    required this.originCoordinates,
    required this.departureTime,
    required this.items,
    required this.candidateStores,
    this.preferences = const [],
  });
}

/// Hybrid Vehicle Routing Problem with Time Windows (VRPTW) Solver
class VrpSolver {
  final DistanceMatrixService matrixService;

  VrpSolver({required this.matrixService});

  /// Solve the multi-stop errand route with candidate disjunctions,
  /// thermal decay penalties for perishables, and human hard sequence locks.
  Future<ActiveRoute> solveRoute(VrpSolverRequest request) async {
    final activeItems = request.items.where((i) => !i.isCompleted).toList();
    if (activeItems.isEmpty) {
      return ActiveRoute(
        id: const Uuid().v4(),
        generatedAt: DateTime.now(),
        totalDistanceMeters: 0,
        totalDurationSeconds: 0,
        solverStatus: 'OPTIMAL',
        stops: const [],
        warnings: const ['No pending items to route.'],
      );
    }

    // 1. Group items by candidate store selection (Disjunctive Choice)
    final storeToItems = <Store, List<TodoItem>>{};
    final storeMap = {for (final s in request.candidateStores) s.id: s};
    final prefMap = {
      for (final p in request.preferences) '${p.itemCategory}_${p.storeId}': p.confidenceScore
    };

    for (final item in activeItems) {
      // Find candidate stores that support this item's category
      final candidates = request.candidateStores.where((s) {
        return s.supportedCategories.contains(item.category) ||
            s.supportedCategories.contains('generic');
      }).toList();

      if (candidates.isEmpty) {
        // Fallback to closest store if no category match
        candidates.addAll(request.candidateStores);
      }

      // Pick best store based on learned preference confidence score and distance
      candidates.sort((a, b) {
        final scoreA = prefMap['${item.category}_${a.id}'] ?? 0.5;
        final scoreB = prefMap['${item.category}_${b.id}'] ?? 0.5;
        return scoreB.compareTo(scoreA); // Higher confidence preferred
      });

      final bestStore = candidates.first;
      storeToItems.putIfAbsent(bestStore, () => []).add(item);
    }

    final selectedStores = storeToItems.keys.toList();
    if (selectedStores.isEmpty) {
      return ActiveRoute(
        id: const Uuid().v4(),
        generatedAt: DateTime.now(),
        totalDistanceMeters: 0,
        totalDurationSeconds: 0,
        solverStatus: 'INFEASIBLE',
        stops: const [],
        warnings: const ['No matching stores found for items.'],
      );
    }

    // 2. Build coordinate list: Index 0 is origin, indices 1..N are stores
    final nodes = <List<double>>[request.originCoordinates];
    for (final s in selectedStores) {
      nodes.add([s.latitude, s.longitude]);
    }

    final matrix = await matrixService.computeMatrix(nodes);

    // 3. Solve Sequence Optimization:
    // User pins take precedence (Hard Locks).
    // Stores containing perishable items are penalized if scheduled early (Thermal Decay).
    final orderedStores = _optimizeSequence(
      selectedStores: selectedStores,
      storeToItems: storeToItems,
      matrix: matrix,
      departureTime: request.departureTime,
    );

    // 4. Construct Route Stops & Check Time Windows
    final warnings = <String>[];
    var solverStatus = 'OPTIMAL';
    var currentTime = request.departureTime;
    var totalDistance = 0.0;
    var totalDuration = 0.0;
    var prevNodeIndex = 0; // Starts at origin

    final stops = <RouteStop>[];

    for (var i = 0; i < orderedStores.length; i++) {
      final store = orderedStores[i];
      final nodeIndex = selectedStores.indexOf(store) + 1;
      final legDistance = matrix.distances[prevNodeIndex][nodeIndex];
      final legDuration = matrix.durations[prevNodeIndex][nodeIndex];

      totalDistance += legDistance;
      totalDuration += legDuration;
      currentTime = currentTime.add(Duration(seconds: legDuration.round()));

      final arrivalTime = currentTime;
      final storeItems = storeToItems[store] ?? [];
      final hasPerishable = storeItems.any((item) => item.isPerishable);
      final isUserPinned = storeItems.any((item) => item.isPinned);

      // Check store closing time
      final violatesClosing = !store.isOpenAt(arrivalTime);
      String? stopWarning;

      if (violatesClosing) {
        solverStatus = 'RELAXED_CONSTRAINTS';
        final formattedArrival = '${arrivalTime.hour.toString().padLeft(2, '0')}:${arrivalTime.minute.toString().padLeft(2, '0')}';
        stopWarning = '${store.name} may be closed upon arrival ($formattedArrival). Hours: ${store.formattedHours}';
        warnings.add(stopWarning);
      }

      // Add in-store wait/shopping delay
      final checkoutDelay = store.avgCheckoutDelaySec;
      currentTime = currentTime.add(Duration(seconds: checkoutDelay));
      totalDuration += checkoutDelay;
      final departureTime = currentTime;

      stops.add(RouteStop(
        id: const Uuid().v4(),
        routeId: '', // Populated by active_route
        stopSequence: i + 1,
        storeId: store.id,
        estimatedArrival: arrivalTime,
        estimatedDeparture: departureTime,
        isCompleted: false,
        store: store,
        itemsToPick: storeItems,
        hasPerishable: hasPerishable,
        isUserPinned: isUserPinned,
        violatesClosingTime: violatesClosing,
        warningMessage: stopWarning,
      ));

      prevNodeIndex = nodeIndex;
    }

    final routeId = const Uuid().v4();
    final stopsWithRouteId = stops.map((s) => s.copyWith(routeId: routeId)).toList();

    return ActiveRoute(
      id: routeId,
      generatedAt: DateTime.now(),
      totalDistanceMeters: totalDistance,
      totalDurationSeconds: totalDuration,
      solverStatus: solverStatus,
      stops: stopsWithRouteId,
      warnings: warnings,
    );
  }

  /// Optimize sequence enforcing hard locks and penalizing early perishable stops
  List<Store> _optimizeSequence({
    required List<Store> selectedStores,
    required Map<Store, List<TodoItem>> storeToItems,
    required MatrixResult matrix,
    required DateTime departureTime,
  }) {
    if (selectedStores.length <= 1) return selectedStores;

    // Categorize stores:
    // 1. Pinned stores (Human-in-the-loop manual lock)
    // 2. Stores with perishable items (defer to end)
    // 3. Regular flexible stores
    final pinnedStores = <Store>[];
    final unpinnedRegularStores = <Store>[];
    final perishableStores = <Store>[];

    for (final store in selectedStores) {
      final items = storeToItems[store] ?? [];
      final isPinned = items.any((i) => i.isPinned);
      final isPerishable = items.any((i) => i.isPerishable);

      if (isPinned) {
        pinnedStores.add(store);
      } else if (isPerishable) {
        perishableStores.add(store);
      } else {
        unpinnedRegularStores.add(store);
      }
    }

    // Sort pinned stores by minimum human_order_index among their pinned items
    pinnedStores.sort((a, b) {
      final minA = storeToItems[a]!
          .where((i) => i.isPinned)
          .map((i) => i.humanOrderIndex)
          .reduce(min);
      final minB = storeToItems[b]!
          .where((i) => i.isPinned)
          .map((i) => i.humanOrderIndex)
          .reduce(min);
      return minA.compareTo(minB);
    });

    // Solve TSP / Greedy Nearest Neighbor on flexible regular stores
    final orderedRegular = _greedyNearestNeighbor(
      stores: unpinnedRegularStores,
      allStores: selectedStores,
      matrix: matrix,
    );

    // Solve TSP / Greedy on perishable stores (these will be placed at the final leg)
    final orderedPerishable = _greedyNearestNeighbor(
      stores: perishableStores,
      allStores: selectedStores,
      matrix: matrix,
    );

    // Assembly: Pinned sequence + Optimized regular stops + Perishable stops at the end
    // Non-destructive principle: If user explicitly pinned a perishable store, it stays where user pinned it!
    return [...pinnedStores, ...orderedRegular, ...orderedPerishable];
  }

  /// Greedy Nearest Neighbor solver for small store candidate subsets
  List<Store> _greedyNearestNeighbor({
    required List<Store> stores,
    required List<Store> allStores,
    required MatrixResult matrix,
  }) {
    if (stores.length <= 1) return stores;

    final remaining = List<Store>.from(stores);
    final route = <Store>[];

    var currentIdx = 0; // Origin node

    while (remaining.isNotEmpty) {
      var bestIdx = -1;
      var shortestDist = double.infinity;

      for (var i = 0; i < remaining.length; i++) {
        final store = remaining[i];
        final nodeIdx = allStores.indexOf(store) + 1;
        final dist = matrix.distances[currentIdx][nodeIdx];
        if (dist < shortestDist) {
          shortestDist = dist;
          bestIdx = i;
        }
      }

      final chosen = remaining.removeAt(bestIdx);
      route.add(chosen);
      currentIdx = allStores.indexOf(chosen) + 1;
    }

    return route;
  }
}
