/// Historical In-Store Visit Record
class StoreVisit {
  final String id;
  final String storeId;
  final DateTime entryTimestamp;
  final DateTime? exitTimestamp;

  const StoreVisit({
    required this.id,
    required this.storeId,
    required this.entryTimestamp,
    this.exitTimestamp,
  });

  bool get isActive => exitTimestamp == null;

  StoreVisit copyWith({
    String? id,
    String? storeId,
    DateTime? entryTimestamp,
    DateTime? exitTimestamp,
  }) {
    return StoreVisit(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      entryTimestamp: entryTimestamp ?? this.entryTimestamp,
      exitTimestamp: exitTimestamp ?? this.exitTimestamp,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'store_id': storeId,
      'entry_timestamp': entryTimestamp.toIso8601String(),
      'exit_timestamp': exitTimestamp?.toIso8601String(),
    };
  }

  factory StoreVisit.fromMap(Map<String, dynamic> map) {
    return StoreVisit(
      id: map['id'] as String,
      storeId: map['store_id'] as String,
      entryTimestamp: DateTime.parse(map['entry_timestamp'] as String),
      exitTimestamp: map['exit_timestamp'] != null
          ? DateTime.tryParse(map['exit_timestamp'] as String)
          : null,
    );
  }
}

/// In-Store Check-Off Event Timestamp
class VisitCheckoff {
  final String id;
  final String visitId;
  final String itemId;
  final String itemCategory;
  final DateTime checkoffTimestamp;

  const VisitCheckoff({
    required this.id,
    required this.visitId,
    required this.itemId,
    this.itemCategory = 'generic',
    required this.checkoffTimestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'visit_id': visitId,
      'item_id': itemId,
      'checkoff_timestamp': checkoffTimestamp.toIso8601String(),
    };
  }

  factory VisitCheckoff.fromMap(Map<String, dynamic> map, {String itemCategory = 'generic'}) {
    return VisitCheckoff(
      id: map['id'] as String,
      visitId: map['visit_id'] as String,
      itemId: map['item_id'] as String,
      itemCategory: itemCategory,
      checkoffTimestamp: DateTime.parse(map['checkoff_timestamp'] as String),
    );
  }
}
