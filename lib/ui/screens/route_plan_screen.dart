import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/models/active_route.dart';
import '../../data/models/route_stop.dart';
import '../../services/vrp_solver.dart';
import '../../state/app_state.dart';
import 'in_store_screen.dart';

class RoutePlanScreen extends StatelessWidget {
  final ActiveRoute route;

  const RoutePlanScreen({super.key, required this.route});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final timeFormat = DateFormat('h:mm a');
    final distKm = (route.totalDistanceMeters / 1000.0).toStringAsFixed(1);
    final durMin = (route.totalDurationSeconds / 60.0).round();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Planned Errand Itinerary',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Route Summary Card
          Card(
            color: const Color(0xFF1E293B),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMetric(
                        label: 'Total Distance',
                        value: '$distKm km',
                        icon: Icons.directions_car,
                        color: const Color(0xFF6366F1),
                      ),
                      _buildMetric(
                        label: 'Est. Duration',
                        value: '$durMin min',
                        icon: Icons.access_time,
                        color: const Color(0xFF14B8A6),
                      ),
                      _buildMetric(
                        label: 'Stops',
                        value: '${route.stops.length}',
                        icon: Icons.store,
                        color: const Color(0xFF06B6D4),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Solver status pill
                  Builder(
                    builder: (context) {
                      final (
                        Color color,
                        String label,
                      ) = switch (route.solverStatus) {
                        SolverStatus.optimal => (
                          const Color(0xFF10B981),
                          'OPTIMAL',
                        ),
                        SolverStatus.feasible => (
                          const Color(0xFF10B981),
                          'GOOD (heuristic)',
                        ),
                        SolverStatus.relaxed => (
                          const Color(0xFFF59E0B),
                          'HOURS CONFLICT',
                        ),
                        _ => (const Color(0xFFF87171), 'NO ROUTE'),
                      };
                      return Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: color),
                            ),
                            child: Text(
                              'STATUS: $label',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Flexible(
                            child: Text(
                              'Hybrid VRPTW Engine · includes trip home',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white38,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Constraint Relaxation Cascade Warnings (if any)
          if (route.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF78350F).withValues(alpha: 0.4),
                border: Border.all(color: const Color(0xFFF59E0B), width: 1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFFBBF24),
                        size: 18,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Heads up',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFBBF24),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final warn in route.warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '• $warn',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          const Text(
            'Route Stops Sequence',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),

          // Stops timeline
          for (var i = 0; i < route.stops.length; i++) ...[
            _buildStopCard(context, state, route.stops[i], i, timeFormat),
            if (i < route.stops.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 4, bottom: 4),
                child: Row(
                  children: [
                    Container(
                      width: 2,
                      height: 20,
                      color: const Color(0xFF334155),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.arrow_downward,
                      size: 14,
                      color: Colors.white24,
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetric({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStopCard(
    BuildContext context,
    AppState state,
    RouteStop stop,
    int index,
    DateFormat timeFormat,
  ) {
    final store = stop.store;
    final arrival = timeFormat.format(stop.estimatedArrival);
    final departure = timeFormat.format(stop.estimatedDeparture);

    return Card(
      color: const Color(0xFF1E293B),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Stop Sequence Circle
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFF6366F1),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${stop.stopSequence}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Store Title
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store?.name ?? 'Store #${stop.stopSequence}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'Arrival: $arrival  •  Depart: $departure',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),

                // Simulation Trigger: Drive to Store
                if (store != null)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                    onPressed: () async {
                      await state.simulateDriveToStore(store);
                      await state.simulateStoreEntry(store);
                      if (!context.mounted) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const InStoreScreen(),
                        ),
                      );
                    },
                    child: const Text("I'm here"),
                  ),
              ],
            ),

            if (stop.warningMessage != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    stop.violatesClosingTime
                        ? Icons.warning_amber_rounded
                        : Icons.schedule,
                    size: 14,
                    color: stop.violatesClosingTime
                        ? const Color(0xFFFBBF24)
                        : Colors.white54,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      stop.warningMessage!,
                      style: TextStyle(
                        fontSize: 12,
                        color: stop.violatesClosingTime
                            ? const Color(0xFFFBBF24)
                            : Colors.white60,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 8),

            // Perishable & Pin Badges for Stop
            Wrap(
              spacing: 6,
              children: [
                if (stop.hasPerishable)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF06B6D4).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '🧊 Perishables picked here',
                      style: TextStyle(fontSize: 11, color: Color(0xFF67E8F9)),
                    ),
                  ),
                if (stop.isUserPinned)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '📌 User Sequence Locked',
                      style: TextStyle(fontSize: 11, color: Color(0xFFFBBF24)),
                    ),
                  ),
              ],
            ),

            if (stop.itemsToPick.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(color: Color(0xFF334155), height: 1),
              const SizedBox(height: 6),
              const Text(
                'Items to Pick:',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white54,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              for (final it in stop.itemsToPick.map(
                (i) =>
                    state.items.where((live) => live.id == i.id).firstOrNull ??
                    i,
              ))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        it.isCompleted
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        size: 14,
                        color: it.isCompleted
                            ? const Color(0xFF14B8A6)
                            : Colors.white38,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          it.summary,
                          style: TextStyle(
                            fontSize: 13,
                            decoration: it.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                            color: it.isCompleted
                                ? Colors.white38
                                : Colors.white,
                          ),
                        ),
                      ),
                      if (it.isPerishable)
                        const Text('  🧊', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
