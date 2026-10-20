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
///
/// Inner (arrival) ring = the store's own geofence radius; outer (exit) ring
/// = inner x [AppConstants.outerToInnerRadiusRatio]. Entry needs a continuous
/// dwell inside the inner ring; exit needs a continuous stay outside the
/// outer ring. Timing uses fix timestamps plus [tick], so it is driven by a
/// 1 Hz timer in the app and by explicit clock values in tests.
class GeofenceEngine {
  final AppDatabase database;
  final LayoutLearningEngine? layoutLearningEngine;
  final KalmanGpsFilter kalmanFilter;
  final DateTime Function() clock;
  final bool autoTick;

  GeofenceState _currentState = GeofenceState.outsideStore;
  Store? _activeStore;
  StoreVisit? _currentVisit;

  DateTime? _pendingSince;
  Timer? _ticker;

  final _stateController = StreamController<GeofenceState>.broadcast();
  final _dwellSecondsController = StreamController<int>.broadcast();

  GeofenceEngine({
    required this.database,
    this.layoutLearningEngine,
    KalmanGpsFilter? filter,
    DateTime Function()? clock,
    this.autoTick = true,
  })  : kalmanFilter = filter ?? KalmanGpsFilter(),
        clock = clock ?? DateTime.now;

  GeofenceState get currentState => _currentState;
  Store? get activeStore => _activeStore;
  StoreVisit? get currentVisit => _currentVisit;
  Stream<GeofenceState> get stateStream => _stateController.stream;
  Stream<int> get dwellProgressStream => _dwellSecondsController.stream;

  static double innerRadius(Store s) => s.geofenceRadiusMeters;
  static double outerRadius(Store s) => s.geofenceRadiusMeters * AppConstants.outerToInnerRadiusRatio;

  void _setState(GeofenceState newState) {
    _currentState = newState;
    if (!_stateController.isClosed) _stateController.add(newState);
  }

  void _emitDwell(int seconds) {
    if (!_dwellSecondsController.isClosed) _dwellSecondsController.add(seconds);
  }

  /// Resume (or close) a visit left open when the app was last stopped.
  Future<void> restoreActiveVisit({Duration maxAge = const Duration(hours: 3)}) async {
    final visit = await database.getActiveVisit();
    if (visit == null) return;
    final store = await database.getStore(visit.storeId);
    final now = clock();
    if (store == null || now.difference(visit.entryTimestamp) > maxAge) {
      await _finishVisit(visit, store?.id, exitAt: visit.entryTimestamp.add(const Duration(minutes: 30)));
      return;
    }
    _activeStore = store;
    _currentVisit = visit;
    _setState(GeofenceState.insideStore);
  }

  /// Process an incoming raw GPS fix
  Future<void> onLocationUpdate(GeoPoint rawPoint) async {
    final smoothed = kalmanFilter.processFix(rawPoint);
    if (smoothed == null) {
      // Discarded by Kalman filter due to poor accuracy (> 30m)
      return;
    }
    final t = rawPoint.timestamp;

    double distanceTo(Store s) => HaversineUtils.directDistance(
          smoothed.latitude,
          smoothed.longitude,
          s.latitude,
          s.longitude,
        );

    switch (_currentState) {
      case GeofenceState.outsideStore:
        await _maybeStartEntry(distanceTo, t);
        break;

      case GeofenceState.pendingEntry:
        if (distanceTo(_activeStore!) > innerRadius(_activeStore!)) {
          // Left the inner ring before the dwell completed; maybe it's a neighbour.
          _abortPendingEntry();
          await _maybeStartEntry(distanceTo, t);
        } else {
          await tick(t);
        }
        break;

      case GeofenceState.insideStore:
        if (distanceTo(_activeStore!) > outerRadius(_activeStore!)) {
          _startPending(GeofenceState.pendingExit, t);
        }
        break;

      case GeofenceState.pendingExit:
        if (distanceTo(_activeStore!) <= outerRadius(_activeStore!)) {
          // Back inside the outer ring: GPS dead zone, not an exit.
          _stopPending();
          _setState(GeofenceState.insideStore);
        } else {
          await tick(t);
        }
        break;
    }
  }

