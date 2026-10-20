import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../core/hlc.dart';
import '../core/kalman_filter.dart';
import '../data/database/app_database.dart';
import '../data/models/active_route.dart';
import '../data/models/preference.dart';
import '../data/models/store.dart';
import '../data/models/todo_item.dart';
import '../data/sync/ha_websocket_client.dart';
import '../data/sync/mutation_engine.dart';
import '../services/distance_matrix_service.dart';
import '../services/geofence_engine.dart';
import '../services/layout_learning_engine.dart';
import '../services/location_service.dart';
import '../services/vrp_solver.dart';

/// Central Reactive State Provider for op-list
class AppState extends ChangeNotifier {
  // Used until the user sets a home location (Bangalore city centre).
  static const double defaultHomeLat = 12.9698;
  static const double defaultHomeLon = 77.5986;

  final AppDatabase database;
  final LocationService locationService;
  late final HomeAssistantWsClient haClient;
  late final MutationEngine mutationEngine;
  late final DistanceMatrixService matrixService;
  late final VrpSolver vrpSolver;
  late final LayoutLearningEngine layoutLearningEngine;
  late final GeofenceEngine geofenceEngine;

  List<TodoItem> _items = [];
  List<Store> _stores = [];
  List<ItemStorePreference> _preferences = [];
  ActiveRoute? _activeRoute;

  GeofenceState _geofenceState = GeofenceState.outsideStore;
  Store? _activeStore;
  int _dwellSeconds = 0;
  HaConnectionState _haState = HaConnectionState.notConfigured;
  bool _isSolving = false;
  bool _initialized = false;
  bool _disposed = false;
  // Snapshot/state handlers run async; serialise them so the DB is never
  // reconciled twice at once and dispose can wait for the last one.
  Future<void> _pendingSync = Future.value();
  int _failedSyncCount = 0;

  double _homeLat = defaultHomeLat;
  double _homeLon = defaultHomeLon;
  bool _homeIsSet = false;
  // Last known position (GPS or simulated); null until one arrives.
  double? _userLat;
  double? _userLon;
  DateTime? _userFixAt;
  bool _gpsTracking = false;

  StreamSubscription? _haStateSub;
  StreamSubscription? _haItemsSub;
  StreamSubscription? _geofenceSub;
  StreamSubscription? _dwellSub;

  AppState({
    required this.database,
    HomeAssistantWsClient? haClient,
    LocationService? locationService,
    bool solveInBackground = true,
    bool geofenceAutoTick = true,
  }) : locationService = locationService ?? LocationService() {
    this.haClient = haClient ?? HomeAssistantWsClient();
    mutationEngine = MutationEngine(database: database, wsClient: this.haClient);
    matrixService = DistanceMatrixService(database: database);
    vrpSolver = VrpSolver(matrixService: matrixService, runInBackground: solveInBackground);
    layoutLearningEngine = LayoutLearningEngine(database: database);
    geofenceEngine = GeofenceEngine(
      database: database,
      layoutLearningEngine: layoutLearningEngine,
      autoTick: geofenceAutoTick,
    );
    _haState = this.haClient.state;

    _initListeners();
  }

  List<TodoItem> get items => _items;
  List<Store> get stores => _stores;
  List<ItemStorePreference> get preferences => _preferences;
  ActiveRoute? get activeRoute => _activeRoute;
  GeofenceState get geofenceState => _geofenceState;
  Store? get activeStore => _activeStore;
  int get dwellSeconds => _dwellSeconds;
  HaConnectionState get haState => _haState;
  String? get haError => haClient.lastError;
  int get failedSyncCount => _failedSyncCount;
  bool get isSolving => _isSolving;
  bool get initialized => _initialized;
  bool get gpsTracking => _gpsTracking;
  double get homeLat => _homeLat;
  double get homeLon => _homeLon;
  bool get homeIsSet => _homeIsSet;
  bool get hasLiveFix => _userLat != null;

  /// Current position if known, otherwise home.
  double get userLat => _userLat ?? _homeLat;
  double get userLon => _userLon ?? _homeLon;

  void _initListeners() {
    _haStateSub = haClient.stateStream.listen((state) {
      _haState = state;
      notifyListeners();
      if (state == HaConnectionState.connected) {
        _serialise(() async {
          await mutationEngine.flushQueue();
          await refreshData();
        });
      }
    });

    _haItemsSub = haClient.itemsStream.listen((remoteItems) {
      _serialise(() async {
        await mutationEngine.reconcileSnapshot(remoteItems);
        await refreshData();
      });
    });

    _geofenceSub = geofenceEngine.stateStream.listen((state) {
      _geofenceState = state;
      _activeStore = geofenceEngine.activeStore;
      notifyListeners();
    });

    _dwellSub = geofenceEngine.dwellProgressStream.listen((seconds) {
      _dwellSeconds = seconds;
      notifyListeners();
    });
  }

