import 'dart:isolate';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../core/haversine.dart';
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
  // Model the trip home (the spec's terminal node n+1). Perishables keep
  // accruing thermal cost until they get there.
  final bool returnToOrigin;

  const VrpSolverRequest({
    required this.originCoordinates,
    required this.departureTime,
    required this.items,
    required this.candidateStores,
    this.preferences = const [],
    this.returnToOrigin = true,
  });
}

/// Solver status values stored on [ActiveRoute.solverStatus].
class SolverStatus {
  static const optimal = 'OPTIMAL'; // exact DP, all hard constraints met
  static const feasible =
      'FEASIBLE'; // heuristic (large list), all constraints met
  static const relaxed =
      'RELAXED_CONSTRAINTS'; // time windows had to be softened
  static const infeasible = 'INFEASIBLE';
}

/// Hybrid Vehicle Routing Problem with Time Windows (VRPTW) Solver.
///
/// Items are grouped into tasks; each task must be served by exactly one of
/// its candidate stores (the spec's disjunction constraint). Routes are
/// searched with a label-setting dynamic program over (tasks covered, last
/// store) states which jointly picks stores and their order, honouring:
///  * store opening hours (waiting for opening, finishing before closing),
///  * thermal decay: gamma x perishables on board x seconds until home,
///  * learned store preferences,
///  * pins: a pinned item is never served after anything listed below it.
/// If no route meets every closing time, time windows become soft penalties
/// (constraint relaxation cascade) and the violations are reported.
class VrpSolver {
  final DistanceMatrixService matrixService;
  final bool runInBackground;

  VrpSolver({required this.matrixService, this.runInBackground = true});

  Future<ActiveRoute> solveRoute(VrpSolverRequest request) async {
    final activeItems = request.items.where((i) => !i.isCompleted).toList()
      ..sort((a, b) => a.humanOrderIndex.compareTo(b.humanOrderIndex));
    if (activeItems.isEmpty) {
      return _emptyRoute(SolverStatus.optimal, 'No pending items to route.');
    }
    if (request.candidateStores.isEmpty) {
      return _emptyRoute(
        SolverStatus.infeasible,
        'No stores configured. Add stores to plan a route.',
      );
    }

    final problem = _buildProblem(request, activeItems);

    final nodes = <List<double>>[
      request.originCoordinates,
      for (final s in problem.stores) [s.latitude, s.longitude],
    ];
    final matrix = await matrixService.computeMatrix(nodes);

    final plan = runInBackground
        ? await _solveInBackground(problem, matrix)
        : _solvePlan(problem, matrix);

    return _assembleRoute(problem, matrix, plan);
  }

  ActiveRoute _emptyRoute(String status, String warning) {
    return ActiveRoute(
      id: const Uuid().v4(),
      generatedAt: DateTime.now(),
      totalDistanceMeters: 0,
      totalDurationSeconds: 0,
      solverStatus: status,
      stops: const [],
      warnings: [warning],
    );
  }

