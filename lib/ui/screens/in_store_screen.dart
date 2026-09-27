import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/todo_item.dart';
import '../../services/geofence_engine.dart';
import '../../state/app_state.dart';

class InStoreScreen extends StatefulWidget {
  const InStoreScreen({super.key});

  @override
  State<InStoreScreen> createState() => _InStoreScreenState();
}

class _InStoreScreenState extends State<InStoreScreen> {
  List<TodoItem>? _walkOrderedItems;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWalkOrder();
  }

  Future<void> _loadWalkOrder() async {
    final state = context.read<AppState>();
    final store = state.activeStore ?? (state.stores.isNotEmpty ? state.stores.first : null);
    if (store != null) {
      final items = await state.getInStoreWalkOrderItems(store);
      if (mounted) {
        setState(() {
          _walkOrderedItems = items;
          _loading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final store = state.activeStore ?? (state.stores.isNotEmpty ? state.stores.first : null);

    if (store == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('In-Store Mode')),
        body: const Center(child: Text('No active store detected.')),
      );
    }

    final allStoreItems = state.items.where((i) {
      return store.supportedCategories.contains(i.category) ||
          store.supportedCategories.contains('generic');
    }).toList();

    final completedCount = allStoreItems.where((i) => i.isCompleted).length;
    final totalCount = allStoreItems.length;
    final progress = totalCount > 0 ? (completedCount / totalCount) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(store.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
            icon: const Icon(Icons.exit_to_app, color: Colors.redAccent, size: 18),
            label: const Text('Exit Store', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Shopping progress bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: const Color(0xFF1E293B),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Shopping Progress: $completedCount of $totalCount items',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF14B8A6)),
                        ),
                      ),
                    ],
                  ),
                ),

                // Walk Order Info Banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  child: (_walkOrderedItems == null || _walkOrderedItems!.isEmpty)
                      ? const Center(
                          child: Text(
                            'No items to pick at this store!',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _walkOrderedItems!.length,
                          itemBuilder: (context, index) {
                            final item = _walkOrderedItems![index];
                            final isDone = item.isCompleted;

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              color: isDone ? const Color(0xFF111827) : const Color(0xFF1E293B),
                              child: ListTile(
                                leading: Checkbox(
                                  value: isDone,
                                  activeColor: const Color(0xFF14B8A6),
                                  onChanged: (_) async {
                                    await state.toggleItemCompleted(item.id);
                                    await _loadWalkOrder();
                                  },
                                ),
                                title: Text(
                                  item.summary,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    decoration: isDone ? TextDecoration.lineThrough : null,
                                    color: isDone ? Colors.white38 : Colors.white,
                                  ),
                                ),
                                subtitle: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Aisle: ${item.category}',
                                        style: const TextStyle(fontSize: 10, color: Colors.white70),
                                      ),
                                    ),
                                    if (item.isPerishable) ...[
                                      const SizedBox(width: 6),
                                      const Text('🧊 Perishable', style: TextStyle(fontSize: 11, color: Color(0xFF67E8F9))),
                                    ],
                                  ],
                                ),
                                trailing: Text(
                                  'Aisle #${index + 1}',
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
