/// Item Category to Store Preference Counter
class ItemStorePreference {
  final String id;
  final String itemCategory;
  final String storeId;
  final int selectionCount;
  final double confidenceScore;

  const ItemStorePreference({
    required this.id,
    required this.itemCategory,
    required this.storeId,
    this.selectionCount = 1,
    this.confidenceScore = 0.5,
  });

  ItemStorePreference copyWith({
    String? id,
    String? itemCategory,
    String? storeId,
    int? selectionCount,
    double? confidenceScore,
  }) {
    return ItemStorePreference(
      id: id ?? this.id,
      itemCategory: itemCategory ?? this.itemCategory,
      storeId: storeId ?? this.storeId,
      selectionCount: selectionCount ?? this.selectionCount,
      confidenceScore: confidenceScore ?? this.confidenceScore,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_category': itemCategory,
      'store_id': storeId,
      'selection_count': selectionCount,
      'confidence_score': confidenceScore,
    };
  }

  factory ItemStorePreference.fromMap(Map<String, dynamic> map) {
    return ItemStorePreference(
      id: map['id'] as String,
      itemCategory: map['item_category'] as String,
      storeId: map['store_id'] as String,
      selectionCount: map['selection_count'] as int? ?? 1,
      confidenceScore: (map['confidence_score'] as num? ?? 0.5).toDouble(),
    );
  }
}