  _Problem _buildProblem(VrpSolverRequest request, List<TodoItem> items) {
    final warnings = <String>[];
    final prefs = {
      for (final p in request.preferences)
        '${p.itemCategory}|${p.storeId}': p.confidenceScore,
    };
    double conf(String category, String storeId) =>
        prefs['$category|$storeId'] ?? 0.5;

    // 1. Group items into tasks. Pinned items are their own task; unpinned
    // items are grouped by (category, perishable) within the stretch of the
    // list between two pins, so a group never straddles a pin.
    final taskItems = <List<TodoItem>>[];
    final taskPinned = <bool>[];
    final groupIndex = <String, int>{};
    var segment = 0;
    for (final item in items) {
      if (item.isPinned) {
        taskItems.add([item]);
        taskPinned.add(true);
        segment++;
        continue;
      }
      final key = '$segment|${item.category}|${item.isPerishable}';
      final existing = groupIndex[key];
      if (existing != null) {
        taskItems[existing].add(item);
      } else {
        groupIndex[key] = taskItems.length;
        taskItems.add([item]);
        taskPinned.add(false);
      }
    }

    // 2. Candidate stores per task (disjunctive choice).
    final allStores = request.candidateStores;
    final origin = request.originCoordinates;
    final taskCandidates = <List<Store>>[];
    final missingCategories = <String>{};
    for (final itemsOfTask in taskItems) {
      final category = itemsOfTask.first.category;
      var candidates = allStores
          .where(
            (s) =>
                s.supportedCategories.contains(category) ||
                s.supportedCategories.contains('generic'),
          )
          .toList();
      if (candidates.isEmpty) {
        missingCategories.add(category);
        candidates = List.of(allStores);
      }
      // Strongly learned favourites knock out stores the user never uses for this category.
      final best = candidates.map((s) => conf(category, s.id)).reduce(max);
      candidates = candidates
          .where(
            (s) =>
                conf(category, s.id) >=
                best - AppConstants.storePreferenceCutoffMargin,
          )
          .toList();
      // Keep the search tractable: the few best candidates by preference, then proximity.
      double distFromOrigin(Store s) => HaversineUtils.directDistance(
        origin[0],
        origin[1],
        s.latitude,
        s.longitude,
      );
      candidates.sort((a, b) {
        final byPref = conf(category, b.id).compareTo(conf(category, a.id));
        return byPref != 0
            ? byPref
            : distFromOrigin(a).compareTo(distFromOrigin(b));
      });
      taskCandidates.add(candidates.take(_maxCandidatesPerTask).toList());
    }
    for (final c in missingCategories) {
      warnings.add(
        'No store is set up for "$c" items, so any store may be suggested for them.',
      );
    }

    final stores = <Store>[];
    final storeIndex = <String, int>{};
    for (final candidates in taskCandidates) {
      for (final s in candidates) {
        storeIndex.putIfAbsent(s.id, () {
          stores.add(s);
          return stores.length - 1;
        });
      }
    }

    final tasks = <_Task>[];
    for (var t = 0; t < taskItems.length; t++) {
      final first = taskItems[t].first;
      // Pins that sit above this task must be served no later than it.
      var requiredBefore = 0;
      for (var p = 0; p < t; p++) {
        if (taskPinned[p] &&
            taskItems[p].first.humanOrderIndex < first.humanOrderIndex) {
          requiredBefore |= 1 << p;
        }
      }
      tasks.add(
        _Task(
          items: taskItems[t],
          category: first.category,
          perishableCount: taskItems[t].where((i) => i.isPerishable).length,
          isPinned: taskPinned[t],
          requiredBefore: requiredBefore,
          candidateStores: taskCandidates[t]
              .map((s) => storeIndex[s.id]!)
              .toList(),
        ),
      );
    }

    final preferenceCost = List.generate(stores.length, (s) {
      return [
        for (final task in tasks)
          AppConstants.storePreferenceWeightSeconds *
              (1.0 - conf(task.category, stores[s].id)),
      ];
    });

    return _Problem(
      tasks: tasks,
      stores: stores,
      departure: request.departureTime,
      returnToOrigin: request.returnToOrigin,
      preferenceCost: preferenceCost,
      warnings: warnings,
    );
  }

