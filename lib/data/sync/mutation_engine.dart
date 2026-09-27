import 'package:uuid/uuid.dart';
import '../../core/hlc.dart';
import '../database/app_database.dart';
import '../models/mutation_record.dart';
import '../models/todo_item.dart';
import 'ha_websocket_client.dart';

/// LWW-HLC offline mutation engine
class MutationEngine {
  final AppDatabase database;
  final HybridLogicalClock hlc;
  final HomeAssistantWsClient wsClient;

  bool _isFlushing = false;

  MutationEngine({
    required this.database,
    required this.wsClient,
    HybridLogicalClock? hlc,
  }) : hlc = hlc ?? HybridLogicalClock();

  /// Queue an item modification locally and attempt sync
  Future<void> queueMutation({
    required String itemId,
    required String field,
    required String? value,
  }) async {
    final timestamp = hlc.now().toString();
    final mutation = MutationRecord(
      id: const Uuid().v4(),
      itemId: itemId,
      field: field,
      value: value,
      hlcTimestamp: timestamp,
      status: 'pending',
      retryCount: 0,
      createdAt: DateTime.now(),
    );

    await database.enqueueMutation(mutation);

    // If connected or in mock mode, attempt flush immediately
    if (wsClient.state == HaConnectionState.connected ||
        wsClient.state == HaConnectionState.mockConnected) {
      await flushQueue();
    }
  }

  /// Drain the pending mutation queue
  Future<void> flushQueue() async {
    if (_isFlushing) return;
    _isFlushing = true;

    try {
      final pending = await database.getPendingMutations();
      for (final m in pending) {
        final item = await database.getItem(m.itemId);
        if (item == null) {
          await database.markMutationSynced(m.id);
          continue;
        }

        bool success = false;
        if (m.field == 'status') {
          success = await wsClient.sendTodoUpdate(
            itemId: item.id,
            summary: item.summary,
            status: m.value ?? item.status,
            description: item.description,
          );
        } else if (m.field == 'summary') {
          success = await wsClient.sendTodoUpdate(
            itemId: item.id,
            summary: m.value ?? item.summary,
            status: item.status,
            description: item.description,
          );
        } else if (m.field == 'deleted') {
          success = await wsClient.sendTodoRemove(itemId: item.id);
        } else {
          // Internal fields (e.g. human_order_index, is_pinned) are kept local
          success = true;
        }

        if (success) {
          await database.markMutationSynced(m.id);
        } else {
          await database.markMutationFailed(m.id);
        }
      }
    } finally {
      _isFlushing = false;
    }
  }

  /// Reconcile incoming remote delta update from Home Assistant with LWW semantics
  Future<void> reconcileRemoteItem(Map<String, dynamic> remoteData) async {
    final itemId = remoteData['id'] as String?;
    if (itemId == null) return;

    final existing = await database.getItem(itemId);
    final summary = remoteData['summary'] as String? ?? 'Untitled Item';
    final status = remoteData['status'] as String? ?? 'needs_action';
    final category = remoteData['category'] as String? ?? 'generic';
    final isPerishable = remoteData['is_perishable'] == true;

    // Check if there are local un-synced pending mutations for this item
    final pending = await database.getPendingMutations();
    final localItemMutations = pending.where((m) => m.itemId == itemId).toList();

    if (localItemMutations.isNotEmpty) {
      // Local edit is in flight: Last-Write-Wins check
      // For remote events without HLC, local deliberate mutations take priority
      return;
    }

    if (existing == null) {
      // New remote item added
      final allItems = await database.getItems();
      final newItem = TodoItem(
        id: itemId,
        haEntityId: wsClient.entityId,
        summary: summary,
        category: category,
        isPerishable: isPerishable,
        status: status,
        humanOrderIndex: allItems.length,
        isPinned: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await database.insertItem(newItem);
    } else {
      // Remote item updated: preserve human_order_index and is_pinned!
      final updated = existing.copyWith(
        summary: summary,
        status: status,
        updatedAt: DateTime.now(),
      );
      await database.updateItem(updated);
    }
  }
}
