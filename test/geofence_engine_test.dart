import 'package:flutter_test/flutter_test.dart';
import 'package:op_list/core/kalman_filter.dart';
import 'package:op_list/data/database/app_database.dart';
import 'package:op_list/data/models/store.dart';
import 'package:op_list/data/models/visit.dart';
import 'package:op_list/services/geofence_engine.dart';
import 'package:op_list/services/layout_learning_engine.dart';

// Far from the seeded sample stores. ~111 m per 0.001 degree of latitude.
const _target = Store(
  id: 'target_store',
  name: 'Target Store',
  latitude: 13.5000,
  longitude: 78.5000,
  geofenceRadiusMeters: 40,
);
const _neighbour = Store(
  id: 'neighbour_store',
  name: 'Neighbour',
  latitude: 13.5006, // ~67 m north
  longitude: 78.5000,
  geofenceRadiusMeters: 40,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late GeofenceEngine engine;
  late DateTime now;
  final t0 = DateTime(2026, 9, 28, 10, 0, 0);

  GeoPoint fix(double dLatMeters, int atSec, {double accuracy = 5}) => GeoPoint(
    latitude: _target.latitude + dLatMeters / 111000.0,
    longitude: _target.longitude,
    accuracy: accuracy,
    timestamp: t0.add(Duration(seconds: atSec)),
  );

  Future<void> at(int sec, double dLatMeters) async {
    now = t0.add(Duration(seconds: sec));
    // Fresh filter per fix: these tests exercise the state machine, not smoothing.
    engine.kalmanFilter.reset();
    await engine.onLocationUpdate(fix(dLatMeters, sec));
  }

  setUp(() async {
    db = AppDatabase.instance;
    await db.init(inMemory: true);
    await db.insertStore(_target);
    now = t0;
    engine = GeofenceEngine(
      database: db,
      layoutLearningEngine: LayoutLearningEngine(database: db),
      clock: () => now,
      autoTick: false,
    );
  });

  tearDown(() async {
    engine.dispose();
    await db.close();
  });

  test('Kalman GPS filter discards fixes with horizontal accuracy > 30m', () {
    final filter = KalmanGpsFilter();
    expect(filter.processFix(fix(0, 0, accuracy: 45)), isNull);
    final good = filter.processFix(fix(0, 0, accuracy: 10));
    expect(good, isNotNull);
    expect(good!.latitude, _target.latitude);
  });

  test(
    'Geofence transitions to pendingEntry when inside inner 40m radius',
    () async {
      await at(0, 5);
      expect(engine.currentState, GeofenceState.pendingEntry);
      expect(engine.activeStore?.id, 'target_store');
    },
  );

  test(
    '120 s dwell confirms entry and opens a visit stamped at arrival',
    () async {
      await at(0, 5);
      await at(60, 10);
      expect(engine.currentState, GeofenceState.pendingEntry);
      await at(121, 8);
      expect(engine.currentState, GeofenceState.insideStore);

      final visit = await db.getActiveVisit();
      expect(visit?.storeId, 'target_store');
      expect(visit?.entryTimestamp, t0);
    },
  );

  test('dwell completes on the timer even without new fixes', () async {
    await at(0, 5);
    now = t0.add(const Duration(seconds: 125));
    await engine.tick(now);
    expect(engine.currentState, GeofenceState.insideStore);
  });

  test(
    'leaving the inner ring before the dwell aborts entry (drive-by)',
    () async {
      await at(0, 5);
      await at(30, 200);
      expect(engine.currentState, GeofenceState.outsideStore);
      await at(200, 200);
      expect(await db.getActiveVisit(), isNull);
    },
  );

  test(
    'brief dead-zone excursion past the outer ring does not end the visit',
    () async {
      await engine.forceEnterStore(_target);
      await at(10, 100); // beyond 80 m outer ring
      expect(engine.currentState, GeofenceState.pendingExit);
      await at(100, 50); // back within the outer ring
      expect(engine.currentState, GeofenceState.insideStore);
      await at(400, 30);
      expect(engine.currentState, GeofenceState.insideStore);
    },
  );

  test(
    '180 s outside the outer ring closes the visit and learns the layout',
    () async {
      await engine.forceEnterStore(_target);
      final visit = engine.currentVisit!;
      await engine.layoutLearningEngine!.recordCheckoff(
        visitId: visit.id,
        itemId: 'i1',
        itemCategory: 'produce',
        at: t0.add(const Duration(seconds: 30)),
      );
      await engine.layoutLearningEngine!.recordCheckoff(
        visitId: visit.id,
        itemId: 'i2',
        itemCategory: 'dairy',
        at: t0.add(const Duration(seconds: 90)),
      );

      await at(300, 150);
      await at(420, 300);
      expect(engine.currentState, GeofenceState.pendingExit);
      await at(481, 500);
      expect(engine.currentState, GeofenceState.outsideStore);
      expect(await db.getActiveVisit(), isNull);

      final edges = await db.getLayoutEdges('target_store');
      expect(edges.single.fromItemCategory, 'produce');
    },
  );

  test(
    'a nearer neighbouring store does not end the visit in progress',
    () async {
      await db.insertStore(_neighbour);
      await engine.forceEnterStore(_target);
      // 60 m north: closer to the neighbour, still within target's 80 m outer ring.
      await at(10, 60);
      expect(engine.currentState, GeofenceState.insideStore);
      expect(engine.activeStore?.id, 'target_store');

      // Walking into the neighbour (100 m from target, 33 m from neighbour) is
      // leaving the target, even though *a* store is still close by.
      await at(20, 100);
      expect(engine.currentState, GeofenceState.pendingExit);
      await at(201, 100);
      expect(engine.currentState, GeofenceState.outsideStore);

      // ...and the neighbour can then be entered normally.
      await at(210, 100);
      expect(engine.currentState, GeofenceState.pendingEntry);
      expect(engine.activeStore?.id, 'neighbour_store');
    },
  );

  test('each store uses its own geofence radius as the arrival ring', () async {
    await db.insertStore(
      const Store(
        id: 'big_mall',
        name: 'Mall',
        latitude: 13.6,
        longitude: 78.6,
        geofenceRadiusMeters: 150,
      ),
    );
    now = t0;
    await engine.onLocationUpdate(
      GeoPoint(
        latitude: 13.6 + 120 / 111000.0,
        longitude: 78.6,
        accuracy: 5,
        timestamp: t0,
      ),
    );
    expect(engine.currentState, GeofenceState.pendingEntry);
    expect(engine.activeStore?.id, 'big_mall');
  });

  test('a recent unfinished visit is resumed after an app restart', () async {
    await db.insertVisit(
      StoreVisit(
        id: 'open_visit',
        storeId: 'target_store',
        entryTimestamp: t0.subtract(const Duration(minutes: 10)),
      ),
    );
    await engine.restoreActiveVisit();
    expect(engine.currentState, GeofenceState.insideStore);
    expect(engine.currentVisit?.id, 'open_visit');
  });

  test('a stale unfinished visit is closed on restart', () async {
    await db.insertVisit(
      StoreVisit(
        id: 'stale_visit',
        storeId: 'target_store',
        entryTimestamp: t0.subtract(const Duration(hours: 8)),
      ),
    );
    await engine.restoreActiveVisit();
    expect(engine.currentState, GeofenceState.outsideStore);
    expect(await db.getActiveVisit(), isNull);
  });
}