  ActiveRoute _assembleRoute(
    _Problem problem,
    MatrixResult matrix,
    _Plan plan,
  ) {
    final routeId = const Uuid().v4();
    final warnings = [...problem.warnings];
    final stops = <RouteStop>[];
    var totalDistance = 0.0;
    var prevNode = 0;

    if (plan.steps.isEmpty) {
      return _emptyRoute(
        SolverStatus.infeasible,
        'Could not build a route for the pending items.',
      );
    }

    String hhmm(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    for (var i = 0; i < plan.steps.length; i++) {
      final step = plan.steps[i];
      final store = problem.stores[step.store];
      totalDistance += matrix.distances[prevNode][step.store + 1];
      prevNode = step.store + 1;

      final stopItems = <TodoItem>[
        for (var t = 0; t < problem.tasks.length; t++)
          if (step.covered & (1 << t) != 0) ...problem.tasks[t].items,
      ]..sort((a, b) => a.humanOrderIndex.compareTo(b.humanOrderIndex));

      final arrival = problem.departure.add(_secs(step.arrival));
      final start = arrival.add(_secs(step.wait));
      final departure = start.add(Duration(seconds: store.avgCheckoutDelaySec));

      String? message;
      if (step.late) {
        final window = store.windowAtOrAfter(arrival);
        message = window == null
            ? '${store.name} is closed by the time you arrive (${hhmm(arrival)}). Hours: ${store.formattedHours}'
            : '${store.name} closes at ${hhmm(window.close)}; arriving ${hhmm(arrival)} leaves too little time. Hours: ${store.formattedHours}';
        warnings.add(message);
      } else if (step.wait >= 300) {
        message =
            'Arrive ${hhmm(arrival)}, opens ${hhmm(start)} (${(step.wait / 60).round()} min wait).';
      }

      stops.add(
        RouteStop(
          id: const Uuid().v4(),
          routeId: routeId,
          stopSequence: i + 1,
          storeId: store.id,
          estimatedArrival: arrival,
          estimatedDeparture: departure,
          store: store,
          itemsToPick: stopItems,
          hasPerishable: stopItems.any((it) => it.isPerishable),
          isUserPinned: stopItems.any((it) => it.isPinned),
          violatesClosingTime: step.late,
          waitSeconds: step.wait.round(),
          warningMessage: message,
        ),
      );
    }

    var totalDuration = plan.steps.last.departureTime;
    if (problem.returnToOrigin) {
      totalDistance += matrix.distances[prevNode][0];
      totalDuration += matrix.durations[prevNode][0];
    }
    if (plan.relaxed && problem.tasks.any((t) => t.isPinned)) {
      warnings.add(
        'Your pinned order was kept even though it misses some opening hours.',
      );
    }

    return ActiveRoute(
      id: routeId,
      generatedAt: DateTime.now(),
      totalDistanceMeters: totalDistance,
      totalDurationSeconds: totalDuration,
      solverStatus: plan.relaxed
          ? SolverStatus.relaxed
          : (plan.exact ? SolverStatus.optimal : SolverStatus.feasible),
      stops: stops,
      warnings: warnings,
    );
  }
}

const int _maxCandidatesPerTask = 4;
const int _maxLabelsPerState = 4;

Duration _secs(double seconds) =>
    Duration(milliseconds: (seconds * 1000).round());

class _Task {
  final List<TodoItem> items;
  final String category;
  final int perishableCount;
  final bool isPinned;
  final int requiredBefore; // bitmask of pinned tasks that must be served first
  final List<int> candidateStores;

  const _Task({
    required this.items,
    required this.category,
    required this.perishableCount,
    required this.isPinned,
    required this.requiredBefore,
    required this.candidateStores,
  });
}

/// Plain-data problem description; safe to send to a background isolate.
class _Problem {
  final List<_Task> tasks;
  final List<Store> stores; // node index = store index + 1 (0 is origin)
  final DateTime departure;
  final bool returnToOrigin;
  final List<List<double>> preferenceCost; // [store][task]
  final List<String> warnings;

  const _Problem({
    required this.tasks,
    required this.stores,
    required this.departure,
    required this.returnToOrigin,
    required this.preferenceCost,
    required this.warnings,
  });
}

/// One stop of a (partial) route, linked back to its predecessor.
class _Label {
  final _Label? parent;
  final int store; // -1 for the origin
  final int covered; // tasks served at this stop
  final double arrival; // seconds after departure
  final double wait;
  final double departureTime; // seconds after departure, leaving this stop
  final double cost;
  final bool late;