  Future<void> _maybeStartEntry(double Function(Store) distanceTo, DateTime t) async {
    final stores = await database.getStores();
    Store? nearest;
    var nearestDistance = double.infinity;
    for (final store in stores) {
      final d = distanceTo(store);
      if (d <= innerRadius(store) && d < nearestDistance) {
        nearest = store;
        nearestDistance = d;
      }
    }
    if (nearest == null) return;
    _activeStore = nearest;
    _startPending(GeofenceState.pendingEntry, t);
  }

  /// Advance dwell / grace timers to [now].
  Future<void> tick(DateTime now) async {
    final since = _pendingSince;
    if (since == null) return;
    final elapsed = now.difference(since).inSeconds;

    if (_currentState == GeofenceState.pendingEntry) {
      _emitDwell(elapsed.clamp(0, AppConstants.entryDwellTimeSeconds));
      if (elapsed >= AppConstants.entryDwellTimeSeconds) {
        _stopPending();
        await _confirmStoreEntry(enteredAt: since);
      }
    } else if (_currentState == GeofenceState.pendingExit) {
      if (elapsed >= AppConstants.exitGracePeriodSeconds) {
        _stopPending();
        await _confirmStoreExit(exitedAt: since);
      }
    }
  }

  void _startPending(GeofenceState state, DateTime since) {
    _stopPending();
    _pendingSince = since;
    _setState(state);
    if (autoTick) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick(clock()));
    }
  }

  void _stopPending() {
    _ticker?.cancel();
    _ticker = null;
    _pendingSince = null;
  }

  void _abortPendingEntry() {
    _stopPending();
    _activeStore = null;
    _emitDwell(0);
    _setState(GeofenceState.outsideStore);
  }

  Future<void> _confirmStoreEntry({required DateTime enteredAt}) async {
    final store = _activeStore;
    if (store == null) return;

    final visit = StoreVisit(
      id: const Uuid().v4(),
      storeId: store.id,
      entryTimestamp: enteredAt,
    );
    _currentVisit = visit;
    await database.insertVisit(visit);
    _emitDwell(0);
    _setState(GeofenceState.insideStore);
  }

  Future<void> _confirmStoreExit({required DateTime exitedAt}) async {
    final visit = _currentVisit;
    final storeId = _activeStore?.id;
    _activeStore = null;
    _currentVisit = null;
    if (visit != null) {
      await _finishVisit(visit, storeId, exitAt: exitedAt);
    }
    _setState(GeofenceState.outsideStore);
  }

  Future<void> _finishVisit(StoreVisit visit, String? storeId, {required DateTime exitAt}) async {
    await database.updateVisit(visit.copyWith(exitTimestamp: exitAt));
    // Trigger walk-order graph layout learning on store exit
    if (layoutLearningEngine != null && storeId != null) {
      await layoutLearningEngine!.processCompletedVisit(storeId: storeId, visitId: visit.id);
    }
  }

  /// Manually force enter a store (for simulation / instant test mode)
  Future<void> forceEnterStore(Store store) async {
    if (_currentVisit != null) {
      if (_activeStore?.id == store.id) return;
      await forceExitStore();
    }
    _stopPending();
    _activeStore = store;
    await _confirmStoreEntry(enteredAt: clock());
  }

  /// Manually force exit (for simulation / instant test mode)
  Future<void> forceExitStore() async {
    _stopPending();
    if (_currentVisit == null) {
      _activeStore = null;
      _emitDwell(0);
      _setState(GeofenceState.outsideStore);
      return;
    }
    await _confirmStoreExit(exitedAt: clock());
  }

  void dispose() {
    _stopPending();
    _stateController.close();
    _dwellSecondsController.close();
  }
}
