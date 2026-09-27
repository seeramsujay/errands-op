import 'package:flutter_test/flutter_test.dart';
import 'package:op_list/data/database/app_database.dart';
import 'package:op_list/data/models/store_layout_edge.dart';
import 'package:op_list/services/layout_learning_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late LayoutLearningEngine engine;

  setUp(() async {
    db = AppDatabase.instance;
    await db.init(inMemory: true);
    engine = LayoutLearningEngine(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('Kahns topological sort orders categories deterministically', () {
    final nodes = ['frozen', 'produce', 'bakery', 'dairy'];
    // Edges: produce -> bakery -> dairy -> frozen
    final edges = [
      const StoreLayoutEdge(storeId: 's1', fromItemCategory: 'produce', toItemCategory: 'bakery', forwardWeight: 0.9),
      const StoreLayoutEdge(storeId: 's1', fromItemCategory: 'bakery', toItemCategory: 'dairy', forwardWeight: 0.8),
      const StoreLayoutEdge(storeId: 's1', fromItemCategory: 'dairy', toItemCategory: 'frozen', forwardWeight: 0.95),
    ];

    final sorted = engine.kahnsTopologicalSort(nodes, edges);
    expect(sorted, ['produce', 'bakery', 'dairy', 'frozen']);
  });

  test('Feedback Arc Set breaks directed cycles by severing weakest link', () {
    // Directed cycle: A -> B (0.8) -> C (0.9) -> A (0.3 - weakest)
    final edges = [
      const StoreLayoutEdge(storeId: 's1', fromItemCategory: 'A', toItemCategory: 'B', forwardWeight: 0.8),
      const StoreLayoutEdge(storeId: 's1', fromItemCategory: 'B', toItemCategory: 'C', forwardWeight: 0.9),
      const StoreLayoutEdge(storeId: 's1', fromItemCategory: 'C', toItemCategory: 'A', forwardWeight: 0.3), // weakest
    ];

    final dagEdges = engine.breakCyclesWithFeedbackArcSet(edges);

    expect(dagEdges.length, 2);
    expect(dagEdges.any((e) => e.fromItemCategory == 'C' && e.toItemCategory == 'A'), isFalse);
    expect(dagEdges.any((e) => e.fromItemCategory == 'A' && e.toItemCategory == 'B'), isTrue);
    expect(dagEdges.any((e) => e.fromItemCategory == 'B' && e.toItemCategory == 'C'), isTrue);
  });
}
