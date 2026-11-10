import 'package:flutter/material.dart';

import '../../services/geofence_engine.dart';
import '../../data/models/store.dart';

class GeofenceBadge extends StatelessWidget {
  final GeofenceState state;
  final Store? activeStore;
  final int dwellSeconds;

  const GeofenceBadge({
    super.key,
    required this.state,
    this.activeStore,
    this.dwellSeconds = 0,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color border;
    IconData icon;
    String label;

    switch (state) {
      case GeofenceState.outsideStore:
        bg = Colors.white.withValues(alpha: 0.06);
        border = Colors.white.withValues(alpha: 0.15);
        icon = Icons.location_on_outlined;
        label = 'En Route';
        break;
      case GeofenceState.pendingEntry:
        bg = const Color(0xFFF59E0B).withValues(alpha: 0.18);
        border = const Color(0xFFF59E0B);
        icon = Icons.timer_outlined;
        label =
            'Dwell ${dwellSeconds}s / 120s (${activeStore?.name ?? "Store"})';
        break;
      case GeofenceState.insideStore:
        bg = const Color(0xFF10B981).withValues(alpha: 0.2);
        border = const Color(0xFF10B981);
        icon = Icons.storefront;
        label = 'Inside: ${activeStore?.name ?? "Store"}';
        break;
      case GeofenceState.pendingExit:
        bg = const Color(0xFFEF4444).withValues(alpha: 0.18);
        border = const Color(0xFFEF4444);
        icon = Icons.exit_to_app;
        label = 'Exit Grace: 180s (${activeStore?.name ?? "Store"})';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: border),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: border,
            ),
          ),
        ],
      ),
    );
  }
}
