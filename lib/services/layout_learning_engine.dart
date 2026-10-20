import 'dart:math';
import 'package:uuid/uuid.dart';
import '../core/constants.dart';
import '../data/database/app_database.dart';
import '../data/models/store_layout_edge.dart';
import '../data/models/visit.dart';

/// In-Store Walk-Order Precedence Learning Engine
///
/// The database keeps raw precedence *evidence* per store (both directions of
/// a pair may exist). The DAG is derived when reading: opposite directions
/// cancel out, remaining cycles are broken with a greedy Feedback Arc Set,
/// and Kahn's algorithm produces the walk order.
class LayoutLearningEngine {
  final AppDatabase database;

  LayoutLearningEngine({required this.database});

  /// Log a check-off event when an item is ticked inside a store
  Future<void> recordCheckoff({
    required String visitId,
    required String itemId,
    required String itemCategory,
    DateTime? at,
  }) async {
    final checkoff = VisitCheckoff(
      id: const Uuid().v4(),
      visitId: visitId,
      itemId: itemId,
      itemCategory: itemCategory,
      checkoffTimestamp: at ?? DateTime.now(),
    );
    await database.insertCheckoff(checkoff);
  }

  /// Un-ticking an item in the store means it wasn't picked at that point.
  Future<void> retractCheckoff({required String visitId, required String itemId}) {
    return database.deleteCheckoff(visitId, itemId);
  }

  /// Fold this visit's check-off sequence into the store's precedence evidence.
  Future<void> processCompletedVisit({
    required String storeId,
    required String visitId,
  }) async {
    final checkoffs = await database.getCheckoffsForVisit(visitId);

    // Collapse to one timestamp per category (first pick), so five dairy
    // items don't count as five observations of every dairy pair.
    final firstPick = <String, DateTime>{};
    for (final c in checkoffs) {
      final prev = firstPick[c.itemCategory];
      if (prev == null || c.checkoffTimestamp.isBefore(prev)) {
        firstPick[c.itemCategory] = c.checkoffTimestamp;
      }
    }
    if (firstPick.length < 2) return;
    final sequence = firstPick.entries.toList()..sort((a, b) => a.value.compareTo(b.value));

    final existingEdges = await database.getLayoutEdges(storeId);
    final edgeMap = <String, StoreLayoutEdge>{
      for (final e in existingEdges) '${e.fromItemCategory}->${e.toItemCategory}': e
    };

    // Pairwise time-decay weights: w = exp(-(t_B - t_A) / sigma)
    for (var i = 0; i < sequence.length; i++) {
      for (var j = i + 1; j < sequence.length; j++) {
        final a = sequence[i];
        final b = sequence[j];
        final deltaSec = b.value.difference(a.value).inMilliseconds / 1000.0;
        if (deltaSec <= 0 || deltaSec > AppConstants.walkOrderMaxDeltaSeconds) continue;

        final weight = exp(-deltaSec / AppConstants.walkOrderDecaySigma);
        final key = '${a.key}->${b.key}';
        final curr = edgeMap[key];
        edgeMap[key] = curr == null
            ? StoreLayoutEdge(
                storeId: storeId,
                fromItemCategory: a.key,
                toItemCategory: b.key,
                forwardWeight: weight,
                sampleSize: 1,
              )
            : curr.copyWith(
                forwardWeight: (curr.forwardWeight * curr.sampleSize + weight) / (curr.sampleSize + 1),
                sampleSize: curr.sampleSize + 1,
              );
      }
    }

    for (final edge in edgeMap.values) {
      await database.insertLayoutEdge(edge);
    }
  }

