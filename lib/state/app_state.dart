import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../core/constants.dart';
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
import '../services/vrp_solver.dart';

/// Central Reactive State Provider for op-list
class AppState extends ChangeNotifier {
  final AppDatabase database;
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
  HaConnectionState _haState = HaConnectionState.disconnected;
  bool _isSolving = false;

  // Default starting position (e.g. Bangalore center / user home)
  double _userLat = 12.9716;
  double _userLon = 77.5946;

  StreamSubscription? _haStateSub;
  StreamSubscription? _haEventSub;
  StreamSubscription? _geofenceSub;
  StreamSubscription? _dwellSub;

  AppState({required this.database}) {
    haClient = HomeAssistantWsClient(mockMode: true);
    mutationEngine = MutationEngine(database: database, wsClient: haClient);
    matrixService = DistanceMatrixService(database: database);
    vrpSolver = VrpSolver(matrixService: matrixService);
    layoutLearningEngine = LayoutLearningEngine(database: database);
    geofenceEngine = GeofenceEngine(
      database: database,
      layoutLearningEngine: layoutLearningEngine,
    );

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
  bool get isSolving => _isSolving;
  double get userLat => _userLat;
  double get userLon => _userLon;

  void _initListeners() {
    _haStateSub = haClient.stateStream.listen((state) {
      _haState = state;
      notifyListeners();
    });

    _haEventSub = haClient.eventStream.listen((event) async {
      await mutationEngine.reconcileRemoteItem(event['item'] as Map<String, dynamic>);
      await refreshData();
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
    await haClient.connect();
    await refreshData();
  }

  Future<void> refreshData() async {
    _items = await database.getItems();
    _stores = await database.getStores();
    _preferences = await database.getPreferences();
    _activeRoute = await database.getActiveRoute();
    notifyListeners();
  }

  // --- Human-in-the-Loop List Operations ---

  /// Manual Drag & Drop reordering: preserves human_order_index
  Future<void> reorderItem(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _items.removeAt(oldIndex);
    _items.insert(newIndex, item);

    notifyListeners();
    await database.updateItemOrder(_items);
  }

  /// Toggle Pin / Hard Lock sequence constraint
  Future<void> togglePin(String itemId) async {
    final item = await database.getItem(itemId);
    if (item == null) return;

    final updated = item.copyWith(
      isPinned: !item.isPinned,
      updatedAt: DateTime.now(),
    );

    await database.updateItem(updated);
    await refreshData();
  }

  /// Toggle item completion: records in-store check-off if inside store
  Future<void> toggleItemCompleted(String itemId) async {
    final item = await database.getItem(itemId);
    if (item == null) return;

    final newStatus = item.isCompleted ? 'needs_action' : 'completed';
    final updated = item.copyWith(
      status: newStatus,
      updatedAt: DateTime.now(),
    );

    await database.updateItem(updated);

    // If inside a store during completion, record check-off event for layout learning
    if (newStatus == 'completed' &&
        _geofenceState == GeofenceState.insideStore &&
        geofenceEngine.currentVisit != null) {
      await layoutLearningEngine.recordCheckoff(
        visitId: geofenceEngine.currentVisit!.id,
        itemId: item.id,
        itemCategory: item.category,
      );

      // Increment store category preference counter
      if (_activeStore != null) {
        await database.incrementPreference(item.category, _activeStore!.id);
      }
    }

    // Queue mutation for Home Assistant sync
    await mutationEngine.queueMutation(
      itemId: item.id,
      field: 'status',
      value: newStatus,
    );

    await refreshData();
  }

  /// Add new errand / shopping item
  Future<void> addItem({
    required String summary,
    String? description,
    String category = 'generic',
    bool isPerishable = false,
  }) async {
    final newItem = TodoItem(
      id: const Uuid().v4(),
      haEntityId: haClient.entityId,
      summary: summary,
      description: description,
      category: category,
      isPerishable: isPerishable,
      status: 'needs_action',
      humanOrderIndex: _items.length,
      isPinned: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await database.insertItem(newItem);
    await haClient.sendTodoAdd(summary: summary, description: description);
    await refreshData();
  }

  /// Delete an item
  Future<void> deleteItem(String itemId) async {
    await database.deleteItem(itemId);
    await mutationEngine.queueMutation(
      itemId: itemId,
      field: 'deleted',
      value: null,
    );
    await refreshData();
  }

  // --- Hybrid VRPTW Solver Trigger ("I'm Going Out") ---

  Future<ActiveRoute> solveErrandRoute() async {
    _isSolving = true;
    notifyListeners();

    try {
      final req = VrpSolverRequest(
        originCoordinates: [_userLat, _userLon],
        departureTime: DateTime.now(),
        items: _items,
        candidateStores: _stores,
        preferences: _preferences,
      );

      final route = await vrpSolver.solveRoute(req);
      await database.saveActiveRoute(route);

      // Update non-destructive visual overlay indices on items
      final itemToOptimizedIndex = <String, int>{};
      for (final stop in route.stops) {
        for (var i = 0; i < stop.itemsToPick.length; i++) {
          itemToOptimizedIndex[stop.itemsToPick[i].id] = stop.stopSequence;
        }
      }
      await database.updateOptimizedIndices(itemToOptimizedIndex);

      _activeRoute = route;
      await refreshData();
      return route;
    } finally {
      _isSolving = false;
      notifyListeners();
    }
  }

  // --- In-Store Walk-Order Query ---

  Future<List<TodoItem>> getInStoreWalkOrderItems(Store store) async {
    final storeItems = _items.where((i) {
      return !i.isCompleted &&
          (store.supportedCategories.contains(i.category) ||
              store.supportedCategories.contains('generic'));
    }).toList();

    if (storeItems.length <= 1) return storeItems;

    final categories = storeItems.map((i) => i.category).toSet().toList();
    final walkOrder = await layoutLearningEngine.getOptimalWalkOrder(
      storeId: store.id,
      categoriesToPick: categories,
    );

    // Sort items by learned walk category rank
    storeItems.sort((a, b) {
      final rankA = walkOrder.indexOf(a.category);
      final rankB = walkOrder.indexOf(b.category);
      final validA = rankA == -1 ? 999 : rankA;
      final validB = rankB == -1 ? 999 : rankB;
      return validA.compareTo(validB);
    });

    return storeItems;
  }

  // --- GPS Location Updates & Geofencing ---

  Future<void> updateUserLocation(double lat, double lon, {double accuracy = 5.0}) async {
    _userLat = lat;
    _userLon = lon;
    notifyListeners();

    final point = GeoPoint(
      latitude: lat,
      longitude: lon,
      accuracy: accuracy,
      timestamp: DateTime.now(),
    );

    await geofenceEngine.onLocationUpdate(point);
  }

  // --- Simulation Triggers for User Demos ---

  Future<void> simulateDriveToStore(Store store) async {
    await updateUserLocation(store.latitude, store.longitude, accuracy: 5.0);
  }

  Future<void> simulateStoreEntry(Store store) async {
    await geofenceEngine.forceEnterStore(store);
    _geofenceState = GeofenceState.insideStore;
    _activeStore = store;
    notifyListeners();
  }

  Future<void> simulateStoreExit() async {
    await geofenceEngine.forceExitStore();
    _geofenceState = GeofenceState.outsideStore;
    _activeStore = null;
    notifyListeners();
  }

  void simulateHaItemAdd(String summary, {String category = 'groceries', bool isPerishable = false}) {
    haClient.simulateIncomingRemoteItem(
      summary: summary,
      category: category,
      isPerishable: isPerishable,
    );
  }

  Future<void> simulateResetData() async {
    await database.close();
    await database.init(inMemory: false);
    await refreshData();
  }

  @override
  void dispose() {
    _haStateSub?.cancel();
    _haEventSub?.cancel();
    _geofenceSub?.cancel();
    _dwellSub?.cancel();
    haClient.dispose();
    geofenceEngine.dispose();
    super.dispose();
  }
}
