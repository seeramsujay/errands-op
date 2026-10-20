/// Home Assistant Synced To-Do Item representation
class TodoItem {
  final String id;
  final String haEntityId;
  final String? haUid; // Home Assistant's uid once the item exists there
  final String summary;
  final String? description;
  final String category; // e.g. 'groceries', 'hardware', 'pharmacy', 'dairy', 'frozen'
  final bool isPerishable; // Thermal tag: ice cream, frozen goods, dairy
  final String status; // 'needs_action' or 'completed'
  final int humanOrderIndex; // Human-in-the-loop manual order (never overridden)
  final int? optimizedOrderIndex; // Visual overlay index suggested by solver
  final bool isPinned; // Hard lock sequence constraint
  final DateTime createdAt;
  final DateTime updatedAt;

  const TodoItem({
    required this.id,
    required this.haEntityId,
    this.haUid,
    required this.summary,
    this.description,
    this.category = 'generic',
    this.isPerishable = false,
    this.status = 'needs_action',
    required this.humanOrderIndex,
    this.optimizedOrderIndex,
    this.isPinned = false,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isCompleted => status == 'completed';

  TodoItem copyWith({
    String? id,
    String? haEntityId,
    String? haUid,
    String? summary,
    String? description,
    String? category,
    bool? isPerishable,
    String? status,
    int? humanOrderIndex,
    int? optimizedOrderIndex,
    bool? isPinned,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TodoItem(
      id: id ?? this.id,
      haEntityId: haEntityId ?? this.haEntityId,
      haUid: haUid ?? this.haUid,
      summary: summary ?? this.summary,
      description: description ?? this.description,
      category: category ?? this.category,
      isPerishable: isPerishable ?? this.isPerishable,
      status: status ?? this.status,
      humanOrderIndex: humanOrderIndex ?? this.humanOrderIndex,
      optimizedOrderIndex: optimizedOrderIndex ?? this.optimizedOrderIndex,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ha_entity_id': haEntityId,
      'ha_uid': haUid,
      'summary': summary,
      'description': description,
      'category': category,
      'is_perishable': isPerishable ? 1 : 0,
      'status': status,
      'human_order_index': humanOrderIndex,
      'optimized_order_index': optimizedOrderIndex,
      'is_pinned': isPinned ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory TodoItem.fromMap(Map<String, dynamic> map) {
    return TodoItem(
      id: map['id'] as String,
      haEntityId: map['ha_entity_id'] as String,
      haUid: map['ha_uid'] as String?,
      summary: map['summary'] as String,
      description: map['description'] as String?,
      category: (map['category'] as String?) ?? 'generic',
      isPerishable: (map['is_perishable'] as int? ?? 0) == 1,
      status: (map['status'] as String?) ?? 'needs_action',
      humanOrderIndex: map['human_order_index'] as int? ?? 0,
      optimizedOrderIndex: map['optimized_order_index'] as int?,
      isPinned: (map['is_pinned'] as int? ?? 0) == 1,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
