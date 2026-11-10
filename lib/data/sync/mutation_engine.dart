import 'package:uuid/uuid.dart';

import '../../core/categories.dart';
import '../../core/hlc.dart';
import '../database/app_database.dart';
import '../models/mutation_record.dart';
import '../models/todo_item.dart';
import 'ha_websocket_client.dart';

/// Fields mirrored to Home Assistant. Everything else (order, pins,
/// category, perishable flag) only exists in this app and is never queued.
class SyncField {
  static const create = 'create';
  static const status = 'status';
  static const summary = 'summary';
  static const description = 'description';
  static const deleted = 'deleted'; // value = HA uid of the removed item

  static const all = {create, status, summary, description, deleted};
}

/// LWW-HLC offline mutation engine
///
/// Local edits are appended to a durable queue stamped with a Hybrid Logical
/// Clock and drained in HLC order whenever Home Assistant is reachable.
/// While an item has unsent local edits, incoming snapshots don't overwrite
/// it (the local write is the later one); afterwards HA is the source of truth.
class MutationEngine {
  final AppDatabase database;
  final HybridLogicalClock hlc;
  final HomeAssistantWsClient wsClient;

  bool _isFlushing = false;
  bool _flushAgain = false;

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
    if (!SyncField.all.contains(field)) return; // local-only field

    if (field == SyncField.deleted) {
      final dropped = await database.discardPendingMutations(itemId);
      // Never reached HA (or was never meant to): nothing to remove remotely.
      if (dropped.contains(SyncField.create) || value == null) return;
    } else if (field != SyncField.create) {
      await database.discardPendingMutations(itemId, field: field);
    }

    await database.enqueueMutation(
      MutationRecord(
        id: const Uuid().v4(),
        itemId: itemId,
        field: field,
        value: value,
        hlcTimestamp: hlc.now().toString(),
        createdAt: DateTime.now(),
      ),
    );

    if (wsClient.isConnected) await flushQueue();
  }

  /// Drain the pending mutation queue
  Future<void> flushQueue() async {
    if (!wsClient.isConnected) return;
    if (_isFlushing) {
      _flushAgain = true;
      return;
    }
    _isFlushing = true;

    try {
      do {
        _flushAgain = false;
        await _flushOnce();
      } while (_flushAgain && wsClient.isConnected);
    } finally {
      _isFlushing = false;
    }
  }

  Future<void> _flushOnce() async {
    final pending = await database.getPendingMutations();
    for (final m in pending) {
      if (!wsClient.isConnected) return;

      if (m.field == SyncField.deleted) {
        await _record(m, await wsClient.removeItem(uid: m.value!));
        continue;
      }

      final item = await database.getItem(m.itemId);
      if (item == null) {
        await database.markMutationSynced(m.id); // deleted locally meanwhile
        continue;
      }

      if (m.field == SyncField.create) {
        if (item.haUid != null) {
          await database.markMutationSynced(m.id);
        } else {
          await _record(m, await wsClient.addItem(summary: item.summary));
        }
        continue;
      }

      // Edits need HA's uid; it arrives with the snapshot after the create.
      final uid = item.haUid;
      if (uid == null) continue;

      final res = switch (m.field) {
        SyncField.status => await wsClient.updateItem(
          uid: uid,
          status: item.status,
        ),
        SyncField.summary => await wsClient.updateItem(
          uid: uid,
          rename: item.summary,
        ),
        _ => await wsClient.updateItem(
          uid: uid,
          description: item.description ?? '',
        ),
      };
      await _record(m, res);
    }
  }

  Future<void> _record(MutationRecord m, HaResult res) async {
    if (res.success) {
      await database.markMutationSynced(m.id);
    } else if (wsClient.isConnected) {
      await database.markMutationFailed(m.id);
    }
    // Lost the connection mid-call: leave it pending without burning a retry.
  }

  /// Reconcile a full snapshot of the HA list with the local database.
  /// Returns true when local data changed.
  Future<bool> reconcileSnapshot(List<HaTodoItem> remoteItems) async {
    var changed = false;
    final localItems = await database.getItems();
    final remoteUids = <String>{};
    var nextOrder = localItems.isEmpty
        ? 0
        : localItems
                  .map((i) => i.humanOrderIndex)
                  .reduce((a, b) => a > b ? a : b) +
              1;

    for (final remote in remoteItems) {
      remoteUids.add(remote.uid);
      var local = await database.getItemByHaUid(remote.uid);

      if (local == null) {
        // An item we added ourselves comes back with HA's uid: adopt it by name.
        final match = localItems.where(
          (i) =>
              i.haUid == null &&
              i.summary.trim().toLowerCase() ==
                  remote.summary.trim().toLowerCase(),
        );
        if (match.isNotEmpty) {
          local = match.first.copyWith(haUid: remote.uid);
          localItems.remove(match.first);
          await database.updateItem(local);
          changed = true;
        }
      }

      if (local == null) {
        await database.insertItem(newItemFromRemote(remote, nextOrder++));
        changed = true;
        continue;
      }

      if (await database.hasPendingMutations(local.id)) continue;

      if (local.summary != remote.summary ||
          local.status != remote.status ||
          (remote.description != null &&
              local.description != remote.description)) {
        await database.updateItem(
          local.copyWith(
            summary: remote.summary,
            status: remote.status,
            description: remote.description,
            updatedAt: DateTime.now(),
          ),
        );
        changed = true;
      }
    }

    // Removed in HA (or cleared as completed) and not edited here since.
    for (final local in await database.getItems()) {
      if (local.haUid == null || remoteUids.contains(local.haUid)) continue;
      if (local.haEntityId != wsClient.entityId) continue;
      if (await database.hasPendingMutations(local.id)) continue;
      await database.deleteItem(local.id);
      changed = true;
    }

    if (wsClient.isConnected) await flushQueue();
    return changed;
  }

  /// HA only knows a summary; infer category and perishability from it.
  TodoItem newItemFromRemote(HaTodoItem remote, int orderIndex) {
    final category = ItemCategories.classify(remote.summary);
    final now = DateTime.now();
    return TodoItem(
      id: const Uuid().v4(),
      haEntityId: wsClient.entityId,
      haUid: remote.uid,
      summary: remote.summary,
      description: remote.description,
      category: category.id,
      isPerishable: category.perishableByDefault,
      status: remote.status,
      humanOrderIndex: orderIndex,
      createdAt: now,
      updatedAt: now,
    );
  }
}
