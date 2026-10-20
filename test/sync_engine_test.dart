// These tests talk to a real WebSocket server on loopback, so they must not
// initialise the Flutter test binding (it replaces HttpClient with a stub).
import 'package:flutter_test/flutter_test.dart';
import 'package:op_list/core/hlc.dart';
import 'package:op_list/data/database/app_database.dart';
import 'package:op_list/data/models/todo_item.dart';
import 'package:op_list/data/sync/ha_websocket_client.dart';
import 'package:op_list/state/app_state.dart';

import 'fake_home_assistant.dart';

void main() {
  late AppDatabase db;
  late FakeHomeAssistant ha;
  late AppState state;

  setUp(() async {
    db = AppDatabase.instance;
    await db.init(inMemory: true);
    ha = FakeHomeAssistant();
    await ha.start();
    state = AppState(database: db, solveInBackground: false, geofenceAutoTick: false);
  });

  tearDown(() async {
    final idle = state.syncIdle;
    state.dispose();
    await ha.stop();
    await idle;
    await db.close();
  });

  Future<void> connect({String token = 'good-token'}) async {
    await db.setSetting(SettingKeys.haUrl, ha.url);
    await db.setSetting(SettingKeys.haToken, token);
    await state.initialize();
  }

  TodoItem? local(String summary) => state.items.where((i) => i.summary == summary).firstOrNull;

  List<Map<String, dynamic>> calls(String service) =>
      ha.serviceCalls.where((c) => c['service'] == service).toList();

  test('HybridLogicalClock produces monotonically increasing timestamps', () {
    final hlc = HybridLogicalClock(nodeId: 'device_test');
    final t1 = hlc.now();
    final t2 = hlc.now();
    final t3 = hlc.now();
    expect(t2.isAfter(t1), isTrue);
    expect(t3.isAfter(t2), isTrue);
    expect(t1.toString(), contains('device_test'));

    final merged = hlc.update(HlcTimestamp(physicalTime: t3.physicalTime + 60000, counter: 7, nodeId: 'x'));
    expect(merged.isAfter(t3), isTrue);
    expect(hlc.now().isAfter(merged), isTrue);
  });

  test('websocket URL is derived from what users paste', () {
    expect(HomeAssistantWsClient.websocketUri('homeassistant.local').toString(),
        'ws://homeassistant.local:8123/api/websocket');
    expect(HomeAssistantWsClient.websocketUri('http://192.168.1.5:8123/').toString(),
        'ws://192.168.1.5:8123/api/websocket');
    expect(HomeAssistantWsClient.websocketUri('https://abc.ui.nabu.casa').toString(),
        'wss://abc.ui.nabu.casa/api/websocket');
  });

  test('without settings the app stays local-only and keeps edits queued', () async {
    await state.initialize();
    expect(state.haState, HaConnectionState.notConfigured);
    await state.addItem(summary: 'Bread', category: 'bakery');
    expect(await db.getPendingMutations(), hasLength(1));
  });

  test('connects, authenticates and imports HA items with guessed categories', () async {
    ha.addRemote('Ice cream');
    ha.addRemote('Paracetamol');
    await connect();

    await eventually(() => local('Ice cream') != null && local('Paracetamol') != null);
    expect(state.haState, HaConnectionState.connected);
    expect(local('Ice cream')!.category, 'frozen');
    expect(local('Ice cream')!.isPerishable, isTrue);
    expect(local('Paracetamol')!.category, 'pharmacy');
    // Local sample items were not pushed to HA.
    expect(calls('add_item'), isEmpty);
  });

  test('checking an item off sends update_item with HA uid and only the status', () async {
    final uid = ha.addRemote('Milk');
    await connect();
    await eventually(() => local('Milk') != null);

    await state.toggleItemCompleted(local('Milk')!.id);
    await eventually(() => calls('update_item').isNotEmpty);

    final data = calls('update_item').single['service_data'] as Map;
    expect(data, {'item': uid, 'status': 'completed'});
    expect(calls('update_item').single['target'], {'entity_id': 'todo.shopping_list'});
    expect(ha.items.single['status'], 'completed');
    expect(await db.getPendingMutations(), isEmpty);
  });

  test('deleting an item removes it in Home Assistant too', () async {
    final uid = ha.addRemote('Batteries');
    await connect();
    await eventually(() => local('Batteries') != null);

    await state.deleteItem(local('Batteries')!.id);
    await eventually(() => calls('remove_item').isNotEmpty);
    expect((calls('remove_item').single['service_data'] as Map)['item'], [uid]);
    expect(ha.items, isEmpty);
  });

  test('items added offline are pushed on connect and adopted without duplicates', () async {
    await state.initialize(); // not configured yet
    await state.addItem(summary: 'Hex key', category: 'hardware');

    await db.setSetting(SettingKeys.haUrl, ha.url);
    await state.saveHaSettings(url: ha.url, token: 'good-token', entityId: 'todo.shopping_list');

    await eventually(() => ha.items.any((i) => i['summary'] == 'Hex key'));
    await eventually(() => local('Hex key')?.haUid != null);
    expect(state.items.where((i) => i.summary == 'Hex key'), hasLength(1));
    expect(local('Hex key')!.category, 'hardware'); // local metadata kept

    await state.toggleItemCompleted(local('Hex key')!.id);
    await eventually(() => ha.items.single['status'] == 'completed');
  });

  test('remote rename/complete/delete flow into the local list, keeping local metadata', () async {
    final uid = ha.addRemote('Eggs');
    await connect();
    await eventually(() => local('Eggs') != null);
    await state.togglePin(local('Eggs')!.id);

    ha.updateRemote(uid, summary: 'Free-range eggs', status: 'completed');
    await eventually(() => local('Free-range eggs')?.isCompleted ?? false);
    expect(local('Free-range eggs')!.isPinned, isTrue);
    expect(local('Free-range eggs')!.category, 'groceries');

    ha.removeRemote(uid);
    await eventually(() => local('Free-range eggs') == null);
  });

  test('offline edits are compacted: add-then-delete sends nothing', () async {
    await state.initialize();
    await state.addItem(summary: 'Temporary');
    final id = local('Temporary')!.id;
    await state.toggleItemCompleted(id);
    await state.toggleItemCompleted(id);
    await state.deleteItem(id);
    expect(await db.getPendingMutations(), isEmpty);

    await state.saveHaSettings(url: ha.url, token: 'good-token', entityId: 'todo.shopping_list');
    await eventually(() => state.haState == HaConnectionState.connected);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(ha.serviceCalls, isEmpty);
  });

  test('a description change the list cannot store fails without blocking other edits', () async {
    final uid = ha.addRemote('Soap');
    await connect();
    await eventually(() => local('Soap') != null);
    final soap = local('Soap')!;

    await state.editItem(soap.id,
        summary: 'Soap bars', description: 'unscented', category: soap.category, isPerishable: false);
    await eventually(() => ha.items.any((i) => i['uid'] == uid && i['summary'] == 'Soap bars'));
    // The rejected description is retried a few times, then parked as failed.
    for (var i = 0; i < 6; i++) {
      await state.mutationEngine.flushQueue();
    }
    await state.refreshData();
    expect(state.failedSyncCount, 1);
  });

  test('a bad token reports an error and does not retry forever', () async {
    await connect(token: 'wrong');
    await eventually(() => state.haState == HaConnectionState.error);
    expect(state.haError, contains('Invalid'));
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(ha.connectionCount, 1);
  });

  test('reconnects after the connection drops and syncs edits made meanwhile', () async {
    final uid = ha.addRemote('Rice');
    await connect();
    await eventually(() => local('Rice') != null);

    await ha.dropConnections();
    await eventually(() => state.haState != HaConnectionState.connected);
    await state.toggleItemCompleted(local('Rice')!.id); // queued while offline

    await eventually(() => state.haState == HaConnectionState.connected,
        timeout: const Duration(seconds: 8));
    await eventually(() => ha.items.firstWhere((i) => i['uid'] == uid)['status'] == 'completed');
  });
}
