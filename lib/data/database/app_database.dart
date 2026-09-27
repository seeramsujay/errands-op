import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import '../models/todo_item.dart';
import '../models/store.dart';
import '../models/preference.dart';
import '../models/visit.dart';
import '../models/store_layout_edge.dart';
import '../models/active_route.dart';
import '../models/route_stop.dart';
import '../models/mutation_record.dart';

/// Local SQLite Database manager implementing the core schema
class AppDatabase {
  static AppDatabase? _instance;
  Database? _db;

  AppDatabase._();

  static AppDatabase get instance => _instance ??= AppDatabase._();

  /// Expose raw db if needed
  Database get db {
    if (_db == null) {
      throw StateError('Database not initialized. Call init() first.');
    }
    return _db!;
  }

  /// Initialize SQLite database for mobile, desktop, or in-memory tests
  Future<void> init({bool inMemory = false, String dbName = 'op_list.db'}) async {
    if (_db != null && _db!.isOpen) return;

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS || inMemory) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    String path;
    if (inMemory) {
      path = inMemoryDatabasePath;
    } else {
      final dbFolder = await getDatabasesPath();
      path = p.join(dbFolder, dbName);
    }

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );

    // Seed default sample stores and preferences if empty
    await _seedInitialData();
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1. Home Assistant Synced To-Do Items
    await db.execute('''
      CREATE TABLE items (  
        id TEXT PRIMARY KEY NOT NULL,  
        ha_entity_id TEXT NOT NULL,  
        summary TEXT NOT NULL,  
        description TEXT,  
        category TEXT DEFAULT 'generic',  
        is_perishable INTEGER NOT NULL DEFAULT 0 CHECK (is_perishable IN (0, 1)),  
        status TEXT NOT NULL DEFAULT 'needs_action' CHECK (status IN ('needs_action', 'completed')),  
        human_order_index INTEGER NOT NULL,  
        optimized_order_index INTEGER,  
        is_pinned INTEGER NOT NULL DEFAULT 0 CHECK (is_pinned IN (0, 1)),  
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,  
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP  
      );
    ''');

    // 2. Store Master Entities
    await db.execute('''
      CREATE TABLE stores (  
        id TEXT PRIMARY KEY NOT NULL,  
        name TEXT NOT NULL,  
        brand TEXT,  
        latitude REAL NOT NULL,  
        longitude REAL NOT NULL,  
        geofence_radius_meters REAL NOT NULL DEFAULT 50.0,  
        opening_time_sec INTEGER,  
        closing_time_sec INTEGER,  
        avg_checkout_delay_sec INTEGER DEFAULT 600,
        supported_categories TEXT
      );
    ''');

    // 3. Item Category to Store Preference Counter
    await db.execute('''
      CREATE TABLE item_store_preferences (  
        id TEXT PRIMARY KEY NOT NULL,  
        item_category TEXT NOT NULL,  
        store_id TEXT NOT NULL,  
        selection_count INTEGER NOT NULL DEFAULT 1,  
        confidence_score REAL NOT NULL DEFAULT 0.5,  
        FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE  
      );
    ''');

    // 4. Historical In-Store Visit Records
    await db.execute('''
      CREATE TABLE visits (  
        id TEXT PRIMARY KEY NOT NULL,  
        store_id TEXT NOT NULL,  
        entry_timestamp DATETIME NOT NULL,  
        exit_timestamp DATETIME,  
        FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE  
      );
    ''');

    // 5. In-Store Check-Off Event Timestamps
    await db.execute('''
      CREATE TABLE visit_checkoffs (  
        id TEXT PRIMARY KEY NOT NULL,  
        visit_id TEXT NOT NULL,  
        item_id TEXT NOT NULL,  
        checkoff_timestamp DATETIME NOT NULL,  
        FOREIGN KEY (visit_id) REFERENCES visits(id) ON DELETE CASCADE,  
        FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE  
      );
    ''');

    // 6. Directed Store Layout Graph
    await db.execute('''
      CREATE TABLE store_layout_edges (  
        store_id TEXT NOT NULL,  
        from_item_category TEXT NOT NULL,  
        to_item_category TEXT NOT NULL,  
        forward_weight REAL NOT NULL DEFAULT 0.0,  
        sample_size INTEGER NOT NULL DEFAULT 0,  
        PRIMARY KEY (store_id, from_item_category, to_item_category),  
        FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE  
      );
    ''');

    // 7. Active Route Executions
    await db.execute('''
      CREATE TABLE active_routes (  
        id TEXT PRIMARY KEY NOT NULL,  
        generated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,  
        total_distance_meters REAL NOT NULL,  
        total_duration_seconds REAL NOT NULL,  
        solver_status TEXT NOT NULL  
      );
    ''');

    // 8. Route Stops
    await db.execute('''
      CREATE TABLE route_stops (  
        id TEXT PRIMARY KEY NOT NULL,  
        route_id TEXT NOT NULL,  
        stop_sequence INTEGER NOT NULL,  
        store_id TEXT NOT NULL,  
        estimated_arrival DATETIME NOT NULL,  
        estimated_departure DATETIME NOT NULL,  
        is_completed INTEGER NOT NULL DEFAULT 0 CHECK (is_completed IN (0, 1)),  
        FOREIGN KEY (route_id) REFERENCES active_routes(id) ON DELETE CASCADE,  
        FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE  
      );
    ''');

    // 9. Mutation Queue
    await db.execute('''
      CREATE TABLE mutation_queue (
        id TEXT PRIMARY KEY NOT NULL,
        item_id TEXT NOT NULL,
        field TEXT NOT NULL,
        value TEXT,
        hlc_timestamp TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        retry_count INTEGER NOT NULL DEFAULT 0,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    ''');

    // 10. Geohash Spatial Matrix Cache
    await db.execute('''
      CREATE TABLE geohash_matrix_cache (
        origin_geohash TEXT NOT NULL,
        dest_geohash TEXT NOT NULL,
        distance_meters REAL NOT NULL,
        duration_seconds REAL NOT NULL,
        cached_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (origin_geohash, dest_geohash)
      );
    ''');

    // Indices for Low-Latency Spatial and Status Lookups
    await db.execute('CREATE INDEX idx_items_status ON items(status);');
    await db.execute('CREATE INDEX idx_stores_spatial ON stores(latitude, longitude);');
    await db.execute('CREATE INDEX idx_edges_lookup ON store_layout_edges(store_id, from_item_category);');
  }

  Future<void> _seedInitialData() async {
    final storeCount = Sqflite.firstIntValue(
      await _db!.rawQuery('SELECT COUNT(*) FROM stores'),
    );

    if (storeCount != null && storeCount > 0) return;

    // Seed realistic candidate stores from product specs (DMart, Star Bazaar, Pharmacy, Hardware, Office)
    final initialStores = [
      Store(
        id: 'store_dmart',
        name: 'DMart Hypermarket',
        brand: 'DMart',
        latitude: 12.9716,
        longitude: 77.5946,
        geofenceRadiusMeters: 50.0,
        openingTimeSec: 32400, // 09:00 AM
        closingTimeSec: 79200, // 10:00 PM
        avgCheckoutDelaySec: 900, // 15 mins
        supportedCategories: ['groceries', 'dairy', 'frozen', 'produce', 'snacks'],
      ),
      Store(
        id: 'store_star_bazaar',
        name: 'Star Bazaar',
        brand: 'Star',
        latitude: 12.9780,
        longitude: 77.6010,
        geofenceRadiusMeters: 50.0,
        openingTimeSec: 36000, // 10:00 AM
        closingTimeSec: 75600, // 09:00 PM
        avgCheckoutDelaySec: 600,
        supportedCategories: ['groceries', 'dairy', 'frozen', 'bakery', 'organic'],
      ),
      Store(
        id: 'store_apollo',
        name: 'Apollo Pharmacy',
        brand: 'Apollo',
        latitude: 12.9650,
        longitude: 77.5890,
        geofenceRadiusMeters: 40.0,
        openingTimeSec: 28800, // 08:00 AM
        closingTimeSec: 82800, // 11:00 PM
        avgCheckoutDelaySec: 300,
        supportedCategories: ['pharmacy', 'health', 'personal_care'],
      ),
      Store(
        id: 'store_hardware',
        name: 'Precision Hardware Mart',
        brand: 'Local',
        latitude: 12.9850,
        longitude: 77.6100,
        geofenceRadiusMeters: 45.0,
        openingTimeSec: 34200, // 09:30 AM
        closingTimeSec: 72000, // 08:00 PM
        avgCheckoutDelaySec: 420,
        supportedCategories: ['hardware', 'tools', 'cables'],
      ),
      Store(
        id: 'store_admin_office',
        name: 'Regional Transport / Passport Office',
        brand: 'Govt',
        latitude: 12.9590,
        longitude: 77.5750,
        geofenceRadiusMeters: 60.0,
        openingTimeSec: 36000, // 10:00 AM
        closingTimeSec: 61200, // 05:00 PM (Strict early closing time!)
        avgCheckoutDelaySec: 1800, // 30 mins
        supportedCategories: ['admin_errand', 'documents'],
      ),
    ];

    for (final s in initialStores) {
      await insertStore(s);
    }

    // Seed initial errand & shopping items
    final now = DateTime.now();
    final initialItems = [
      TodoItem(
        id: 'item_1',
        haEntityId: 'todo.shopping_list',
        summary: 'Passport Application Attestation',
        description: 'Fixed administrative stop with strict closing hours',
        category: 'admin_errand',
        isPerishable: false,
        status: 'needs_action',
        humanOrderIndex: 0,
        isPinned: false,
        createdAt: now,
        updatedAt: now,
      ),
      TodoItem(
        id: 'item_2',
        haEntityId: 'todo.shopping_list',
        summary: 'Bicycle Brake Wire & Hex Key',
        description: 'Need replacement 1.8mm stainless cable',
        category: 'hardware',
        isPerishable: false,
        status: 'needs_action',
        humanOrderIndex: 1,
        isPinned: false,
        createdAt: now,
        updatedAt: now,
      ),
      TodoItem(
        id: 'item_3',
        haEntityId: 'todo.shopping_list',
        summary: 'Almond Milk & Greek Yogurt',
        description: 'Chilled dairy products',
        category: 'dairy',
        isPerishable: true, // Perishable!
        status: 'needs_action',
        humanOrderIndex: 2,
        isPinned: false,
        createdAt: now,
        updatedAt: now,
      ),
      TodoItem(
        id: 'item_4',
        haEntityId: 'todo.shopping_list',
        summary: 'Belgian Chocolate Gelato Ice Cream',
        description: 'Highly temperature sensitive - keep cold',
        category: 'frozen',
        isPerishable: true, // Perishable! Must defer to final leg
        status: 'needs_action',
        humanOrderIndex: 3,
        isPinned: false,
        createdAt: now,
        updatedAt: now,
      ),
      TodoItem(
        id: 'item_5',
        haEntityId: 'todo.shopping_list',
        summary: 'Multivitamins & Paracetamol',
        description: 'Refill monthly prescription',
        category: 'pharmacy',
        isPerishable: false,
        status: 'needs_action',
        humanOrderIndex: 4,
        isPinned: false,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    for (final item in initialItems) {
      await insertItem(item);
    }

    // Seed item-store preferences
    await insertPreference(ItemStorePreference(
      id: 'pref_1',
      itemCategory: 'groceries',
      storeId: 'store_dmart',
      selectionCount: 12,
      confidenceScore: 0.85,
    ));
    await insertPreference(ItemStorePreference(
      id: 'pref_2',
      itemCategory: 'dairy',
      storeId: 'store_star_bazaar',
      selectionCount: 8,
      confidenceScore: 0.75,
    ));
    await insertPreference(ItemStorePreference(
      id: 'pref_3',
      itemCategory: 'pharmacy',
      storeId: 'store_apollo',
      selectionCount: 15,
      confidenceScore: 0.95,
    ));
    await insertPreference(ItemStorePreference(
      id: 'pref_4',
      itemCategory: 'hardware',
      storeId: 'store_hardware',
      selectionCount: 9,
      confidenceScore: 0.90,
    ));
    await insertPreference(ItemStorePreference(
      id: 'pref_5',
      itemCategory: 'admin_errand',
      storeId: 'store_admin_office',
      selectionCount: 5,
      confidenceScore: 1.0,
    ));

    // Seed initial walk-order layout graph for DMart (Produce -> Bakery -> Dairy -> Frozen)
    await insertLayoutEdge(StoreLayoutEdge(
      storeId: 'store_dmart',
      fromItemCategory: 'produce',
      toItemCategory: 'dairy',
      forwardWeight: 0.82,
      sampleSize: 5,
    ));
    await insertLayoutEdge(StoreLayoutEdge(
      storeId: 'store_dmart',
      fromItemCategory: 'dairy',
      toItemCategory: 'frozen',
      forwardWeight: 0.91,
      sampleSize: 6,
    ));
    await insertLayoutEdge(StoreLayoutEdge(
      storeId: 'store_dmart',
      fromItemCategory: 'groceries',
      toItemCategory: 'frozen',
      forwardWeight: 0.74,
      sampleSize: 4,
    ));
  }

  // --- CRUD Operations for Items ---

  Future<List<TodoItem>> getItems() async {
    final maps = await db.query(
      'items',
      orderBy: 'human_order_index ASC',
    );
    return maps.map((m) => TodoItem.fromMap(m)).toList();
  }

  Future<TodoItem?> getItem(String id) async {
    final maps = await db.query(
      'items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return TodoItem.fromMap(maps.first);
  }

  Future<void> insertItem(TodoItem item) async {
    await db.insert(
      'items',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateItem(TodoItem item) async {
    await db.update(
      'items',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> updateItemOrder(List<TodoItem> items) async {
    final batch = db.batch();
    for (var i = 0; i < items.length; i++) {
      batch.update(
        'items',
        {'human_order_index': i, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [items[i].id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateOptimizedIndices(Map<String, int> itemToOptimizedIndex) async {
    final batch = db.batch();
    itemToOptimizedIndex.forEach((itemId, optIndex) {
      batch.update(
        'items',
        {'optimized_order_index': optIndex},
        where: 'id = ?',
        whereArgs: [itemId],
      );
    });
    await batch.commit(noResult: true);
  }

  Future<void> deleteItem(String id) async {
    await db.delete(
      'items',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- CRUD Operations for Stores ---

  Future<List<Store>> getStores() async {
    final maps = await db.query('stores', orderBy: 'name ASC');
    return maps.map((m) => Store.fromMap(m)).toList();
  }

  Future<Store?> getStore(String id) async {
    final maps = await db.query(
      'stores',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Store.fromMap(maps.first);
  }

  Future<void> insertStore(Store store) async {
    await db.insert(
      'stores',
      store.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- CRUD Operations for Preferences ---

  Future<List<ItemStorePreference>> getPreferences() async {
    final maps = await db.query('item_store_preferences');
    return maps.map((m) => ItemStorePreference.fromMap(m)).toList();
  }

  Future<void> insertPreference(ItemStorePreference pref) async {
    await db.insert(
      'item_store_preferences',
      pref.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> incrementPreference(String category, String storeId) async {
    final existing = await db.query(
      'item_store_preferences',
      where: 'item_category = ? AND store_id = ?',
      whereArgs: [category, storeId],
      limit: 1,
    );

    if (existing.isEmpty) {
      final id = 'pref_${category}_$storeId';
      await insertPreference(ItemStorePreference(
        id: id,
        itemCategory: category,
        storeId: storeId,
        selectionCount: 1,
        confidenceScore: 0.5,
      ));
    } else {
      final count = (existing.first['selection_count'] as int? ?? 0) + 1;
      final newScore = (count / (count + 2.0)).clamp(0.1, 0.99);
      await db.update(
        'item_store_preferences',
        {'selection_count': count, 'confidence_score': newScore},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  // --- CRUD Operations for Visits & Check-offs ---

  Future<void> insertVisit(StoreVisit visit) async {
    await db.insert(
      'visits',
      visit.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateVisit(StoreVisit visit) async {
    await db.update(
      'visits',
      visit.toMap(),
      where: 'id = ?',
      whereArgs: [visit.id],
    );
  }

  Future<StoreVisit?> getActiveVisit() async {
    final maps = await db.query(
      'visits',
      where: 'exit_timestamp IS NULL',
      orderBy: 'entry_timestamp DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return StoreVisit.fromMap(maps.first);
  }

  Future<void> insertCheckoff(VisitCheckoff checkoff) async {
    await db.insert(
      'visit_checkoffs',
      checkoff.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<VisitCheckoff>> getCheckoffsForVisit(String visitId) async {
    final query = '''
      SELECT vc.*, i.category as item_category 
      FROM visit_checkoffs vc
      LEFT JOIN items i ON vc.item_id = i.id
      WHERE vc.visit_id = ?
      ORDER BY vc.checkoff_timestamp ASC
    ''';
    final rows = await db.rawQuery(query, [visitId]);
    return rows.map((r) => VisitCheckoff.fromMap(
      r,
      itemCategory: (r['item_category'] as String?) ?? 'generic',
    )).toList();
  }

  // --- CRUD Operations for Store Layout Graph ---

  Future<List<StoreLayoutEdge>> getLayoutEdges(String storeId) async {
    final maps = await db.query(
      'store_layout_edges',
      where: 'store_id = ?',
      whereArgs: [storeId],
    );
    return maps.map((m) => StoreLayoutEdge.fromMap(m)).toList();
  }

  Future<void> insertLayoutEdge(StoreLayoutEdge edge) async {
    await db.insert(
      'store_layout_edges',
      edge.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- CRUD Operations for Active Routes ---

  Future<void> saveActiveRoute(ActiveRoute route) async {
    await db.transaction((txn) async {
      await txn.delete('route_stops');
      await txn.delete('active_routes');

      await txn.insert('active_routes', route.toMap());
      for (final stop in route.stops) {
        await txn.insert('route_stops', stop.toMap());
      }
    });
  }

  Future<ActiveRoute?> getActiveRoute() async {
    final routeRows = await db.query('active_routes', limit: 1);
    if (routeRows.isEmpty) return null;

    final routeMap = routeRows.first;
    final routeId = routeMap['id'] as String;

    final stopRows = await db.query(
      'route_stops',
      where: 'route_id = ?',
      whereArgs: [routeId],
      orderBy: 'stop_sequence ASC',
    );

    final stores = await getStores();
    final storeMap = {for (final s in stores) s.id: s};

    final stops = stopRows.map((r) {
      final sId = r['store_id'] as String;
      return RouteStop.fromMap(r, store: storeMap[sId]);
    }).toList();

    return ActiveRoute.fromMap(routeMap, stops: stops);
  }

  // --- Mutation Queue Operations ---

  Future<void> enqueueMutation(MutationRecord mutation) async {
    await db.insert(
      'mutation_queue',
      mutation.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MutationRecord>> getPendingMutations() async {
    final maps = await db.query(
      'mutation_queue',
      where: "status = 'pending'",
      orderBy: 'created_at ASC',
    );
    return maps.map((m) => MutationRecord.fromMap(m)).toList();
  }

  Future<void> markMutationSynced(String id) async {
    await db.update(
      'mutation_queue',
      {'status': 'synced'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markMutationFailed(String id) async {
    await db.rawUpdate('''
      UPDATE mutation_queue 
      SET retry_count = retry_count + 1,
          status = CASE WHEN retry_count >= 5 THEN 'failed' ELSE 'pending' END
      WHERE id = ?
    ''', [id]);
  }

  // --- Geohash Matrix Cache Operations ---

  Future<Map<String, double>?> getCachedMatrix(String originGeohash, String destGeohash) async {
    final rows = await db.query(
      'geohash_matrix_cache',
      where: 'origin_geohash = ? AND dest_geohash = ?',
      whereArgs: [originGeohash, destGeohash],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final row = rows.first;
    final cachedAt = DateTime.parse(row['cached_at'] as String);

    // 7-day TTL check
    if (DateTime.now().difference(cachedAt).inDays > 7) {
      return null;
    }

    return {
      'distance': (row['distance_meters'] as num).toDouble(),
      'duration': (row['duration_seconds'] as num).toDouble(),
    };
  }

  Future<void> cacheMatrixResult(
    String originGeohash,
    String destGeohash,
    double distanceMeters,
    double durationSeconds,
  ) async {
    await db.insert(
      'geohash_matrix_cache',
      {
        'origin_geohash': originGeohash,
        'dest_geohash': destGeohash,
        'distance_meters': distanceMeters,
        'duration_seconds': durationSeconds,
        'cached_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
