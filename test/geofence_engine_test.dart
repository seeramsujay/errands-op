import 'package:flutter_test/flutter_test.dart';
import 'package:op_list/core/kalman_filter.dart';
import 'package:op_list/data/database/app_database.dart';
import 'package:op_list/data/models/store.dart';
import 'package:op_list/services/geofence_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late GeofenceEngine geofenceEngine;

  setUp(() async {
    db = AppDatabase.instance;
    await db.init(inMemory: true);
    geofenceEngine = GeofenceEngine(database: db);
  });

  tearDown(() async {
    geofenceEngine.dispose();
    await db.close();
  });

  test('Kalman GPS filter discards fixes with horizontal accuracy > 30m', () {
    final filter = KalmanGpsFilter();

    final noisyFix = GeoPoint(
      latitude: 12.9716,
      longitude: 77.5946,
      accuracy: 45.0, // Exceeds 30m threshold!
      timestamp: DateTime.now(),
    );

    final result = filter.processFix(noisyFix);
    expect(result, isNull);

    final goodFix = GeoPoint(
      latitude: 12.9716,
      longitude: 77.5946,
      accuracy: 10.0, // Valid accuracy
      timestamp: DateTime.now(),
    );

    final goodResult = filter.processFix(goodFix);
    expect(goodResult, isNotNull);
    expect(goodResult!.latitude, 12.9716);
  });

  test('Geofence transitions to pendingEntry when inside inner 40m radius', () async {
    final store = const Store(
      id: 'target_store',
      name: 'Target Store',
      latitude: 13.5000, // Distinct coordinates far from seed stores
      longitude: 78.5000,
    );
    await db.insertStore(store);

    // Provide GPS fix within ~5 meters of the target store
    final fixInside = GeoPoint(
      latitude: 13.50002,
      longitude: 78.50002,
      accuracy: 5.0,
      timestamp: DateTime.now(),
    );

    await geofenceEngine.onLocationUpdate(fixInside);

    expect(geofenceEngine.currentState, GeofenceState.pendingEntry);
    expect(geofenceEngine.activeStore?.id, 'target_store');
  });
}
