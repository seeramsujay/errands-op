import 'dart:math';

/// Representation of a 2D coordinate with accuracy
class GeoPoint {
  final double latitude;
  final double longitude;
  final double accuracy; // Horizontal accuracy in meters
  final DateTime timestamp;

  const GeoPoint({
    required this.latitude,
    required this.longitude,
    this.accuracy = 5.0,
    required this.timestamp,
  });

  @override
  String toString() =>
      'GeoPoint(lat: ${latitude.toStringAsFixed(5)}, lng: ${longitude.toStringAsFixed(5)}, acc: ${accuracy.toStringAsFixed(1)}m)';
}

/// 2D Kalman filter for smoothing noisy GPS updates and estimating velocity.
/// Rejects measurements with horizontal accuracy > maxAccuracyThreshold.
class KalmanGpsFilter {
  final double maxAccuracyThreshold; // Discard fixes worse than 30m
  final double processNoiseQ;

  double? _lat;
  double? _lng;
  double? _variance; // Covariance P
  DateTime? _lastTimestamp;

  KalmanGpsFilter({
    this.maxAccuracyThreshold = 30.0,
    this.processNoiseQ = 3.0, // Process noise (meters per second)
  });

  /// Reset filter state
  void reset() {
    _lat = null;
    _lng = null;
    _variance = null;
    _lastTimestamp = null;
  }

  /// Process incoming raw GPS fix. Returns smoothed fix, or null if rejected.
  GeoPoint? processFix(GeoPoint raw) {
    // 1. Accuracy gate
    if (raw.accuracy > maxAccuracyThreshold) {
      return null; // Discard noisy reading
    }

    if (_lat == null || _lng == null || _variance == null || _lastTimestamp == null) {
      // Initialize with first valid fix
      _lat = raw.latitude;
      _lng = raw.longitude;
      _variance = raw.accuracy * raw.accuracy;
      _lastTimestamp = raw.timestamp;
      return raw;
    }

    // Time delta in seconds
    final dt = raw.timestamp.difference(_lastTimestamp!).inMilliseconds / 1000.0;
    _lastTimestamp = raw.timestamp;

    if (dt > 0) {
      // 2. Predict: Variance increases with time delta and process noise
      _variance = _variance! + dt * processNoiseQ * processNoiseQ;
    }

    // 3. Measurement variance R
    final r = raw.accuracy * raw.accuracy;

    // 4. Kalman Gain K = P / (P + R)
    final k = _variance! / (_variance! + r);

    // 5. Update state
    _lat = _lat! + k * (raw.latitude - _lat!);
    _lng = _lng! + k * (raw.longitude - _lng!);

    // 6. Update covariance P = (1 - K) * P
    _variance = (1.0 - k) * _variance!;

    final estimatedAccuracy = sqrt(_variance!);
    return GeoPoint(
      latitude: _lat!,
      longitude: _lng!,
      accuracy: estimatedAccuracy,
      timestamp: raw.timestamp,
    );
  }

  GeoPoint? get currentEstimatedPosition {
    if (_lat == null || _lng == null) return null;
    return GeoPoint(
      latitude: _lat!,
      longitude: _lng!,
      accuracy: _variance != null ? sqrt(_variance!) : 5.0,
      timestamp: _lastTimestamp ?? DateTime.now(),
    );
  }
}
