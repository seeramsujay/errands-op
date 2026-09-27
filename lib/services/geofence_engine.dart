import 'dart:async';
import 'package:uuid/uuid.dart';
import '../core/constants.dart';
import '../core/haversine.dart';
import '../core/kalman_filter.dart';
import '../data/database/app_database.dart';
import '../data/models/store.dart';
import '../data/models/visit.dart';
import 'layout_learning_engine.dart';

enum GeofenceState {
  outsideStore,
  pendingEntry,
  insideStore,
  pendingExit,
}

/// Dual-Ring Hysteresis Geofencing State Machine
class GeofenceEngine {
  final AppDatabase database;
  final LayoutLearningEngine? layoutLearningEngine;
  final KalmanGpsFilter kalmanFilter;

  GeofenceState _currentState = GeofenceState.outsideStore;
  Store? _activeStore;
  StoreVisit? _currentVisit;

  DateTime? _dwellStartTime;
  DateTime? _exitGraceStartTime;
  Timer? _dwellTimer;
  Timer? _exitGraceTimer;

  final _stateController = StreamController<GeofenceState>.broadcast();
  final _dwellSecondsController = StreamController<int>.broadcast();

  GeofenceEngine({
    required this.database,
    this.layoutLearningEngine,
    KalmanGpsFilter? filter,
  }) : kalmanFilter = filter ?? KalmanGpsFilter();

  GeofenceState get currentState => _currentState;
  Store? get activeStore => _activeStore;
  StoreVisit? get currentVisit => _currentVisit;
  Stream<GeofenceState> get stateStream => _stateController.stream;
  Stream<int> get dwellProgressStream => _dwellSecondsController.stream;

  void _setState(GeofenceState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  /// Process an incoming raw GPS fix
  Future<void> onLocationUpdate(GeoPoint rawPoint) async {
    final smoothed = kalmanFilter.processFix(rawPoint);
    if (smoothed == null) {
      // Discarded by Kalman filter due to poor accuracy (> 30m)
      return;
    }

    final stores = await database.getStores();
    if (stores.isEmpty) return;

    // Evaluate proximity against nearest candidate store
    Store? nearestStore;
    var minDistance = double.infinity;

    for (final store in stores) {
      final dist = HaversineUtils.directDistance(
        smoothed.latitude,
        smoothed.longitude,
        store.latitude,
        store.longitude,
      );
      if (dist < minDistance) {
        minDistance = dist;
        nearestStore = store;
      }
    }

    if (nearestStore == null) return;

    final rIn = AppConstants.innerArrivalRadiusMeters;
    final rOut = AppConstants.outerExitRadiusMeters;

    switch (_currentState) {
      case GeofenceState.outsideStore:
        if (minDistance <= rIn) {
          // Within inner arrival radius (40m) -> Start 120s dwell
          _activeStore = nearestStore;
          _startPendingEntry();
        }
        break;

      case GeofenceState.pendingEntry:
        if (minDistance > rIn) {
          // Left inner radius before dwell completed -> abort
          _abortPendingEntry();
        }
        break;

      case GeofenceState.insideStore:
        if (minDistance > rOut) {
          // Exceeded outer boundary (80m) -> Start 180s exit grace
          _startPendingExit();
        }
        break;

      case GeofenceState.pendingExit:
        if (minDistance <= rOut) {
          // Returned back inside outer boundary -> cancel exit
          _abortPendingExit();
        }
        break;
    }
  }

  void _startPendingEntry() {
    _setState(GeofenceState.pendingEntry);
    _dwellStartTime = DateTime.now();

    _dwellTimer?.cancel();
    _dwellTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_dwellStartTime == null) return;
      final elapsedSec = DateTime.now().difference(_dwellStartTime!).inSeconds;
      _dwellSecondsController.add(elapsedSec);

      if (elapsedSec >= AppConstants.entryDwellTimeSeconds) {
        timer.cancel();
        _confirmStoreEntry();
      }
    });
  }

  void _abortPendingEntry() {
    _dwellTimer?.cancel();
    _dwellStartTime = null;
    _dwellSecondsController.add(0);
    _setState(GeofenceState.outsideStore);
  }

  Future<void> _confirmStoreEntry() async {
    if (_activeStore == null) return;
    _setState(GeofenceState.insideStore);

    final visit = StoreVisit(
      id: const Uuid().v4(),
      storeId: _activeStore!.id,
      entryTimestamp: DateTime.now(),
    );
    _currentVisit = visit;
    await database.insertVisit(visit);
  }

  void _startPendingExit() {
    _setState(GeofenceState.pendingExit);
    _exitGraceStartTime = DateTime.now();

    _exitGraceTimer?.cancel();
    _exitGraceTimer = Timer(Duration(seconds: AppConstants.exitGracePeriodSeconds), () {
      _confirmStoreExit();
    });
  }

  void _abortPendingExit() {
    _exitGraceTimer?.cancel();
    _exitGraceStartTime = null;
    _setState(GeofenceState.insideStore);
  }

  Future<void> _confirmStoreExit() async {
    _exitGraceTimer?.cancel();
    _exitGraceStartTime = null;

    if (_currentVisit != null) {
      final completedVisit = _currentVisit!.copyWith(
        exitTimestamp: DateTime.now(),
      );
      await database.updateVisit(completedVisit);

      // Trigger walk-order graph layout learning on store exit
      if (layoutLearningEngine != null && _activeStore != null) {
        await layoutLearningEngine!.processCompletedVisit(
          storeId: _activeStore!.id,
          visitId: completedVisit.id,
        );
      }
    }

    _activeStore = null;
    _currentVisit = null;
    _setState(GeofenceState.outsideStore);
  }

  /// Manually force enter a store (for simulation / instant test mode)
  Future<void> forceEnterStore(Store store) async {
    _activeStore = store;
    _confirmStoreEntry();
  }

  /// Manually force exit (for simulation / instant test mode)
  Future<void> forceExitStore() async {
    await _confirmStoreExit();
  }

  void dispose() {
    _dwellTimer?.cancel();
    _exitGraceTimer?.cancel();
    _stateController.close();
    _dwellSecondsController.close();
  }
}
