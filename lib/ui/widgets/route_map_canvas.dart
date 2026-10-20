import 'dart:math';
import 'package:flutter/material.dart';
import '../../services/geofence_engine.dart';
import '../../data/models/active_route.dart';
import '../../data/models/store.dart';

class RouteMapCanvas extends StatelessWidget {
  final double userLat;
  final double userLon;
  final List<Store> stores;
  final ActiveRoute? activeRoute;
  final Store? activeStore;
  final Function(Store)? onStoreTap;

  const RouteMapCanvas({
    super.key,
    required this.userLat,
    required this.userLon,
    required this.stores,
    this.activeRoute,
    this.activeStore,
    this.onStoreTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: const Color(0xFF0B132B),
            child: CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _MapPainter(
                userLat: userLat,
                userLon: userLon,
                stores: stores,
                activeRoute: activeRoute,
                activeStore: activeStore,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MapPainter extends CustomPainter {
  final double userLat;
  final double userLon;
  final List<Store> stores;
  final ActiveRoute? activeRoute;
  final Store? activeStore;

  _MapPainter({
    required this.userLat,
    required this.userLon,
    required this.stores,
    this.activeRoute,
    this.activeStore,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Determine bounding box around user and stores
    var minLat = userLat;
    var maxLat = userLat;
    var minLon = userLon;
    var maxLon = userLon;

    for (final s in stores) {
      if (s.latitude < minLat) minLat = s.latitude;
      if (s.latitude > maxLat) maxLat = s.latitude;
      if (s.longitude < minLon) minLon = s.longitude;
      if (s.longitude > maxLon) maxLon = s.longitude;
    }

    // Add padding margin to bounding box
    final latPadding = max((maxLat - minLat) * 0.25, 0.008);
    final lonPadding = max((maxLon - minLon) * 0.25, 0.008);

    minLat -= latPadding;
    maxLat += latPadding;
    minLon -= lonPadding;
    maxLon += lonPadding;

    Offset toCanvas(double lat, double lon) {
      final x = ((lon - minLon) / (maxLon - minLon)) * size.width;
      // Invert Y because canvas Y goes downwards
      final y = (1.0 - (lat - minLat) / (maxLat - minLat)) * size.height;
      return Offset(x, y);
    }

    // 1. Draw subtle background coordinate grid
    final gridPaint = Paint()
      ..color = const Color(0xFF1C2A4A).withValues(alpha: 0.5)
      ..strokeWidth = 1;

    for (var x = 0.0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 2. Draw planned route polyline connecting origin and stops
    if (activeRoute != null && activeRoute!.stops.isNotEmpty) {
      final routePaint = Paint()
        ..color = const Color(0xFF6366F1).withValues(alpha: 0.8)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      var prevPos = toCanvas(userLat, userLon);
      path.moveTo(prevPos.dx, prevPos.dy);

      for (final stop in activeRoute!.stops) {
        if (stop.store != null) {
          final stopPos = toCanvas(stop.store!.latitude, stop.store!.longitude);
          path.lineTo(stopPos.dx, stopPos.dy);
        }
      }
      canvas.drawPath(path, routePaint);
    }

    // 3. Draw Store Geofence Dual-Rings and Pins, to scale (~111 km per
    // degree of latitude) but never smaller than a legible minimum.
    final pxPerMeter = size.height / ((maxLat - minLat) * 111000.0);
    for (final store in stores) {
      final pos = toCanvas(store.latitude, store.longitude);
      final isCurrentStore = activeStore?.id == store.id;
      final innerPx = max(GeofenceEngine.innerRadius(store) * pxPerMeter, 10.0);
      final outerPx = max(GeofenceEngine.outerRadius(store) * pxPerMeter, innerPx + 8);

      // Outer Exit Boundary in amber
      final outerRingPaint = Paint()
        ..color = (isCurrentStore ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8)).withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;
      final outerRingBorder = Paint()
        ..color = (isCurrentStore ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8)).withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(pos, outerPx, outerRingPaint);
      canvas.drawCircle(pos, outerPx, outerRingBorder);

      // Inner Arrival Boundary in emerald
      final innerRingPaint = Paint()
        ..color = (isCurrentStore ? const Color(0xFF10B981) : const Color(0xFF6EE7B7)).withValues(alpha: 0.2)
        ..style = PaintingStyle.fill;
      final innerRingBorder = Paint()
        ..color = (isCurrentStore ? const Color(0xFF10B981) : const Color(0xFF6EE7B7)).withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(pos, innerPx, innerRingPaint);
      canvas.drawCircle(pos, innerPx, innerRingBorder);

      // Store Center Dot
      final storePinPaint = Paint()
        ..color = isCurrentStore ? const Color(0xFF10B981) : const Color(0xFF38BDF8)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 6, storePinPaint);

      // Store Name Label
      final textSpan = TextSpan(
        text: store.name,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(pos.dx - textPainter.width / 2, pos.dy + 8));

      // Stop number overlay if in active route
      if (activeRoute != null) {
        final stopIdx = activeRoute!.stops.indexWhere((s) => s.storeId == store.id);
        if (stopIdx != -1) {
          final stopNumber = stopIdx + 1;
          final badgePaint = Paint()
            ..color = const Color(0xFF6366F1)
            ..style = PaintingStyle.fill;
          final badgePos = Offset(pos.dx + 8, pos.dy - 12);
          canvas.drawCircle(badgePos, 8, badgePaint);

          final numSpan = TextSpan(
            text: '$stopNumber',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          );
          final numPainter = TextPainter(
            text: numSpan,
            textDirection: TextDirection.ltr,
          )..layout();
          numPainter.paint(
            canvas,
            Offset(badgePos.dx - numPainter.width / 2, badgePos.dy - numPainter.height / 2),
          );
        }
      }
    }

    // 4. Draw User Position with Pulse Radar
    final userPos = toCanvas(userLat, userLon);
    final userPulsePaint = Paint()
      ..color = const Color(0xFF6366F1).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(userPos, 18, userPulsePaint);

    final userPaint = Paint()
      ..color = const Color(0xFF6366F1)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(userPos, 7, userPaint);

    final userBorder = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(userPos, 7, userBorder);
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => true;
}
