import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/categories.dart';
import '../../data/models/store_layout_edge.dart';
import '../../state/app_state.dart';
import 'store_editor_screen.dart';

class StoresScreen extends StatefulWidget {
  const StoresScreen({super.key});

  @override
  State<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends State<StoresScreen> {
  String? _selectedStoreId;
  List<StoreLayoutEdge> _edges = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      if (state.stores.isNotEmpty) {
        _selectStore(state.stores.first.id);
      }
    });
  }

  Future<void> _selectStore(String storeId) async {
    final state = context.read<AppState>();
    final edges = await state.layoutLearningEngine.getLearnedDag(storeId);
    if (!mounted) return;
    setState(() {
      _selectedStoreId = storeId;
      _edges = edges;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (_selectedStoreId != null && !state.stores.any((s) => s.id == _selectedStoreId)) {
      _selectedStoreId = null;
      _edges = [];
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stores & Layout Learning', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_store',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const StoreEditorScreen()),
        ),
        icon: const Icon(Icons.add_business),
        label: const Text('Add Store'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (state.stores.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'No stores yet. Add the shops and offices you use so the route planner can send items there.',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          const Text(
            'Candidate Stores & Time Windows',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),

          // Stores list
          for (final store in state.stores) ...[
            Card(
              color: _selectedStoreId == store.id
                  ? const Color(0xFF1E293B)
                  : const Color(0xFF131B2E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: _selectedStoreId == store.id
                      ? const Color(0xFF6366F1)
                      : const Color(0xFF334155),
                  width: _selectedStoreId == store.id ? 1.5 : 1,
                ),
              ),
              child: ListTile(
                title: Text(store.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Text(
                      'Hours: ${store.formattedHours}  •  Wait: ${store.avgCheckoutDelaySec ~/ 60}m',
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      children: store.supportedCategories.map((c) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            ItemCategories.labelFor(c),
                            style: const TextStyle(fontSize: 10, color: Colors.white54),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Color(0xFF818CF8)),
                  tooltip: 'Edit store',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => StoreEditorScreen(store: store)),
                  ),
                ),
                onTap: () => _selectStore(store.id),
              ),
            ),
            const SizedBox(height: 8),
          ],

          const SizedBox(height: 16),
          const Divider(color: Color(0xFF334155)),
          const SizedBox(height: 8),

          // Learned DAG Layout Graph for selected store
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Learned In-Store Walk Graph (DAG)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Kahn / FAS',
                  style: TextStyle(fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Net walking order learned from check-off times (exponential decay); conflicting observations cancel out and remaining cycles are cut.',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 12),

          if (_edges.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  'No layout edges recorded yet. Check off items inside this store to train its walk graph!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
            )
          else
            for (final edge in _edges) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        edge.fromItemCategory,
                        style: const TextStyle(
                          color: Color(0xFF818CF8),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, size: 16, color: Colors.white38),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF14B8A6).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        edge.toItemCategory,
                        style: const TextStyle(
                          color: Color(0xFF2DD4BF),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Evidence: ${edge.forwardWeight.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}
