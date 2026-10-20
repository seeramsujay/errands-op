import 'dart:async';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../core/kalman_filter.dart';

/// Outcome of trying to start live location updates.
enum LocationStartResult { started, serviceDisabled, permissionDenied, unsupported }

/// Thin wrapper over the platform location plugin that emits [GeoPoint]s.
/// The geofence engine does its own accuracy gating and smoothing, so the
/// raw fixes (with their reported accuracy) are passed through untouched.
class LocationService {
  StreamSubscription<Position>? _subscription;

  bool get isTracking => _subscription != null;

  Future<LocationStartResult> start(void Function(GeoPoint) onFix) async {
    await stop();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationStartResult.serviceDisabled;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return LocationStartResult.permissionDenied;
      }

      _subscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        (p) => onFix(GeoPoint(
          latitude: p.latitude,
          longitude: p.longitude,
          accuracy: p.accuracy,
          timestamp: p.timestamp,
        )),
        onError: (_) {},
      );
      return LocationStartResult.started;
    } on MissingPluginException {
      return LocationStartResult.unsupported; // e.g. Linux desktop
    } on UnimplementedError {
      return LocationStartResult.unsupported;
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