  const _Label({
    required this.parent,
    required this.store,
    required this.covered,
    required this.arrival,
    required this.wait,
    required this.departureTime,
    required this.cost,
    required this.late,
  });
}

class _Plan {
  final List<_Label> steps;
  final bool relaxed;
  final bool exact;
  const _Plan(this.steps, {required this.relaxed, required this.exact});
}

Future<_Plan> _solveInBackground(_Problem problem, MatrixResult matrix) {
  return Isolate.run(() => _solvePlan(problem, matrix));
}

_Plan _solvePlan(_Problem problem, MatrixResult matrix) {
  final search = _Search(problem, matrix);
  if (problem.tasks.length <= AppConstants.exactSolverMaxTasks) {
    final hard = search.exact(relaxed: false);
    if (hard != null) return _Plan(hard, relaxed: false, exact: true);
    return _Plan(
      search.exact(relaxed: true) ?? const [],
      relaxed: true,
      exact: true,
    );
  }
  final hard = search.greedy(relaxed: false);
  if (hard != null) return _Plan(hard, relaxed: false, exact: false);
  return _Plan(
    search.greedy(relaxed: true) ?? const [],
    relaxed: true,
    exact: false,
  );
}

class _Search {
  final _Problem p;
  final MatrixResult m;
  late final int fullMask = (1 << p.tasks.length) - 1;
  late final int perishableMask = _maskWhere((t) => t.perishableCount > 0);
  late final List<int> servable = List.generate(p.stores.length, (s) {
    var mask = 0;
    for (var t = 0; t < p.tasks.length; t++) {
      if (p.tasks[t].candidateStores.contains(s)) mask |= 1 << t;
    }
    return mask;
  });

  _Search(this.p, this.m);

  int _maskWhere(bool Function(_Task) test) {
    var mask = 0;
    for (var t = 0; t < p.tasks.length; t++) {
      if (test(p.tasks[t])) mask |= 1 << t;
    }
    return mask;
  }

  int _perishablesOnBoard(int mask) {
    var count = 0;
    for (var t = 0; t < p.tasks.length; t++) {
      if (mask & (1 << t) != 0) count += p.tasks[t].perishableCount;
    }
    return count;
  }

  /// Drop tasks whose required pins are neither already served nor served
  /// at this same stop, until stable.
  int _respectPins(int candidates, int mask) {
    var t = candidates;
    while (true) {
      var next = t;
      for (var i = 0; i < p.tasks.length; i++) {
        if (next & (1 << i) != 0 &&
            p.tasks[i].requiredBefore & ~(mask | next) != 0) {
          next &= ~(1 << i);
        }
      }
      if (next == t) return t;
      t = next;
    }
  }

  /// Ways to shop at store [s]: buy everything it can supply, or everything
  /// except perishables (so they can be bought on a later, final-leg stop).
  List<int> _options(int s, int mask) {
    final open = servable[s] & ~mask;
    if (open == 0) return const [];
    final all = _respectPins(open, mask);
    final dry = _respectPins(open & ~perishableMask, mask);
    return [if (all != 0) all, if (dry != 0 && dry != all) dry];
  }

  _Label? _extend(_Label from, int mask, int s, int covered, bool relaxed) {
    final store = p.stores[s];
    final travel = m.durations[from.store + 1][s + 1];
    final arrival = from.departureTime + travel;
    final arrivalAbs = p.departure.add(_secs(arrival));
    final service = store.avgCheckoutDelaySec.toDouble();

    var wait = 0.0;
    var late = false;
    var overrun = 0.0;
    final window = store.windowAtOrAfter(arrivalAbs);
    if (window == null) {
      late = true;
      overrun = 3600;
    } else {
      final start = arrivalAbs.isBefore(window.open) ? window.open : arrivalAbs;
      wait = start.difference(arrivalAbs).inMilliseconds / 1000.0;
      overrun =
          start.difference(window.close).inMilliseconds / 1000.0 + service;
      late = overrun > 0;
    }
    if (late) {
      if (!relaxed) return null;
      wait = 0;
    }

    final elapsed = travel + wait + service;
    var cost =
        from.cost +
        elapsed +
        AppConstants.earlyArrivalWaitPenaltyBeta * wait +
        AppConstants.thermalDecayPenaltyGamma *
            _perishablesOnBoard(mask) *
            elapsed;
    for (var t = 0; t < p.tasks.length; t++) {
      if (covered & (1 << t) != 0) cost += p.preferenceCost[s][t];
    }
    if (late) {
      cost += AppConstants.lateArrivalPenaltyPerSecond * max(overrun, 60.0);
    }

    return _Label(
      parent: from,
      store: s,
      covered: covered,
      arrival: arrival,
      wait: wait,
      departureTime: arrival + wait + service,
      cost: cost,
      late: late,
    );
  }

