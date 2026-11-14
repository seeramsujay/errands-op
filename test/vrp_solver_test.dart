import 'package:flutter_test/flutter_test.dart';
import 'package:op_list/data/database/app_database.dart';
import 'package:op_list/data/models/preference.dart';
import 'package:op_list/data/models/store.dart';
import 'package:op_list/data/models/todo_item.dart';
import 'package:op_list/services/distance_matrix_service.dart';
import 'package:op_list/services/vrp_solver.dart';

// ~111 m per 0.001 degree of latitude.
const _home = [12.9716, 77.5946];

TodoItem _item(
  String id,
  String category, {
  int order = 0,
  bool perishable = false,
  bool pinned = false,
  bool done = false,
}) {
  final t = DateTime(2026, 1, 1);
  return TodoItem(
    id: id,
    haEntityId: 'todo.list',
    summary: 'Item $id',
    category: category,
    isPerishable: perishable,
    isPinned: pinned,
    status: done ? 'completed' : 'needs_action',
    humanOrderIndex: order,
    createdAt: t,
    updatedAt: t,
  );
}

Store _store(
  String id,
  double dLat,
  double dLon,
  List<String> categories, {
  int? open = 0,
  int? close = 0,
  int service = 600,
}) {
  return Store(
    id: id,
    name: id,
    latitude: _home[0] + dLat,
    longitude: _home[1] + dLon,
    openingTimeSec: open,
    closingTimeSec: close, // open == close means 24h
    avgCheckoutDelaySec: service,
    supportedCategories: categories,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late VrpSolver solver;

  setUp(() async {
    db = AppDatabase.instance;
    await db.init(inMemory: true);
    solver = VrpSolver(matrixService: DistanceMatrixService(database: db));
  });

  tearDown(() async {
    await db.close();
  });

  Future<dynamic> solve(
    List<TodoItem> items,
    List<Store> stores, {
    DateTime? at,
    List<ItemStorePreference> prefs = const [],
  }) {
    return solver.solveRoute(
      VrpSolverRequest(
        originCoordinates: _home,
        departureTime: at ?? DateTime(2026, 9, 27, 11, 0),
        items: items,
        candidateStores: stores,
        preferences: prefs,
      ),
    );
  }

  List<String> order(dynamic route) => [
    for (final s in route.stops) s.storeId as String,
  ];

  test(
    'VrpSolver solves multi-stop route with perishable deferred to end',
    () async {
      final now = DateTime.now();
      final stores = [
        const Store(
          id: 'store_hardware',
          name: 'Hardware Store',
          latitude: 12.9750,
          longitude: 77.5950,
          supportedCategories: ['hardware'],
        ),
        const Store(
          id: 'store_dairy',
          name: 'Dairy & Ice Cream',
          latitude: 12.9800,
          longitude: 77.6000,
          supportedCategories: ['frozen'],
        ),
      ];

      final items = [
        TodoItem(
          id: '1',
          haEntityId: 'todo.list',
          summary: 'Ice Cream Tub',
          category: 'frozen',
          isPerishable: true,
          humanOrderIndex: 0,
          createdAt: now,
          updatedAt: now,
        ),
        TodoItem(
          id: '2',
          haEntityId: 'todo.list',
          summary: 'Wrench',
          category: 'hardware',
          humanOrderIndex: 1,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final route = await solve(items, stores);

      expect(route.stops.length, 2);
      expect(route.stops.first.storeId, 'store_hardware');
      expect(route.stops.last.storeId, 'store_dairy');
      expect(route.stops.last.hasPerishable, isTrue);
    },
  );

  test('VrpSolver respects user manual pin as hard sequence lock', () async {
    final stores = [
      _store('store_pharmacy', 0.0134, 0.0154, ['pharmacy']),
      _store('store_groceries', 0.0004, 0.0004, ['groceries']),
    ];
    final items = [
      _item('1', 'pharmacy', order: 0, pinned: true),
      _item('2', 'groceries', order: 1),
    ];

    final route = await solve(items, stores);

    expect(route.stops.first.storeId, 'store_pharmacy');
    expect(route.stops.first.isUserPinned, isTrue);
  });

  test(
    'VrpSolver flags closing time violation in constraint relaxation cascade',
    () async {
      // Departure at 20:00, store closes at 20:15, but the drive alone takes ~35 min.
      final stores = [
        _store(
          'store_early_close',
          0.1284,
          0.1054,
          ['hardware'],
          open: 8 * 3600,
          close: 20 * 3600 + 900,
        ),
      ];

      final route = await solve(
        [_item('1', 'hardware')],
        stores,
        at: DateTime(2026, 9, 27, 20, 0),
      );

      expect(route.solverStatus, SolverStatus.relaxed);
      expect(route.stops.first.violatesClosingTime, isTrue);
      expect(route.warnings, isNotEmpty);
    },
  );

  test(
    'perishables are deferred even when their store is closest (3 stops)',
    () async {
      // Nearest-neighbour from home would grab the ice cream first.
      final stores = [
        _store('frozen', 0.002, 0, ['frozen']),
        _store('hardware', 0.02, 0, ['hardware']),
        _store('pharmacy', 0.01, 0.01, ['pharmacy']),
      ];
      final route = await solve([
        _item('ice', 'frozen', order: 0, perishable: true),
        _item('nails', 'hardware', order: 1),
        _item('meds', 'pharmacy', order: 2),
      ], stores);

      expect(route.solverStatus, SolverStatus.optimal);
      expect(order(route).last, 'frozen');
    },
  );

  test('chooses the nearer of two equally preferred stores', () async {
    final stores = [
      _store('far_mart', 0.05, 0.05, ['groceries']),
      _store('near_mart', 0.005, 0.005, ['groceries']),
    ];
    final route = await solve([_item('rice', 'groceries')], stores);
    expect(order(route), ['near_mart']);
  });

  test('a strong learned preference beats a slightly closer store', () async {
    final stores = [
      _store('usual', 0.012, 0, ['groceries']),
      _store('other', 0.010, 0, ['groceries']),
    ];
    final route = await solve(
      [_item('rice', 'groceries')],
      stores,
      prefs: const [
        ItemStorePreference(
          id: 'p',
          itemCategory: 'groceries',
          storeId: 'usual',
          confidenceScore: 0.95,
        ),
      ],
    );
    expect(order(route), ['usual']);
  });

  test(
    'buys several categories in one stop when one store has them all',
    () async {
      final stores = [
        _store('hyper', 0.01, 0, ['groceries', 'dairy', 'snacks']),
        _store('dairy_only', 0.012, 0.002, ['dairy']),
        _store('snack_bar', 0.008, -0.002, ['snacks']),
      ];
      final route = await solve([
        _item('a', 'groceries', order: 0),
        _item('b', 'dairy', order: 1),
        _item('c', 'snacks', order: 2),
      ], stores);
      expect(order(route), ['hyper']);
      expect(route.stops.single.itemsToPick.length, 3);
    },
  );

  test('waits for a store to open instead of reporting a violation', () async {
    final stores = [
      _store(
        'office',
        0.01,
        0,
        ['admin_errand'],
        open: 10 * 3600,
        close: 17 * 3600,
      ),
    ];
    final route = await solve(
      [_item('passport', 'admin_errand')],
      stores,
      at: DateTime(2026, 9, 28, 9, 0),
    );

    expect(route.solverStatus, SolverStatus.optimal);
    final stop = route.stops.single;
    expect(stop.violatesClosingTime, isFalse);
    expect(stop.waitSeconds, greaterThan(50 * 60));
    expect(stop.estimatedDeparture, DateTime(2026, 9, 28, 10, 10));
  });

  test(
    'visits the early-closing office before a store that stays open late',
    () async {
      // Office is further away and its 17:00 close only fits if it goes first.
      final stores = [
        _store(
          'office',
          0.03,
          0,
          ['admin_errand'],
          open: 10 * 3600,
          close: 17 * 3600,
          service: 1800,
        ),
        _store(
          'mart',
          0.004,
          0,
          ['groceries'],
          open: 9 * 3600,
          close: 22 * 3600,
          service: 1800,
        ),
      ];
      final route = await solve(
        [
          _item('groceries', 'groceries', order: 0),
          _item('passport', 'admin_errand', order: 1),
        ],
        stores,
        at: DateTime(2026, 9, 28, 16, 0),
      );

      expect(route.solverStatus, SolverStatus.optimal);
      expect(order(route), ['office', 'mart']);
    },
  );

  test('pinned order is kept even when it misses opening hours', () async {
    final stores = [
      _store(
        'office',
        0.03,
        0,
        ['admin_errand'],
        open: 10 * 3600,
        close: 17 * 3600,
        service: 1800,
      ),
      _store(
        'mart',
        0.004,
        0,
        ['groceries'],
        open: 9 * 3600,
        close: 22 * 3600,
        service: 1800,
      ),
    ];
    final route = await solve(
      [
        _item('groceries', 'groceries', order: 0, pinned: true),
        _item('passport', 'admin_errand', order: 1, pinned: true),
      ],
      stores,
      at: DateTime(2026, 9, 28, 16, 15),
    );

    expect(order(route), ['mart', 'office']);
    expect(route.solverStatus, SolverStatus.relaxed);
    expect(route.stops.last.violatesClosingTime, isTrue);
    expect(
      route.warnings.any((String w) => w.contains('pinned order')),
      isTrue,
    );
  });

  test('a pin only constrains items listed below it', () async {
    // The pinned item is last in the list, so nothing has to come after it.
    final stores = [
      _store('far_pin', 0.03, 0, ['hardware']),
      _store('near', 0.003, 0, ['groceries']),
    ];
    final route = await solve([
      _item('milk', 'groceries', order: 0),
      _item('drill', 'hardware', order: 1, pinned: true),
    ], stores);
    expect(order(route).toSet(), {'near', 'far_pin'});
    expect(route.solverStatus, SolverStatus.optimal);
  });

  test('stores open past midnight are open at 01:00', () {
    final store = _store(
      'late',
      0,
      0,
      const ['generic'],
      open: 18 * 3600,
      close: 2 * 3600,
    );
    expect(store.isOpenAt(DateTime(2026, 9, 28, 1, 0)), isTrue);
    expect(store.isOpenAt(DateTime(2026, 9, 28, 3, 0)), isFalse);
    expect(store.isOpenAt(DateTime(2026, 9, 28, 19, 0)), isTrue);
    final w = store.windowAtOrAfter(DateTime(2026, 9, 28, 12, 0))!;
    expect(w.open, DateTime(2026, 9, 28, 18));
    expect(w.close, DateTime(2026, 9, 29, 2));
  });

  test('ignores completed items and reports missing stores', () async {
    final none = await solve([_item('x', 'groceries')], const []);
    expect(none.solverStatus, SolverStatus.infeasible);

    final route = await solve(
      [_item('done', 'hardware', done: true), _item('todo', 'groceries')],
      [
        _store('hw', 0.01, 0, ['hardware']),
        _store('mart', 0.01, 0.01, ['groceries']),
      ],
    );
    expect(order(route), ['mart']);
  });

  test('uncovered categories fall back to any store with a warning', () async {
    final route = await solve(
      [_item('x', 'cables')],
      [
        _store('mart', 0.01, 0, ['groceries']),
      ],
    );
    expect(order(route), ['mart']);
    expect(route.warnings.single, contains('cables'));
  });

  test('large lists use the heuristic and still route every item', () async {
    const categories = [
      'groceries',
      'dairy',
      'frozen',
      'produce',
      'bakery',
      'pharmacy',
      'personal_care',
      'hardware',
      'tools',
      'cables',
      'admin_errand',
      'documents',
      'snacks',
      'organic',
    ];
    final stores = [
      for (var i = 0; i < categories.length; i++)
        _store('s$i', 0.002 * i, 0.001 * (i % 3), [categories[i]]),
    ];
    final items = [
      for (var i = 0; i < categories.length; i++)
        _item('i$i', categories[i], order: i),
    ];
    final route = await solve(items, stores);
    expect(route.solverStatus, SolverStatus.feasible);
    final routed = {
      for (final s in route.stops)
        for (final i in s.itemsToPick) i.id,
    };
    expect(routed, {for (final i in items) i.id});
  });

  test(
    'exact solve of 12 tasks over 10+ candidate stores stays under 1.5 s',
    () async {
      const categories = [
        'groceries',
        'dairy',
        'frozen',
        'produce',
        'bakery',
        'pharmacy',
        'personal_care',
        'hardware',
        'tools',
        'cables',
        'admin_errand',
        'snacks',
      ];
      final stores = [
        for (var i = 0; i < 16; i++)
          _store('s$i', 0.003 * (i % 4), 0.003 * (i ~/ 4), [
            categories[i % 12],
            categories[(i * 5 + 3) % 12],
            categories[(i * 7 + 1) % 12],
          ]),
      ];
      final items = [
        for (var i = 0; i < 12; i++)
          _item('i$i', categories[i], order: i, perishable: i == 2),
      ];
      final watch = Stopwatch()..start();
      final route = await solve(items, stores);
      watch.stop();
      expect(route.solverStatus, SolverStatus.optimal);
      expect(watch.elapsedMilliseconds, lessThan(1500));
    },
  );
}