  /// Net, acyclic precedence graph for a store: for each pair only the
  /// direction with more evidence survives (weighted by the difference), weak
  /// edges are dropped, then remaining longer cycles are broken.
  List<StoreLayoutEdge> deriveDag(List<StoreLayoutEdge> evidenceEdges) {
    final byKey = {
      for (final e in evidenceEdges) '${e.fromItemCategory}->${e.toItemCategory}': e,
    };
    final net = <StoreLayoutEdge>[];
    for (final e in evidenceEdges) {
      final reverse = byKey['${e.toItemCategory}->${e.fromItemCategory}'];
      final margin = e.evidence - (reverse?.evidence ?? 0.0);
      if (margin <= AppConstants.walkOrderConfidenceThreshold) continue;
      net.add(StoreLayoutEdge(
        storeId: e.storeId,
        fromItemCategory: e.fromItemCategory,
        toItemCategory: e.toItemCategory,
        forwardWeight: margin,
        sampleSize: 1,
      ));
    }
    return breakCyclesWithFeedbackArcSet(net);
  }

  /// Eliminate directed cycles by greedily removing the edge with the least
  /// accumulated evidence on each cycle found.
  List<StoreLayoutEdge> breakCyclesWithFeedbackArcSet(List<StoreLayoutEdge> edges) {
    final retained = List<StoreLayoutEdge>.from(edges);

    while (true) {
      final cycle = _findCycle(retained);
      if (cycle == null || cycle.isEmpty) break;

      StoreLayoutEdge? weakest;
      for (var i = 0; i < cycle.length - 1; i++) {
        final u = cycle[i];
        final v = cycle[i + 1];
        final match = retained.firstWhere(
          (e) => e.fromItemCategory == u && e.toItemCategory == v,
        );
        if (weakest == null || match.evidence < weakest.evidence) {
          weakest = match;
        }
      }

      if (weakest == null) break;
      retained.remove(weakest);
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

  /// Learned DAG for display.
  Future<List<StoreLayoutEdge>> getLearnedDag(String storeId) async {
    return deriveDag(await database.getLayoutEdges(storeId));
  }

  /// Derive the optimal topological walk sequence for a store using Kahn's
  /// Algorithm. [categoriesToPick] should be in the user's list order: it is
  /// the tie-breaker wherever the store hasn't been learned yet.
  Future<List<String>> getOptimalWalkOrder({
    required String storeId,
    required List<String> categoriesToPick,
  }) async {
    if (categoriesToPick.length <= 1) return categoriesToPick;

    final wanted = categoriesToPick.toSet();
    final edges = (await database.getLayoutEdges(storeId))
        .where((e) => wanted.contains(e.fromItemCategory) && wanted.contains(e.toItemCategory))
        .toList();

    return kahnsTopologicalSort(categoriesToPick, deriveDag(edges));
  }

  /// Kahn's Algorithm; among ready nodes the earliest in [nodes] goes first.
  List<String> kahnsTopologicalSort(
    List<String> nodes,
    List<StoreLayoutEdge> edges,
  ) {
    final priority = <String, int>{};
    for (var i = 0; i < nodes.length; i++) {
      priority.putIfAbsent(nodes[i], () => i);
    }
    final inDegree = <String, int>{for (final n in priority.keys) n: 0};
    final adj = <String, List<String>>{for (final n in priority.keys) n: []};

    for (final e in edges) {
      if (inDegree.containsKey(e.toItemCategory) && inDegree.containsKey(e.fromItemCategory)) {
        adj[e.fromItemCategory]!.add(e.toItemCategory);
        inDegree[e.toItemCategory] = inDegree[e.toItemCategory]! + 1;
      }
    }

    int byPriority(String a, String b) => priority[a]!.compareTo(priority[b]!);
    final ready = priority.keys.where((n) => inDegree[n] == 0).toList()..sort(byPriority);
    final sorted = <String>[];

    while (ready.isNotEmpty) {
      final u = ready.removeAt(0);
      sorted.add(u);

      for (final v in adj[u]!) {
        inDegree[v] = inDegree[v]! - 1;
        if (inDegree[v] == 0) {
          ready
            ..add(v)
            ..sort(byPriority);
        }
      }
    }

    // Only reachable if the caller passed a cyclic graph; keep list order.
    for (final n in priority.keys) {
      if (!sorted.contains(n)) sorted.add(n);
    }

    return sorted;
  }
}
