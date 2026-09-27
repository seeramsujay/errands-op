import 'dart:math';
import '../core/constants.dart';
import '../data/database/app_database.dart';
import '../data/models/store_layout_edge.dart';
import '../data/models/visit.dart';

/// In-Store Walk-Order Precedence Learning Engine
class LayoutLearningEngine {
  final AppDatabase database;

  LayoutLearningEngine({required this.database});

  /// Log a check-off event when an item is ticked inside a store
  Future<void> recordCheckoff({
    required String visitId,
    required String itemId,
    required String itemCategory,
  }) async {
    final checkoff = VisitCheckoff(
      id: 'chk_${DateTime.now().millisecondsSinceEpoch}_$itemId',
      visitId: visitId,
      itemId: itemId,
      itemCategory: itemCategory,
      checkoffTimestamp: DateTime.now(),
    );
    await database.insertCheckoff(checkoff);
  }

  /// Rebuild precedence matrix, break cycles via Feedback Arc Set,
  /// and update DAG edges upon visit completion.
  Future<void> processCompletedVisit({
    required String storeId,
    required String visitId,
  }) async {
    final checkoffs = await database.getCheckoffsForVisit(visitId);
    if (checkoffs.length < 2) return;

    // Load existing layout edges for this store
    final existingEdges = await database.getLayoutEdges(storeId);
    final edgeMap = <String, StoreLayoutEdge>{
      for (final e in existingEdges) '${e.fromItemCategory}->${e.toItemCategory}': e
    };

    // Calculate pairwise time-decay weights: w = exp(-(t_B - t_A) / sigma)
    for (var i = 0; i < checkoffs.length; i++) {
      for (var j = i + 1; j < checkoffs.length; j++) {
        final a = checkoffs[i];
        final b = checkoffs[j];

        if (a.itemCategory == b.itemCategory) continue;

        final deltaSec = b.checkoffTimestamp.difference(a.checkoffTimestamp).inSeconds.toDouble();
        if (deltaSec <= 0 || deltaSec > AppConstants.walkOrderMaxDeltaSeconds) {
          continue;
        }

        final weight = exp(-deltaSec / AppConstants.walkOrderDecaySigma);
        final key = '${a.itemCategory}->${b.itemCategory}';

        if (edgeMap.containsKey(key)) {
          final curr = edgeMap[key]!;
          final updatedWeight = (curr.forwardWeight * curr.sampleSize + weight) / (curr.sampleSize + 1);
          edgeMap[key] = curr.copyWith(
            forwardWeight: updatedWeight,
            sampleSize: curr.sampleSize + 1,
          );
        } else {
          edgeMap[key] = StoreLayoutEdge(
            storeId: storeId,
            fromItemCategory: a.itemCategory,
            toItemCategory: b.itemCategory,
            forwardWeight: weight,
            sampleSize: 1,
          );
        }
      }
    }

    // Break cycles using Feedback Arc Set (FAS) to ensure DAG property
    final dagEdges = breakCyclesWithFeedbackArcSet(edgeMap.values.toList());

    // Save pruned DAG edges to database
    for (final edge in dagEdges) {
      await database.insertLayoutEdge(edge);
    }
  }

  /// Eliminate directed cycles by greedily removing lowest-weight back-edges
  List<StoreLayoutEdge> breakCyclesWithFeedbackArcSet(List<StoreLayoutEdge> edges) {
    final retained = List<StoreLayoutEdge>.from(edges);

    while (true) {
      final cycle = _findCycle(retained);
      if (cycle == null || cycle.isEmpty) break;

      // Find the edge in the cycle with the minimal forward weight
      StoreLayoutEdge? weakest;
      for (var i = 0; i < cycle.length - 1; i++) {
        final u = cycle[i];
        final v = cycle[i + 1];
        final match = retained.firstWhere(
          (e) => e.fromItemCategory == u && e.toItemCategory == v,
        );
        if (weakest == null || match.forwardWeight < weakest.forwardWeight) {
          weakest = match;
        }
      }

      if (weakest != null) {
        retained.remove(weakest);
      } else {
        break;
      }
    }

    return retained;
  }

  /// Find a directed cycle using Depth-First Search (DFS)
  List<String>? _findCycle(List<StoreLayoutEdge> edges) {
    final adj = <String, List<String>>{};
    for (final e in edges) {
      adj.putIfAbsent(e.fromItemCategory, () => []).add(e.toItemCategory);
    }

    final visited = <String, int>{}; // 0 = unvisited, 1 = visiting, 2 = visited
    final path = <String>[];

    for (final node in adj.keys) {
      if ((visited[node] ?? 0) == 0) {
        final cycle = _dfsCycle(node, adj, visited, path);
        if (cycle != null) return cycle;
      }
    }

    return null;
  }

  List<String>? _dfsCycle(
    String current,
    Map<String, List<String>> adj,
    Map<String, int> visited,
    List<String> path,
  ) {
    visited[current] = 1;
    path.add(current);

    for (final neighbor in adj[current] ?? <String>[]) {
      if ((visited[neighbor] ?? 0) == 1) {
        // Cycle detected
        final startIndex = path.indexOf(neighbor);
        return [...path.sublist(startIndex), neighbor];
      } else if ((visited[neighbor] ?? 0) == 0) {
        final cycle = _dfsCycle(neighbor, adj, visited, path);
        if (cycle != null) return cycle;
      }
    }

    path.removeLast();
    visited[current] = 2;
    return null;
  }

  /// Derive the optimal topological walk sequence for a store using Kahn's Algorithm
  Future<List<String>> getOptimalWalkOrder({
    required String storeId,
    required List<String> categoriesToPick,
  }) async {
    if (categoriesToPick.length <= 1) return categoriesToPick;

    final edges = await database.getLayoutEdges(storeId);
    final relevantEdges = edges.where((e) {
      return categoriesToPick.contains(e.fromItemCategory) &&
          categoriesToPick.contains(e.toItemCategory);
    }).toList();

    return kahnsTopologicalSort(categoriesToPick, relevantEdges);
  }

  /// Kahn's Algorithm for deterministic layout sequencing
  List<String> kahnsTopologicalSort(
    List<String> nodes,
    List<StoreLayoutEdge> edges,
  ) {
    final inDegree = <String, int>{for (final n in nodes) n: 0};
    final adj = <String, List<String>>{for (final n in nodes) n: []};

    for (final e in edges) {
      if (inDegree.containsKey(e.toItemCategory) && inDegree.containsKey(e.fromItemCategory)) {
        adj[e.fromItemCategory]!.add(e.toItemCategory);
        inDegree[e.toItemCategory] = inDegree[e.toItemCategory]! + 1;
      }
    }

    // Queue nodes with in-degree 0
    final queue = nodes.where((n) => inDegree[n] == 0).toList();
    queue.sort(); // Lexicographical / deterministic tie-breaker

    final sorted = <String>[];

    while (queue.isNotEmpty) {
      final u = queue.removeAt(0);
      sorted.add(u);

      for (final v in adj[u] ?? <String>[]) {
        inDegree[v] = inDegree[v]! - 1;
        if (inDegree[v] == 0) {
          queue.add(v);
          queue.sort();
        }
      }
    }

    // Append any disconnected or remaining nodes
    for (final n in nodes) {
      if (!sorted.contains(n)) {
        sorted.add(n);
      }
    }

    return sorted;
  }
}
