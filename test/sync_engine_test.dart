import 'package:flutter_test/flutter_test.dart';
import 'package:op_list/core/hlc.dart';
import 'package:op_list/data/database/app_database.dart';
import 'package:op_list/data/models/todo_item.dart';
import 'package:op_list/data/sync/ha_websocket_client.dart';
import 'package:op_list/data/sync/mutation_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late MutationEngine mutationEngine;
  late HomeAssistantWsClient wsClient;

  setUp(() async {
    db = AppDatabase.instance;
    await db.init(inMemory: true);
    wsClient = HomeAssistantWsClient(mockMode: true);
    await wsClient.connect(); // Connect to set state to mockConnected
    mutationEngine = MutationEngine(database: db, wsClient: wsClient);
  });

  tearDown(() async {
    wsClient.dispose();
    await db.close();
  });

  test('HybridLogicalClock produces monotonically increasing timestamps', () {
    final hlc = HybridLogicalClock(nodeId: 'device_test');

    final t1 = hlc.now();
    final t2 = hlc.now();
    final t3 = hlc.now();

    expect(t2.isAfter(t1), isTrue);
    expect(t3.isAfter(t2), isTrue);
    expect(t1.toString(), contains('device_test'));
  });

  test('MutationEngine queues local mutations and drains them', () async {
    final now = DateTime.now();
    final item = TodoItem(
      id: 'item_test_1',
      haEntityId: 'todo.shopping_list',
      summary: 'Cold Brew Coffee',
      humanOrderIndex: 0,
      createdAt: now,
      updatedAt: now,
    );
    await db.insertItem(item);

    await mutationEngine.queueMutation(
      itemId: 'item_test_1',
      field: 'status',
      value: 'completed',
    );

    // Verify mutation recorded and synced
    final pending = await db.getPendingMutations();
    expect(pending.isEmpty, isTrue); // Drained immediately in mock mode
  });
}
