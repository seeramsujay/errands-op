import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../widgets/route_map_canvas.dart';

class MapViewScreen extends StatelessWidget {
  const MapViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Spatial Radar & Geofence Canvas',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => state.refreshData(),
            tooltip: 'Refresh Map',
          ),
        ],
      ),
      body: Column(
        children: [
          // Legend banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF0F172A),
            child: Wrap(
              alignment: WrapAlignment.spaceAround,
              spacing: 12,
              runSpacing: 4,
              children: [
                _buildLegendItem('User GPS', const Color(0xFF6366F1)),
                _buildLegendItem('Arrival ring', const Color(0xFF10B981)),
                _buildLegendItem('Exit ring', const Color(0xFFF59E0B)),
                _buildLegendItem('Route Polyline', const Color(0xFF818CF8)),
              ],
            ),
          ),

          // Map Canvas
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: RouteMapCanvas(
                userLat: state.userLat,
                userLon: state.userLon,
                stores: state.stores,
                activeRoute: state.activeRoute,
                activeStore: state.activeStore,
              ),
            ),
          ),

          // Controls & Coordinate display
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(top: BorderSide(color: Color(0xFF334155))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.hasLiveFix
                            ? 'Current Fix:'
                            : 'Home (no GPS fix yet):',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white38,
                        ),
                      ),
                      Text(
                        '${state.userLat.toStringAsFixed(4)}, ${state.userLon.toStringAsFixed(4)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    // Simulate moving to the next unfinished stop of the plan.
                    final nextStop = state.activeRoute?.stops
                        .where(
                          (s) =>
                              s.store != null &&
                              s.store!.id != state.activeStore?.id,
                        )
                        .where((s) => s.itemsToPick.any((i) => !i.isCompleted))
                        .firstOrNull;
                    final target = nextStop?.store ?? state.stores.firstOrNull;
                    if (target != null) {
                      await state.simulateDriveToStore(target);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Simulated movement to ${target.name}',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.near_me, size: 16),
                  label: const Text('Move to Next Stop'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white70),
        ),
      ],
    );
  }
}
