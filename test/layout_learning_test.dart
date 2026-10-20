import 'package:flutter_test/flutter_test.dart';
import 'package:op_list/data/database/app_database.dart';
import 'package:op_list/data/models/store_layout_edge.dart';
import 'package:op_list/data/models/todo_item.dart';
import 'package:op_list/data/models/visit.dart';
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

  /// Simulate one visit picking [categories] in order, [gapSec] apart.
  Future<void> visit(String storeId, List<String> categories, {int gapSec = 60, int n = 0}) async {
    final visitId = 'v_${storeId}_${categories.join()}_$n';
    final start = DateTime(2026, 9, 1, 10).add(Duration(days: n));
    await db.insertVisit(StoreVisit(id: visitId, storeId: storeId, entryTimestamp: start));
    for (var i = 0; i < categories.length; i++) {
      await engine.recordCheckoff(
        visitId: visitId,
        itemId: 'item_${categories[i]}_$n',
        itemCategory: categories[i],
        at: start.add(Duration(seconds: gapSec * (i + 1))),
      );
    }
    await engine.processCompletedVisit(storeId: storeId, visitId: visitId);
  }

  test('Kahns topological sort orders categories deterministically', () {
    final nodes = ['frozen', 'produce', 'bakery', 'dairy'];
    final edges = [
      const StoreLayoutEdge(storeId: 's1', fromItemCategory: 'produce', toItemCategory: 'bakery', forwardWeight: 0.9),
      const StoreLayoutEdge(storeId: 's1', fromItemCategory: 'bakery', toItemCategory: 'dairy', forwardWeight: 0.8),
      const StoreLayoutEdge(storeId: 's1', fromItemCategory: 'dairy', toItemCategory: 'frozen', forwardWeight: 0.95),
    ];

    final sorted = engine.kahnsTopologicalSort(nodes, edges);
    expect(sorted, ['produce', 'bakery', 'dairy', 'frozen']);
  });

  test('Kahns sort breaks ties by the given (list) order, not alphabetically', () {
    final sorted = engine.kahnsTopologicalSort(['zucchini', 'apples', 'milk'], const []);
    expect(sorted, ['zucchini', 'apples', 'milk']);
  });

  test('Feedback Arc Set breaks directed cycles by severing weakest link', () {
    final edges = [
      const StoreLayoutEdge(storeId: 's1', fromItemCategory: 'A', toItemCategory: 'B', forwardWeight: 0.8),
      const StoreLayoutEdge(storeId: 's1', fromItemCategory: 'B', toItemCategory: 'C', forwardWeight: 0.9),
      const StoreLayoutEdge(storeId: 's1', fromItemCategory: 'C', toItemCategory: 'A', forwardWeight: 0.3),
    ];

    final dagEdges = engine.breakCyclesWithFeedbackArcSet(edges);

    expect(dagEdges.length, 2);
    expect(dagEdges.any((e) => e.fromItemCategory == 'C' && e.toItemCategory == 'A'), isFalse);
    expect(dagEdges.any((e) => e.fromItemCategory == 'A' && e.toItemCategory == 'B'), isTrue);
    expect(dagEdges.any((e) => e.fromItemCategory == 'B' && e.toItemCategory == 'C'), isTrue);
  });

  test('ten consistent observations outweigh one fast contradicting one', () {
    // Averaging weights would keep B->A (0.9 > 0.5); accumulated evidence keeps A->B.
    final dag = engine.deriveDag(const [
      StoreLayoutEdge(storeId: 's', fromItemCategory: 'A', toItemCategory: 'B', forwardWeight: 0.5, sampleSize: 10),
      StoreLayoutEdge(storeId: 's', fromItemCategory: 'B', toItemCategory: 'A', forwardWeight: 0.9, sampleSize: 1),
    ]);
    expect(dag.single.fromItemCategory, 'A');
    expect(engine.kahnsTopologicalSort(['B', 'A'], dag), ['A', 'B']);
  });

  test('visits train the walk order end-to-end and contradictions cancel out', () async {
    for (var n = 0; n < 3; n++) {
      await visit('store_star_bazaar', ['produce', 'dairy', 'frozen'], n: n);
    }
    // One odd visit the other way round.
    await visit('store_star_bazaar', ['frozen', 'dairy', 'produce'], n: 9);

    final order = await engine.getOptimalWalkOrder(
      storeId: 'store_star_bazaar',
      categoriesToPick: ['frozen', 'produce', 'dairy'],
    );
    expect(order, ['produce', 'dairy', 'frozen']);

    // Both directions are kept as evidence; the derived DAG is acyclic.
    final raw = await db.getLayoutEdges('store_star_bazaar');
    expect(raw.any((e) => e.fromItemCategory == 'frozen' && e.toItemCategory == 'produce'), isTrue);
    final dag = await engine.getLearnedDag('store_star_bazaar');
    expect(dag.any((e) => e.fromItemCategory == 'frozen'), isFalse);
  });

  test('several items of one category count as a single observation', () async {
    const visitId = 'v_multi';
    final t0 = DateTime(2026, 9, 1, 10);
    await db.insertVisit(StoreVisit(id: visitId, storeId: 'store_dmart', entryTimestamp: t0));
    var i = 0;
    for (final cat in ['produce', 'produce', 'produce', 'snacks']) {
      await engine.recordCheckoff(
        visitId: visitId,
        itemId: 'it${i++}',
        itemCategory: cat,
        at: t0.add(Duration(seconds: 30 * i)),
      );
    }
    await engine.processCompletedVisit(storeId: 'store_dmart', visitId: visitId);

    final edges = await db.getLayoutEdges('store_dmart');
    final edge = edges.firstWhere((e) => e.fromItemCategory == 'produce' && e.toItemCategory == 'snacks');
    expect(edge.sampleSize, 1);
  });

  test('learning survives the checked-off item being deleted (e.g. cleared in HA)', () async {
    const visitId = 'v_deleted';
    final t0 = DateTime(2026, 9, 1, 10);
    final now = DateTime.now();
    await db.insertVisit(StoreVisit(id: visitId, storeId: 'store_dmart', entryTimestamp: t0));
    for (final (id, cat, sec) in [('a', 'bakery', 30), ('b', 'snacks', 90)]) {
      await db.insertItem(TodoItem(
        id: id,
        haEntityId: 'todo.shopping_list',
        summary: id,
        category: cat,
        humanOrderIndex: 0,
        createdAt: now,
        updatedAt: now,
      ));
      await engine.recordCheckoff(
        visitId: visitId,
        itemId: id,
        itemCategory: cat,
        at: t0.add(Duration(seconds: sec)),
      );
      await db.deleteItem(id);
    }
    await engine.processCompletedVisit(storeId: 'store_dmart', visitId: visitId);

    final edges = await db.getLayoutEdges('store_dmart');
    expect(edges.any((e) => e.fromItemCategory == 'bakery' && e.toItemCategory == 'snacks'), isTrue);
  });

  test('retracting a check-off removes it from the visit', () async {
    const visitId = 'v_retract';
    await db.insertVisit(StoreVisit(id: visitId, storeId: 'store_dmart', entryTimestamp: DateTime(2026)));
    await engine.recordCheckoff(visitId: visitId, itemId: 'x', itemCategory: 'dairy');
    await engine.retractCheckoff(visitId: visitId, itemId: 'x');
    expect(await db.getCheckoffsForVisit(visitId), isEmpty);
  });
}
