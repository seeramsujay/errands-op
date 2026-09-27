/// Record in the offline mutation queue
class MutationRecord {
  final String id;
  final String itemId;
  final String field; // e.g. 'status', 'summary', 'human_order_index', 'is_pinned'
  final String? value;
  final String hlcTimestamp; // Monotonic HLC timestamp
  final String status; // 'pending', 'synced', 'failed'
  final int retryCount;
  final DateTime createdAt;

  const MutationRecord({
    required this.id,
    required this.itemId,
    required this.field,
    this.value,
    required this.hlcTimestamp,
    this.status = 'pending',
    this.retryCount = 0,
    required this.createdAt,
  });

  MutationRecord copyWith({
    String? id,
    String? itemId,
    String? field,
    String? value,
    String? hlcTimestamp,
    String? status,
    int? retryCount,
    DateTime? createdAt,
  }) {
    return MutationRecord(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      field: field ?? this.field,
      value: value ?? this.value,
      hlcTimestamp: hlcTimestamp ?? this.hlcTimestamp,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_id': itemId,
      'field': field,
      'value': value,
      'hlc_timestamp': hlcTimestamp,
      'status': status,
      'retry_count': retryCount,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory MutationRecord.fromMap(Map<String, dynamic> map) {
    return MutationRecord(
      id: map['id'] as String,
      itemId: map['item_id'] as String,
      field: map['field'] as String,
      value: map['value'] as String?,
      hlcTimestamp: map['hlc_timestamp'] as String,
      status: (map['status'] as String?) ?? 'pending',
      retryCount: map['retry_count'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