  double _finalCost(_Label label) {
    if (!p.returnToOrigin) return label.cost;
    final travel = m.durations[label.store + 1][0];
    return label.cost +
        travel +
        AppConstants.thermalDecayPenaltyGamma *
            _perishablesOnBoard(fullMask) *
            travel;
  }

  _Label get _start => const _Label(
    parent: null,
    store: -1,
    covered: 0,
    arrival: 0,
    wait: 0,
    departureTime: 0,
    cost: 0,
    late: false,
  );

  /// Label-setting DP over (covered-task mask, last store) with Pareto
  /// pruning on (time, cost). Masks only grow, so ascending order is a
  /// valid topological order of the state graph.
  List<_Label>? exact({required bool relaxed}) {
    final labels = List<Map<int, List<_Label>>?>.filled(fullMask + 1, null);
    labels[0] = {
      -1: [_start],
    };

    for (var mask = 0; mask < fullMask; mask++) {
      final byStore = labels[mask];
      if (byStore == null) continue;
      for (final bucket in byStore.values) {
        for (final label in bucket) {
          for (var s = 0; s < p.stores.length; s++) {
            if (s == label.store) continue;
            for (final covered in _options(s, mask)) {
              final next = _extend(label, mask, s, covered, relaxed);
              if (next == null) continue;
              final target = labels[mask | covered] ??= {};
              _insertPareto(target.putIfAbsent(s, () => []), next);
            }
          }
        }
      }
    }

    final finals = labels[fullMask];
    if (finals == null) return null;
    _Label? best;
    var bestCost = double.infinity;
    for (final bucket in finals.values) {
      for (final label in bucket) {
        final c = _finalCost(label);
        if (c < bestCost) {
          bestCost = c;
          best = label;
        }
      }
    }
    return best == null ? null : _unwind(best);
  }

  void _insertPareto(List<_Label> bucket, _Label next) {
    const eps = 1e-6;
    for (final l in bucket) {
      if (l.departureTime <= next.departureTime + eps &&
          l.cost <= next.cost + eps) {
        return;
      }
    }
    bucket.removeWhere(
      (l) => next.departureTime <= l.departureTime && next.cost <= l.cost,
    );
    bucket.add(next);
    if (bucket.length > _maxLabelsPerState) {
      bucket.sort((a, b) => a.cost.compareTo(b.cost));
      bucket.removeLast();
    }
  }

  /// Large lists: repeatedly take the stop with the lowest cost per task
  /// served. Always makes progress: the highest uncovered task in the list
  /// has every pin above it already served.
  List<_Label>? greedy({required bool relaxed}) {
    var label = _start;
    var mask = 0;
    while (mask != fullMask) {
      _Label? bestNext;
      var bestScore = double.infinity;
      for (var s = 0; s < p.stores.length; s++) {
        if (s == label.store) continue;
        for (final covered in _options(s, mask)) {
          final next = _extend(label, mask, s, covered, relaxed);
          if (next == null) continue;
          final tasksServed = _bitCount(covered);
          final score = (next.cost - label.cost) / tasksServed;
          if (score < bestScore) {
            bestScore = score;
            bestNext = next;
          }
        }
      }
      if (bestNext == null) return null;
      label = bestNext;
      mask |= bestNext.covered;
    }
    return _unwind(label);
  }

  List<_Label> _unwind(_Label last) {
    final steps = <_Label>[];
    for (_Label? l = last; l != null && l.store >= 0; l = l.parent) {
      steps.add(l);
    }
    return steps.reversed.toList();
  }

  static int _bitCount(int v) {
    var c = 0;
    for (var x = v; x != 0; x &= x - 1) {
      c++;
    }
    return c;
  }
}
