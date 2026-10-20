import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:op_list/core/categories.dart';
import 'package:op_list/data/database/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;
  late String path;
  final db = AppDatabase.instance;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('oplist_db_test');
    path = p.join(tmp.path, 'op_list.db');
    sqfliteFfiInit();
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  test('a version 1 database is migrated in place without losing data', () async {
    // The original v1 schema (subset of tables the migration touches).
    final v1 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, _) async {
            await d.execute('''CREATE TABLE items (id TEXT PRIMARY KEY NOT NULL, ha_entity_id TEXT NOT NULL,
              summary TEXT NOT NULL, description TEXT, category TEXT DEFAULT 'generic',
              is_perishable INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'needs_action',
              human_order_index INTEGER NOT NULL, optimized_order_index INTEGER,
              is_pinned INTEGER NOT NULL DEFAULT 0, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
              updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP)''');
            await d.execute('''CREATE TABLE stores (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, brand TEXT,
              latitude REAL NOT NULL, longitude REAL NOT NULL, geofence_radius_meters REAL NOT NULL DEFAULT 50.0,
              opening_time_sec INTEGER, closing_time_sec INTEGER, avg_checkout_delay_sec INTEGER DEFAULT 600,
              supported_categories TEXT)''');
            await d.execute('''CREATE TABLE item_store_preferences (id TEXT PRIMARY KEY NOT NULL,
              item_category TEXT NOT NULL, store_id TEXT NOT NULL, selection_count INTEGER NOT NULL DEFAULT 1,
              confidence_score REAL NOT NULL DEFAULT 0.5)''');
            await d.execute('''CREATE TABLE visits (id TEXT PRIMARY KEY NOT NULL, store_id TEXT NOT NULL,
              entry_timestamp DATETIME NOT NULL, exit_timestamp DATETIME)''');
            await d.execute('''CREATE TABLE visit_checkoffs (id TEXT PRIMARY KEY NOT NULL, visit_id TEXT NOT NULL,
              item_id TEXT NOT NULL, checkoff_timestamp DATETIME NOT NULL)''');
            await d.execute('''CREATE TABLE store_layout_edges (store_id TEXT NOT NULL,
              from_item_category TEXT NOT NULL, to_item_category TEXT NOT NULL,
              forward_weight REAL NOT NULL DEFAULT 0.0, sample_size INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY (store_id, from_item_category, to_item_category))''');
            await d.execute('''CREATE TABLE active_routes (id TEXT PRIMARY KEY NOT NULL,
              generated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, total_distance_meters REAL NOT NULL,
              total_duration_seconds REAL NOT NULL, solver_status TEXT NOT NULL)''');
            await d.execute('''CREATE TABLE route_stops (id TEXT PRIMARY KEY NOT NULL, route_id TEXT NOT NULL,
              stop_sequence INTEGER NOT NULL, store_id TEXT NOT NULL, estimated_arrival DATETIME NOT NULL,
              estimated_departure DATETIME NOT NULL, is_completed INTEGER NOT NULL DEFAULT 0)''');
            await d.execute('''CREATE TABLE mutation_queue (id TEXT PRIMARY KEY NOT NULL, item_id TEXT NOT NULL,
              field TEXT NOT NULL, value TEXT, hlc_timestamp TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending',
              retry_count INTEGER NOT NULL DEFAULT 0, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP)''');
            await d.execute('''CREATE TABLE geohash_matrix_cache (origin_geohash TEXT NOT NULL,
              dest_geohash TEXT NOT NULL, distance_meters REAL NOT NULL, duration_seconds REAL NOT NULL,
              cached_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (origin_geohash, dest_geohash))''');
          },
        ));
    await v1.insert('stores', {'id': 'my_store', 'name': 'Mine', 'latitude': 1.0, 'longitude': 2.0});
    await v1.insert('items', {
      'id': 'it1',
      'ha_entity_id': 'todo.shopping_list',
      'summary': 'Milk',
      'category': 'dairy',
      'human_order_index': 0,
    });
    await v1.insert('visits', {'id': 'v1', 'store_id': 'my_store', 'entry_timestamp': '2026-01-01T10:00:00'});
    await v1.insert('visit_checkoffs',
        {'id': 'c1', 'visit_id': 'v1', 'item_id': 'it1', 'checkoff_timestamp': '2026-01-01T10:05:00'});
    await v1.close();

    await db.init(path: path);

    expect((await db.getItems()).single.summary, 'Milk');
    // The user's own data is kept and the sample data is NOT added on upgrade.
    expect((await db.getStores()).map((s) => s.id), ['my_store']);
    // Check-off categories were backfilled, so they survive deleting the item.
    await db.deleteItem('it1');
    expect((await db.getCheckoffsForVisit('v1')).single.itemCategory, 'dairy');
    // New tables/columns work.
    await db.setSetting(SettingKeys.homeLat, '1.5');
    expect(await db.getSetting(SettingKeys.homeLat), '1.5');
  });

  test('sample data is seeded once; deleting all stores does not resurrect it', () async {
    await db.init(path: path);
    expect(await db.getStores(), isNotEmpty);
    for (final s in await db.getStores()) {
      await db.deleteStore(s.id);
    }
    await db.close();

    await db.init(path: path);
    expect(await db.getStores(), isEmpty);
  });

  test('failed mutations are parked after the configured number of retries', () async {
    await db.init(path: path);
    await db.db.insert('mutation_queue', {
      'id': 'm1',
      'item_id': 'x',
      'field': 'status',
      'hlc_timestamp': '1:0000:n',
      'created_at': DateTime.now().toIso8601String(),
    });
    for (var i = 0; i < 4; i++) {
      await db.markMutationFailed('m1');
    }
    expect(await db.getPendingMutations(), hasLength(1));
    await db.markMutationFailed('m1');
    expect(await db.getPendingMutations(), isEmpty);
    expect(await db.countFailedMutations(), 1);
  });

  group('category classifier', () {
    test('recognises common items', () {
      expect(ItemCategories.classify('Belgian chocolate ice cream').id, 'frozen');
      expect(ItemCategories.classify('2L milk').id, 'dairy');
      expect(ItemCategories.classify('Paracetamol 500mg').id, 'pharmacy');
      expect(ItemCategories.classify('Batteries AA').id, 'hardware');
      expect(ItemCategories.classify('Renew passport').id, 'admin_errand');
      expect(ItemCategories.classify('Tomatoes').id, 'produce');
    });

    test('matches whole words only', () {
      expect(ItemCategories.classify('Rice').id, 'groceries'); // not "ice"
      expect(ItemCategories.classify('Call grandma').id, ItemCategories.generic);
    });

    test('marks cold categories as perishable', () {
      expect(ItemCategories.classify('Ice cream').perishableByDefault, isTrue);
      expect(ItemCategories.classify('Screws').perishableByDefault, isFalse);
    });
  });
}
