import 'package:flutter_test/flutter_test.dart';
import 'package:op_list/data/database/app_database.dart';
import 'package:op_list/data/models/preference.dart';
import 'package:op_list/data/models/store.dart';
import 'package:op_list/data/models/todo_item.dart';
import 'package:op_list/services/distance_matrix_service.dart';
import 'package:op_list/services/vrp_solver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late DistanceMatrixService matrixService;
  late VrpSolver solver;

  setUp(() async {
    db = AppDatabase.instance;
    await db.init(inMemory: true);
    matrixService = DistanceMatrixService(database: db);
    solver = VrpSolver(matrixService: matrixService);
  });

  tearDown(() async {
    await db.close();
  });

  test('VrpSolver solves multi-stop route with perishable deferred to end', () async {
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
        isPerishable: true, // Perishable!
        humanOrderIndex: 0,
        createdAt: now,
        updatedAt: now,
      ),
      TodoItem(
        id: '2',
        haEntityId: 'todo.list',
        summary: 'Wrench',
        category: 'hardware',
        isPerishable: false,
        humanOrderIndex: 1,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    final route = await solver.solveRoute(VrpSolverRequest(
      originCoordinates: [12.9716, 77.5946],
      departureTime: now,
      items: items,
      candidateStores: stores,
    ));

    expect(route.stops.length, 2);
    // Even though Ice cream had humanOrderIndex 0, solver thermal decay pushes
    // the perishable dairy/frozen store to the final stop!
    expect(route.stops.first.storeId, 'store_hardware');
    expect(route.stops.last.storeId, 'store_dairy');
    expect(route.stops.last.hasPerishable, isTrue);
  });

  test('VrpSolver respects user manual pin as hard sequence lock', () async {
    final now = DateTime.now();
    final stores = [
      const Store(
        id: 'store_pharmacy',
        name: 'Pharmacy',
        latitude: 12.9850,
        longitude: 77.6100,
        supportedCategories: ['pharmacy'],
      ),
      const Store(
        id: 'store_groceries',
        name: 'Supermarket',
        latitude: 12.9720,
        longitude: 77.5950,
        supportedCategories: ['groceries'],
      ),
    ];

    final items = [
      TodoItem(
        id: '1',
        haEntityId: 'todo.list',
        summary: 'Emergency Medicine',
        category: 'pharmacy',
        humanOrderIndex: 0,
        isPinned: true, // User hard locked pharmacy first!
        createdAt: now,
        updatedAt: now,
      ),
      TodoItem(
        id: '2',
        haEntityId: 'todo.list',
        summary: 'Cereal',
        category: 'groceries',
        humanOrderIndex: 1,
        isPinned: false,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    final route = await solver.solveRoute(VrpSolverRequest(
      originCoordinates: [12.9716, 77.5946],
      departureTime: now,
      items: items,
      candidateStores: stores,
    ));

    expect(route.stops.first.storeId, 'store_pharmacy');
    expect(route.stops.first.isUserPinned, isTrue);
  });

  test('VrpSolver flags closing time violation in constraint relaxation cascade', () async {
    // Departure at 20:00 (8pm), store closes at 20:15 (8:15pm), but travel + checkout is 30 mins
    final departure = DateTime(2026, 9, 27, 20, 0, 0);
    final stores = [
      const Store(
        id: 'store_early_close',
        name: 'Early Closing Shop',
        latitude: 13.1000, // Far away
        longitude: 77.7000,
        openingTimeSec: 28800, // 8am
        closingTimeSec: 72900, // 8:15pm = 20*3600 + 15*60
        supportedCategories: ['hardware'],
      ),
    ];

    final items = [
      TodoItem(
        id: '1',
        haEntityId: 'todo.list',
        summary: 'Screws',
        category: 'hardware',
        humanOrderIndex: 0,
        createdAt: departure,
        updatedAt: departure,
      ),
    ];

    final route = await solver.solveRoute(VrpSolverRequest(
      originCoordinates: [12.9716, 77.5946],
      departureTime: departure,
      items: items,
      candidateStores: stores,
    ));

    expect(route.solverStatus, 'RELAXED_CONSTRAINTS');
    expect(route.stops.first.violatesClosingTime, isTrue);
    expect(route.warnings.isNotEmpty, isTrue);
  });
}
