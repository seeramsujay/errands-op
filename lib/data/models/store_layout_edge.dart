/// Directed Store Layout Edge representing empirical walking precedence
class StoreLayoutEdge {
  final String storeId;
  final String fromItemCategory;
  final String toItemCategory;
  final double forwardWeight;
  final int sampleSize;

  const StoreLayoutEdge({
    required this.storeId,
    required this.fromItemCategory,
    required this.toItemCategory,
    this.forwardWeight = 0.0,
    this.sampleSize = 0,
  });

  /// Accumulated precedence evidence: sum of the decay weights of every
  /// observation (forward_weight is their mean). Hand-built edges without a
  /// sample count are treated as a single observation.
  double get evidence => forwardWeight * (sampleSize > 0 ? sampleSize : 1);

  StoreLayoutEdge copyWith({
    String? storeId,
    String? fromItemCategory,
    String? toItemCategory,
    double? forwardWeight,
    int? sampleSize,
  }) {
    return StoreLayoutEdge(
      storeId: storeId ?? this.storeId,
      fromItemCategory: fromItemCategory ?? this.fromItemCategory,
      toItemCategory: toItemCategory ?? this.toItemCategory,
      forwardWeight: forwardWeight ?? this.forwardWeight,
      sampleSize: sampleSize ?? this.sampleSize,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'store_id': storeId,
      'from_item_category': fromItemCategory,
      'to_item_category': toItemCategory,
      'forward_weight': forwardWeight,
      'sample_size': sampleSize,
    };
  }

  factory StoreLayoutEdge.fromMap(Map<String, dynamic> map) {
    return StoreLayoutEdge(
      storeId: map['store_id'] as String,
      fromItemCategory: map['from_item_category'] as String,
      toItemCategory: map['to_item_category'] as String,
      forwardWeight: (map['forward_weight'] as num? ?? 0.0).toDouble(),
      sampleSize: map['sample_size'] as int? ?? 0,
    );
  }
}
