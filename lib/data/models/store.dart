/// Store Master Entity representation
class Store {
  final String id;
  final String name;
  final String? brand;
  final double latitude;
  final double longitude;
  final double geofenceRadiusMeters;
  final int? openingTimeSec; // Seconds from 00:00 (e.g. 9*3600 = 32400 for 9am)
  final int?
  closingTimeSec; // Seconds from 00:00 (e.g. 21*3600 = 75600 for 9pm)
  final int avgCheckoutDelaySec; // Estimated in-store shopping/wait duration (default 600s = 10m)
  final List<String> supportedCategories;

  const Store({
    required this.id,
    required this.name,
    this.brand,
    required this.latitude,
    required this.longitude,
    this.geofenceRadiusMeters = 50.0,
    this.openingTimeSec = 32400, // 09:00 AM
    this.closingTimeSec = 75600, // 09:00 PM
    this.avgCheckoutDelaySec = 600, // 10 minutes
    this.supportedCategories = const ['generic'],
  });

  bool get isAlwaysOpen =>
      openingTimeSec == null ||
      closingTimeSec == null ||
      openingTimeSec == closingTimeSec;

  /// The opening period that contains [time], or failing that the next one
  /// that starts later on the same calendar day. Handles stores that close
  /// after midnight (closing earlier in the day than opening). Returns null
  /// when the store does not open again that day.
  ({DateTime open, DateTime close})? windowAtOrAfter(DateTime time) {
    if (isAlwaysOpen) {
      return (open: time, close: time.add(const Duration(days: 365)));
    }
    final overnight = closingTimeSec! < openingTimeSec!;
    ({DateTime open, DateTime close}) windowFor(int dayOffset) {
      final day = DateTime(time.year, time.month, time.day + dayOffset);
      final closeDay = overnight
          ? DateTime(day.year, day.month, day.day + 1)
          : day;
      return (
        open: day.add(Duration(seconds: openingTimeSec!)),
        close: closeDay.add(Duration(seconds: closingTimeSec!)),
      );
    }

    // Yesterday's window can still be running after midnight for overnight stores.
    for (final offset in overnight ? const [-1, 0] : const [0]) {
      final w = windowFor(offset);
      if (!time.isBefore(w.open) && !time.isAfter(w.close)) return w;
    }
    final today = windowFor(0);
    if (time.isBefore(today.open)) return today;
    return null;
  }

  /// Check if the store is open at a given DateTime
  bool isOpenAt(DateTime time) {
    final w = windowAtOrAfter(time);
    return w != null && !time.isBefore(w.open);
  }

  /// Format opening hours as readable string (e.g. "09:00 - 21:00")
  String get formattedHours {
    if (openingTimeSec == null || closingTimeSec == null) return '24 Hours';
    final openH = (openingTimeSec! ~/ 3600).toString().padLeft(2, '0');
    final openM = ((openingTimeSec! % 3600) ~/ 60).toString().padLeft(2, '0');
    final closeH = (closingTimeSec! ~/ 3600).toString().padLeft(2, '0');
    final closeM = ((closingTimeSec! % 3600) ~/ 60).toString().padLeft(2, '0');
    return '$openH:$openM - $closeH:$closeM';
  }

  Store copyWith({
    String? id,
    String? name,
    String? brand,
    double? latitude,
    double? longitude,
    double? geofenceRadiusMeters,
    int? openingTimeSec,
    int? closingTimeSec,
    int? avgCheckoutDelaySec,
    List<String>? supportedCategories,
  }) {
    return Store(
      id: id ?? this.id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      geofenceRadiusMeters: geofenceRadiusMeters ?? this.geofenceRadiusMeters,
      openingTimeSec: openingTimeSec ?? this.openingTimeSec,
      closingTimeSec: closingTimeSec ?? this.closingTimeSec,
      avgCheckoutDelaySec: avgCheckoutDelaySec ?? this.avgCheckoutDelaySec,
      supportedCategories: supportedCategories ?? this.supportedCategories,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'brand': brand,
      'latitude': latitude,
      'longitude': longitude,
      'geofence_radius_meters': geofenceRadiusMeters,
      'opening_time_sec': openingTimeSec,
      'closing_time_sec': closingTimeSec,
      'avg_checkout_delay_sec': avgCheckoutDelaySec,
      'supported_categories': supportedCategories.join(','),
    };
  }

  factory Store.fromMap(Map<String, dynamic> map) {
    final catStr = map['supported_categories'] as String?;
    final categories = catStr != null && catStr.isNotEmpty
        ? catStr.split(',')
        : <String>['generic'];

    return Store(
      id: map['id'] as String,
      name: map['name'] as String,
      brand: map['brand'] as String?,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      geofenceRadiusMeters: (map['geofence_radius_meters'] as num? ?? 50.0)
          .toDouble(),
      openingTimeSec: map['opening_time_sec'] as int?,
      closingTimeSec: map['closing_time_sec'] as int?,
      avgCheckoutDelaySec: map['avg_checkout_delay_sec'] as int? ?? 600,
      supportedCategories: categories,
    );
  }
}
