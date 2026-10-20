import 'package:flutter_test/flutter_test.dart';
import 'package:op_list/data/database/app_database.dart';
import 'package:op_list/data/models/store.dart';
import 'package:op_list/services/geofence_engine.dart';
import 'package:op_list/state/app_state.dart';

void main() {
  late AppDatabase db;
  late AppState state;

  setUp(() async {
    db = AppDatabase.instance;
    await db.init(inMemory: true);
    state = AppState(database: db, solveInBackground: false, geofenceAutoTick: false);
    await state.initialize();
  });

  tearDown(() async {
    state.dispose();
    await db.close();
  });

  List<String> summaries() => state.items.map((i) => i.summary).toList();

  test('reordering a filtered list only permutes the visible items', () async {
    // Sample data: 5 items, #3 and #4 (0-based 2, 3) are perishable.
    final before = summaries();
    final perishables = state.items.where((i) => i.isPerishable).toList();
    expect(perishables, hasLength(2));

    // Drag the 2nd perishable above the 1st within the "Cold" filter.
    await state.reorderVisible(perishables, 1, 0);

    final after = summaries();
    expect(after[0], before[0]);
    expect(after[1], before[1]);
    expect(after[2], before[3]);
    expect(after[3], before[2]);
    expect(after[4], before[4]);
    expect(state.items.map((i) => i.humanOrderIndex), [0, 1, 2, 3, 4]);
  });

  test('new items go to the end of the list even after deletions', () async {
    await state.deleteItem(state.items.first.id);
    await state.addItem(summary: 'Last one');
    expect(summaries().last, 'Last one');
    final indices = state.items.map((i) => i.humanOrderIndex).toList();
    expect(indices.toSet().length, indices.length);
  });

  test('editing an item updates its category and perishability', () async {
    final item = state.items.first;
    await state.editItem(item.id,
        summary: 'Renewed passport', description: '', category: 'documents', isPerishable: false);
    final edited = state.items.firstWhere((i) => i.id == item.id);
    expect(edited.summary, 'Renewed passport');
    expect(edited.description, isNull);
    expect(edited.category, 'documents');
  });

  test('solving sets Stop # overlays and clears stale ones', () async {
    await state.solveErrandRoute(departure: DateTime(2026, 9, 28, 11, 0));
    expect(state.items.where((i) => i.optimizedOrderIndex != null), hasLength(5));
    expect(state.activeRoute!.stops, isNotEmpty);

    final done = state.items.first;
    await state.toggleItemCompleted(done.id);
    await state.solveErrandRoute(departure: DateTime(2026, 9, 28, 11, 0));
    expect(state.items.firstWhere((i) => i.id == done.id).optimizedOrderIndex, isNull);
  });

  test('a saved route reloads with its items and warnings', () async {
    final route = await state.solveErrandRoute(departure: DateTime(2026, 9, 28, 16, 50));
    final reloaded = await db.getActiveRoute();
    expect(reloaded!.warnings, route.warnings);
    expect(
      reloaded.stops.map((s) => s.itemsToPick.map((i) => i.id).toList()),
      route.stops.map((s) => s.itemsToPick.map((i) => i.id).toList()),
    );
  });

  test('in-store list shows what the route assigned to that store', () async {
    final route = await state.solveErrandRoute(departure: DateTime(2026, 9, 28, 11, 0));
    for (final stop in route.stops) {
      final items = await state.getInStoreWalkOrderItems(stop.store!);
      expect(items.map((i) => i.id).toSet(), stop.itemsToPick.map((i) => i.id).toSet());
    }
  });

  test('checking items off inside a store trains its preferences', () async {
    final dmart = state.stores.firstWhere((s) => s.id == 'store_dmart');
    await state.simulateStoreEntry(dmart);
    expect(state.geofenceState, GeofenceState.insideStore);

    final frozen = state.items.firstWhere((i) => i.category == 'frozen');
    await state.toggleItemCompleted(frozen.id);
    await state.simulateStoreExit();

    final prefs = await db.getPreferences();
    expect(prefs.any((p) => p.storeId == 'store_dmart' && p.itemCategory == 'frozen'), isTrue);
  });

  test('stores can be added, edited and deleted', () async {
    const store = Store(
      id: 'store_new',
      name: 'Corner Shop',
      latitude: 12.97,
      longitude: 77.6,
      supportedCategories: ['snacks'],
    );
    await state.saveStore(store);
    expect(state.stores.any((s) => s.name == 'Corner Shop'), isTrue);

    await state.saveStore(store.copyWith(name: 'Corner Shop 24x7'));
    expect(state.stores.where((s) => s.id == 'store_new').single.name, 'Corner Shop 24x7');

    await state.solveErrandRoute();
    await state.deleteStore('store_dmart');
    expect(state.stores.any((s) => s.id == 'store_dmart'), isFalse);
    expect(await db.getLayoutEdges('store_dmart'), isEmpty);
    expect(state.activeRoute, isNull); // stale route dropped
  });

  test('home location and reset keep settings', () async {
    await state.setHomeLocation(12.95, 77.55);
    await db.setSetting(SettingKeys.haUrl, 'http://ha.local:8123');
    await state.addItem(summary: 'Scratch');
    await state.simulateResetData();

    expect(state.items.any((i) => i.summary == 'Scratch'), isFalse);
    expect(await db.getSetting(SettingKeys.homeLat), '12.95');
    expect(await db.getSetting(SettingKeys.haUrl), 'http://ha.local:8123');
  });
}
