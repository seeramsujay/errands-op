import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/categories.dart';
import '../../data/models/store.dart';
import '../../state/app_state.dart';

class InStoreScreen extends StatefulWidget {
  const InStoreScreen({super.key});

  @override
  State<InStoreScreen> createState() => _InStoreScreenState();
}

class _InStoreScreenState extends State<InStoreScreen> {
  // Walk order (item ids) computed on entry; check-offs don't reshuffle it.
  List<String>? _walkOrder;
  String? _loadedForStoreId;

  Future<void> _loadWalkOrder(Store store) async {
    _loadedForStoreId = store.id;
    final items = await context.read<AppState>().getInStoreWalkOrderItems(
      store,
    );
    if (!mounted) return;
    setState(() => _walkOrder = items.map((i) => i.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final store = state.activeStore;

    if (store == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('In-Store Mode')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'You are not inside a store right now. In-Store Mode starts automatically after '
              'a couple of minutes at a store with Live GPS on.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ),
      );
    }

    if (_loadedForStoreId != store.id) {
      _walkOrder = null;
      _loadWalkOrder(store);
    }

    final byId = {for (final i in state.items) i.id: i};
    final allStoreItems = [
      for (final id in _walkOrder ?? const <String>[])
        if (byId[id] != null) byId[id]!,
    ];
    final loading = _walkOrder == null;

    final completedCount = allStoreItems.where((i) => i.isCompleted).length;
    final totalCount = allStoreItems.length;
    final progress = totalCount > 0 ? (completedCount / totalCount) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              store.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Text(
              'Aisle Walk-Order Active (Learned DAG)',
              style: TextStyle(fontSize: 11, color: Color(0xFF10B981)),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await state.simulateStoreExit();
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            icon: const Icon(
              Icons.exit_to_app,
              color: Colors.redAccent,
              size: 18,
            ),
            label: const Text(
              'Exit Store',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Shopping progress bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  color: const Color(0xFF1E293B),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Shopping Progress: $completedCount of $totalCount items',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${(progress * 100).toInt()}%',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF14B8A6),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor: const Color(0xFF334155),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF14B8A6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Walk Order Info Banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: const Color(0xFF0F172A),
                  child: const Row(
                    children: [
                      Icon(Icons.route, size: 16, color: Color(0xFF6366F1)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Items sorted by empirical in-aisle walk order using Feedback Arc Set & Kahn\'s Sort',
                          style: TextStyle(fontSize: 11, color: Colors.white60),
                        ),
                      ),
                    ],
                  ),
                ),

                // Item Check-Off List
                Expanded(
                  child: allStoreItems.isEmpty
                      ? const Center(
                          child: Text(
                            'No items to pick at this store!',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: allStoreItems.length,
                          itemBuilder: (context, index) {
                            final item = allStoreItems[index];
                            final isDone = item.isCompleted;

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              color: isDone
                                  ? const Color(0xFF111827)
                                  : const Color(0xFF1E293B),
                              child: ListTile(
                                leading: Checkbox(
                                  value: isDone,
                                  activeColor: const Color(0xFF14B8A6),
                                  onChanged: (_) =>
                                      state.toggleItemCompleted(item.id),
                                ),
                                title: Text(
                                  item.summary,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    decoration: isDone
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: isDone
                                        ? Colors.white38
                                        : Colors.white,
                                  ),
                                ),
                                subtitle: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.06,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        ItemCategories.labelFor(item.category),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                    if (item.isPerishable) ...[
                                      const SizedBox(width: 6),
                                      const Text(
                                        '🧊 Perishable',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF67E8F9),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: Text(
                                  '#${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF6366F1),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