  /// Initialize state from local database
  Future<void> initialize() async {
    final lat = double.tryParse(await database.getSetting(SettingKeys.homeLat) ?? '');
    final lon = double.tryParse(await database.getSetting(SettingKeys.homeLon) ?? '');
    if (lat != null && lon != null) {
      _homeLat = lat;
      _homeLon = lon;
      _homeIsSet = true;
    }
    matrixService.osrmEndpoint = await database.getSetting(SettingKeys.osrmEndpoint);

    var nodeId = await database.getSetting(SettingKeys.nodeId);
    if (nodeId == null) {
      nodeId = HybridLogicalClock().nodeId;
      await database.setSetting(SettingKeys.nodeId, nodeId);
    }
    mutationEngine.hlc.nodeId = nodeId;

    await haClient.configure(
      baseUrl: await database.getSetting(SettingKeys.haUrl) ?? '',
      accessToken: await database.getSetting(SettingKeys.haToken) ?? '',
      entityId: await database.getSetting(SettingKeys.haEntityId) ?? haClient.entityId,
    );
    await geofenceEngine.restoreActiveVisit();
    _activeStore = geofenceEngine.activeStore;
    _geofenceState = geofenceEngine.currentState;

    await refreshData();
    _initialized = true;
    notifyListeners();

    if (haClient.isConfigured) await haClient.connect();
  }

  void _serialise(Future<void> Function() task) {
    _pendingSync = _pendingSync.then((_) async {
      if (_disposed) return;
      try {
        await task();
      } catch (e) {
        if (!_disposed) debugPrint('Home Assistant sync error: $e');
      }
    });
  }

  /// Completes once queued Home Assistant sync work has finished.
  Future<void> get syncIdle => _pendingSync;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> refreshData() async {
    if (_disposed) return;
    _items = await database.getItems();
    _stores = await database.getStores();
    _preferences = await database.getPreferences();
    _activeRoute = await database.getActiveRoute();
    _failedSyncCount = await database.countFailedMutations();
    notifyListeners();
  }

  // --- Settings ---

  Future<void> saveHaSettings({
    required String url,
    required String token,
    required String entityId,
  }) async {
    await database.setSetting(SettingKeys.haUrl, url.trim());
    // Blank token field means "keep the saved token".
    if (token.trim().isNotEmpty) await database.setSetting(SettingKeys.haToken, token.trim());
    await database.setSetting(SettingKeys.haEntityId, entityId.trim());
    await haClient.configure(
      baseUrl: url,
      accessToken: await database.getSetting(SettingKeys.haToken) ?? '',
      entityId: entityId,
    );
    await haClient.connect();
    notifyListeners();
  }

  Future<void> disconnectHa() async {
    haClient.disconnect();
    notifyListeners();
  }

  Future<void> forgetHa() async {
    await database.setSetting(SettingKeys.haUrl, null);
    await database.setSetting(SettingKeys.haToken, null);
    await haClient.configure(baseUrl: '', accessToken: '', entityId: haClient.entityId);
    notifyListeners();
  }

  Future<void> setHomeLocation(double lat, double lon) async {
    _homeLat = lat;
    _homeLon = lon;
    _homeIsSet = true;
    await database.setSetting(SettingKeys.homeLat, lat.toString());
    await database.setSetting(SettingKeys.homeLon, lon.toString());
    notifyListeners();
  }

  Future<void> setRoutingServer(String? url) async {
    final value = (url == null || url.trim().isEmpty) ? null : url.trim();
    matrixService.osrmEndpoint = value;
    await database.setSetting(SettingKeys.osrmEndpoint, value);
    notifyListeners();
  }

  String? get routingServer => matrixService.osrmEndpoint;

  // --- Human-in-the-Loop List Operations ---

