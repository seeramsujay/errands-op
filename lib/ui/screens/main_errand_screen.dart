import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/todo_item.dart';
import '../../data/sync/ha_websocket_client.dart';
import '../../services/geofence_engine.dart';
import '../../state/app_state.dart';
import '../widgets/geofence_badge.dart';
import '../widgets/item_tile.dart';
import 'in_store_screen.dart';
import 'route_plan_screen.dart';

class MainErrandScreen extends StatefulWidget {
  const MainErrandScreen({super.key});

  @override
  State<MainErrandScreen> createState() => _MainErrandScreenState();
}

class _MainErrandScreenState extends State<MainErrandScreen> {
  String _selectedFilter = 'all'; // 'all', 'pending', 'perishables', 'pinned'

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    List<TodoItem> displayedItems = state.items;
    if (_selectedFilter == 'pending') {
      displayedItems = displayedItems.where((i) => !i.isCompleted).toList();
    } else if (_selectedFilter == 'perishables') {
      displayedItems = displayedItems.where((i) => i.isPerishable).toList();
    } else if (_selectedFilter == 'pinned') {
      displayedItems = displayedItems.where((i) => i.isPinned).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.bolt, color: Color(0xFF6366F1), size: 24),
            const SizedBox(width: 8),
            const Text(
              'op-list',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
            ),
            const Spacer(),
            // Home Assistant status pill
            _buildHaStatusPill(state.haState),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                GeofenceBadge(
                  state: state.geofenceState,
                  activeStore: state.activeStore,
                  dwellSeconds: state.dwellSeconds,
                ),
                const Spacer(),
                Text(
                  '${state.items.where((i) => !i.isCompleted).length} pending',
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Inside Store Shopping Mode shortcut banner
          if (state.geofenceState == GeofenceState.insideStore && state.activeStore != null)
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InStoreScreen()),
                );
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF065F46), Color(0xFF047857)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_bag, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Inside ${state.activeStore!.name}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const Text(
                            'Tap to switch to Learned Walk-Order shopping mode',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
                  ],
                ),
              ),
            ),

          // Filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _buildFilterChip('all', 'All (${state.items.length})'),
                const SizedBox(width: 6),
                _buildFilterChip(
                  'pending',
                  'Pending (${state.items.where((i) => !i.isCompleted).length})',
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  'perishables',
                  '🧊 Cold (${state.items.where((i) => i.isPerishable).length})',
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  'pinned',
                  '📌 Pinned (${state.items.where((i) => i.isPinned).length})',
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFF334155)),

          // Reorderable list preserving human_order_index
          Expanded(
            child: displayedItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, size: 56, color: Colors.white.withOpacity(0.2)),
                        const SizedBox(height: 12),
                        const Text(
                          'No items in this filter',
                          style: TextStyle(color: Colors.white54, fontSize: 15),
                        ),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    itemCount: displayedItems.length,
                    onReorder: (oldIndex, newIndex) {
                      state.reorderItem(oldIndex, newIndex);
                    },
                    itemBuilder: (context, index) {
                      final item = displayedItems[index];
                      return ItemTile(
                        key: ValueKey(item.id),
                        item: item,
                        index: index,
                        onToggleComplete: () => state.toggleItemCompleted(item.id),
                        onTogglePin: () => state.togglePin(item.id),
                        onDelete: () => state.deleteItem(item.id),
                      );
                    },
                  ),
          ),

          // "I'm Going Out" Bottom Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(top: BorderSide(color: Color(0xFF334155), width: 1)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  // Quick add button
                  IconButton.filledTonal(
                    onPressed: () => _showAddItemDialog(context, state),
                    icon: const Icon(Icons.add),
                    tooltip: 'Add item',
                  ),
                  const SizedBox(width: 12),

                  // "I'm Going Out" solver button
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 4,
                      ),
                      onPressed: state.isSolving
                          ? null
                          : () async {
                              final route = await state.solveErrandRoute();
                              if (!mounted) return;
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => RoutePlanScreen(route: route),
                                ),
                              );
                            },
                      icon: state.isSolving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.navigation_outlined, size: 20),
                      label: Text(
                        state.isSolving ? 'Optimizing Itinerary...' : "I'm Going Out",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      selected: isSelected,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: isSelected ? Colors.white : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selectedColor: const Color(0xFF6366F1).withOpacity(0.3),
      backgroundColor: const Color(0xFF1E293B),
      side: BorderSide(
        color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF334155),
      ),
      onSelected: (_) => setState(() => _selectedFilter = value),
    );
  }

  Widget _buildHaStatusPill(HaConnectionState state) {
    Color dotColor = Colors.grey;
    String text = 'Offline';

    if (state == HaConnectionState.connected) {
      dotColor = const Color(0xFF10B981);
      text = 'HA Live';
    } else if (state == HaConnectionState.mockConnected) {
      dotColor = const Color(0xFF06B6D4);
      text = 'HA Mock';
    } else if (state == HaConnectionState.connecting || state == HaConnectionState.authenticating) {
      dotColor = const Color(0xFFF59E0B);
      text = 'Syncing';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: dotColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dotColor.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: dotColor,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddItemDialog(BuildContext context, AppState state) {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    var selectedCat = 'groceries';
    var isPerishable = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add Errand / Item',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'What do you need?',
                      hintStyle: TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Color(0xFF1E293B),
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(
                      hintText: 'Notes / specifications (optional)',
                      hintStyle: TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Color(0xFF1E293B),
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Category dropdown
                  Row(
                    children: [
                      const Text('Category:', style: TextStyle(color: Colors.white70)),
                      const SizedBox(width: 10),
                      DropdownButton<String>(
                        value: selectedCat,
                        dropdownColor: const Color(0xFF1E293B),
                        items: const [
                          DropdownMenuItem(value: 'groceries', child: Text('Groceries')),
                          DropdownMenuItem(value: 'dairy', child: Text('Dairy')),
                          DropdownMenuItem(value: 'frozen', child: Text('Frozen Foods')),
                          DropdownMenuItem(value: 'produce', child: Text('Fresh Produce')),
                          DropdownMenuItem(value: 'pharmacy', child: Text('Pharmacy')),
                          DropdownMenuItem(value: 'hardware', child: Text('Hardware')),
                          DropdownMenuItem(value: 'admin_errand', child: Text('Admin / Document')),
                          DropdownMenuItem(value: 'generic', child: Text('Generic')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              selectedCat = val;
                              if (val == 'frozen' || val == 'dairy') {
                                isPerishable = true;
                              }
                            });
                          }
                        },
                      ),
                    ],
                  ),

                  // Perishable toggle
                  SwitchListTile(
                    title: const Text('Perishable / Thermal Sensitive (Keep Cold)'),
                    subtitle: const Text(
                      'Pushes stop to the final leg of trip',
                      style: TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                    value: isPerishable,
                    activeColor: const Color(0xFF06B6D4),
                    onChanged: (val) => setModalState(() => isPerishable = val),
                    contentPadding: EdgeInsets.zero,
                  ),

                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        if (titleController.text.trim().isNotEmpty) {
                          state.addItem(
                            summary: titleController.text.trim(),
                            description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                            category: selectedCat,
                            isPerishable: isPerishable,
                          );
                          Navigator.pop(ctx);
                        }
                      },
                      child: const Text('Add to Errand List', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
