import 'package:flutter/material.dart';

import '../../core/categories.dart';
import '../../data/models/todo_item.dart';

class ItemTile extends StatelessWidget {
  final TodoItem item;
  final int index;
  final VoidCallback onToggleComplete;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;

  const ItemTile({
    super.key,
    required this.item,
    required this.index,
    required this.onToggleComplete,
    required this.onTogglePin,
    required this.onDelete,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = item.isCompleted;

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.shade900,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        color: isDone ? const Color(0xFF131A29) : const Color(0xFF1E293B),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                // Reorder Drag Handle
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.drag_indicator,
                      color: Colors.white.withValues(alpha: 0.3),
                      size: 22,
                    ),
                  ),
                ),

                // Checkbox
                Checkbox(
                  value: isDone,
                  onChanged: (_) => onToggleComplete(),
                  activeColor: const Color(0xFF14B8A6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),

                // Main content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.summary,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDone ? Colors.white38 : Colors.white,
                          decoration: isDone
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (item.description != null &&
                          item.description!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.description!,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDone ? Colors.white24 : Colors.white60,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),

                      // Non-destructive Visual Overlay Badges
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          // Human Order Index badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '#${item.humanOrderIndex + 1}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.white70,
                              ),
                            ),
                          ),

                          // Suggested Route Stop badge (if solver solved)
                          if (item.optimizedOrderIndex != null && !isDone)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1)
                                    .withValues(alpha: 0.2),
                                border: Border.all(
                                  color: const Color(0xFF6366F1),
                                  width: 0.8,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.alt_route,
                                    size: 12,
                                    color: Color(0xFF818CF8),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Stop #${item.optimizedOrderIndex}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF818CF8),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Perishable / Thermal Decay Tag
                          if (item.isPerishable)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF06B6D4)
                                    .withValues(alpha: 0.18),
                                border: Border.all(
                                  color: const Color(0xFF06B6D4),
                                  width: 0.8,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('🧊 ', style: TextStyle(fontSize: 11)),
                                  Text(
                                    'Keep cold',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF67E8F9),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Category chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              ItemCategories.labelFor(item.category),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Pin / Hard Lock button
                IconButton(
                  icon: Icon(
                    item.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    color: item.isPinned
                        ? const Color(0xFFFBBF24)
                        : Colors.white24,
                    size: 20,
                  ),
                  tooltip: item.isPinned
                      ? 'Hard sequence lock (Pinned)'
                      : 'Pin as hard lock',
                  onPressed: onTogglePin,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