  /// Manual drag & drop inside [visible] (the possibly filtered list on
  /// screen). Hidden items keep their slots; the visible ones are permuted
  /// among the slots they occupy, so filtering never scrambles the list.
  Future<void> reorderVisible(List<TodoItem> visible, int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= visible.length) return;
    final reordered = List<TodoItem>.from(visible);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex.clamp(0, reordered.length), moved);

    final visibleIds = visible.map((i) => i.id).toSet();
    final queue = reordered.iterator;
    _items = [
      for (final item in _items)
        if (visibleIds.contains(item.id)) (queue..moveNext()).current else item,
    ];
    notifyListeners();
    await database.updateItemOrder(_items);
    _items = await database.getItems();
    notifyListeners();
  }

  /// Toggle Pin / Hard Lock sequence constraint
  Future<void> togglePin(String itemId) async {
    final item = await database.getItem(itemId);
    if (item == null) return;

    await database.updateItem(item.copyWith(
      isPinned: !item.isPinned,
      updatedAt: DateTime.now(),
    ));
    await refreshData();
  }

  /// Toggle item completion: records in-store check-off if inside store
  Future<void> toggleItemCompleted(String itemId) async {
    final item = await database.getItem(itemId);
    if (item == null) return;

    final newStatus = item.isCompleted ? 'needs_action' : 'completed';
    await database.updateItem(item.copyWith(
      status: newStatus,
      updatedAt: DateTime.now(),
    ));

    // Inside a store (including the exit grace period), check-offs train the
    // walk-order graph and the item -> store preference.
    final visit = geofenceEngine.currentVisit;
    final store = geofenceEngine.activeStore;
    if (visit != null) {
      if (newStatus == 'completed') {
        await layoutLearningEngine.recordCheckoff(
          visitId: visit.id,
          itemId: item.id,
          itemCategory: item.category,
        );
        if (store != null) await database.incrementPreference(item.category, store.id);
      } else {
        await layoutLearningEngine.retractCheckoff(visitId: visit.id, itemId: item.id);
      }
    }

    await mutationEngine.queueMutation(itemId: item.id, field: SyncField.status, value: newStatus);
    await refreshData();
  }

  /// Add new errand / shopping item
  Future<void> addItem({
    required String summary,
    String? description,
    String category = 'generic',
    bool isPerishable = false,
  }) async {
    final maxOrder = _items.isEmpty
        ? -1
        : _items.map((i) => i.humanOrderIndex).reduce((a, b) => a > b ? a : b);
    final newItem = TodoItem(
      id: const Uuid().v4(),
      haEntityId: haClient.entityId,
      summary: summary,
      description: description,
      category: category,
      isPerishable: isPerishable,
      status: 'needs_action',
      humanOrderIndex: maxOrder + 1,
      isPinned: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await database.insertItem(newItem);
    await mutationEngine.queueMutation(itemId: newItem.id, field: SyncField.create, value: null);
    await refreshData();
  }

  /// Edit an item's text and local-only metadata.
  Future<void> editItem(
    String itemId, {
    required String summary,
    String? description,
    required String category,
    required bool isPerishable,
  }) async {
    final item = await database.getItem(itemId);
    if (item == null) return;
    final newDescription = (description == null || description.isEmpty) ? null : description;

    await database.updateItem(TodoItem(
      id: item.id,
      haEntityId: item.haEntityId,
      haUid: item.haUid,
      summary: summary,
      description: newDescription,
      category: category,
      isPerishable: isPerishable,
      status: item.status,
      humanOrderIndex: item.humanOrderIndex,
      optimizedOrderIndex: item.optimizedOrderIndex,
      isPinned: item.isPinned,
      createdAt: item.createdAt,
      updatedAt: DateTime.now(),
    ));
    if (summary != item.summary) {
      await mutationEngine.queueMutation(itemId: itemId, field: SyncField.summary, value: summary);
    }
    if (newDescription != item.description) {
      await mutationEngine.queueMutation(
          itemId: itemId, field: SyncField.description, value: newDescription);
    }
    await refreshData();
  }

  /// Delete an item
  Future<void> deleteItem(String itemId) async {
    final item = await database.getItem(itemId);
    if (item == null) return;
    await database.deleteItem(itemId);
    await mutationEngine.queueMutation(itemId: itemId, field: SyncField.deleted, value: item.haUid);
    await refreshData();
  }

  // --- Stores ---

  Future<void> saveStore(Store store) async {
    await database.insertStore(store);
    await refreshData();
  }

  Future<void> deleteStore(String storeId) async {
    if (geofenceEngine.activeStore?.id == storeId) await geofenceEngine.forceExitStore();
    await database.deleteStore(storeId);
    await refreshData();
  }

  // --- Hybrid VRPTW Solver Trigger ("I'm Going Out") ---

  Future<ActiveRoute> solveErrandRoute({DateTime? departure}) async {
    _isSolving = true;
    notifyListeners();

    try {
      final req = VrpSolverRequest(
        originCoordinates: [userLat, userLon],
        departureTime: departure ?? DateTime.now(),
        items: _items,
        candidateStores: _stores,
        preferences: _preferences,
      );

      final route = await vrpSolver.solveRoute(req);
      await database.saveActiveRoute(route);

      // Update non-destructive visual overlay indices on items
      await database.updateOptimizedIndices({
        for (final stop in route.stops)
          for (final item in stop.itemsToPick) item.id: stop.stopSequence,
      });

      await refreshData();
      return route;
    } finally {
      _isSolving = false;
      notifyListeners();
    }
  }

  // --- In-Store Walk-Order Query ---

  /// Pending items to pick at [store], in learned aisle order. Items the
  /// active route assigned to this store come first; with no route, every
  /// pending item the store stocks is shown.
  Future<List<TodoItem>> getInStoreWalkOrderItems(Store store) async {
    final stop = _activeRoute?.stops.where((s) => s.storeId == store.id).firstOrNull;
    final routedIds = stop?.itemsToPick.map((i) => i.id).toSet() ?? const <String>{};

    final storeItems = _items.where((i) {
      if (i.isCompleted) return false;
      if (routedIds.isNotEmpty) return routedIds.contains(i.id);
      return store.supportedCategories.contains(i.category) ||
          store.supportedCategories.contains('generic');
    }).toList();

    if (storeItems.length <= 1) return storeItems;

    // Categories in the user's list order: the tie-breaker for unlearned aisles.
    final categories = <String>[];
    for (final i in storeItems) {
      if (!categories.contains(i.category)) categories.add(i.category);
    }
    final walkOrder = await layoutLearningEngine.getOptimalWalkOrder(
      storeId: store.id,
      categoriesToPick: categories,
    );

    // Stable sort keeps the user's order within a category.
    final rank = {for (var r = 0; r < walkOrder.length; r++) walkOrder[r]: r};
    final indexed = storeItems.asMap().entries.toList()
      ..sort((a, b) {
        final byAisle = rank[a.value.category]!.compareTo(rank[b.value.category]!);
        return byAisle != 0 ? byAisle : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
  }

  // --- GPS Location Updates & Geofencing ---

  Future<LocationStartResult> startGpsTracking() async {
    final result = await locationService.start((fix) {
      updateUserLocation(fix.latitude, fix.longitude, accuracy: fix.accuracy, at: fix.timestamp);
    });
    _gpsTracking = result == LocationStartResult.started;
    notifyListeners();
    return result;
  }

  Future<void> stopGpsTracking() async {
    await locationService.stop();
    _gpsTracking = false;
    notifyListeners();
  }

  Future<void> updateUserLocation(
    double lat,
    double lon, {
    double accuracy = 5.0,
    DateTime? at,
  }) async {
    _userLat = lat;
    _userLon = lon;
    _userFixAt = at ?? DateTime.now();
    notifyListeners();

    await geofenceEngine.onLocationUpdate(GeoPoint(
      latitude: lat,
      longitude: lon,
      accuracy: accuracy,
      timestamp: _userFixAt!,
    ));
  }

  // --- Simulation Triggers for User Demos ---

  Future<void> simulateDriveToStore(Store store) async {
    await updateUserLocation(store.latitude, store.longitude, accuracy: 5.0);
  }

  Future<void> simulateStoreEntry(Store store) async {
    await geofenceEngine.forceEnterStore(store);
    _geofenceState = geofenceEngine.currentState;
    _activeStore = geofenceEngine.activeStore;
    notifyListeners();
  }

  Future<void> simulateStoreExit() async {
    await geofenceEngine.forceExitStore();
    _geofenceState = geofenceEngine.currentState;
    _activeStore = null;
    notifyListeners();
  }

  /// Pretend someone added [summary] in Home Assistant (works offline).
  Future<void> simulateHaItemAdd(String summary) async {
    final remote = HaTodoItem(uid: 'sim_${DateTime.now().millisecondsSinceEpoch}', summary: summary);
    final maxOrder = _items.isEmpty
        ? -1
        : _items.map((i) => i.humanOrderIndex).reduce((a, b) => a > b ? a : b);
    await database.insertItem(mutationEngine.newItemFromRemote(remote, maxOrder + 1));
    await refreshData();
  }

  Future<void> simulateResetData() async {
    await geofenceEngine.forceExitStore();
    await database.resetToSampleData();
    await refreshData();
  }

  @override
  void dispose() {
    _disposed = true;
    _haStateSub?.cancel();
    _haItemsSub?.cancel();
    _geofenceSub?.cancel();
    _dwellSub?.cancel();
    locationService.stop();
    haClient.dispose();
    geofenceEngine.dispose();
    super.dispose();
  }
}
