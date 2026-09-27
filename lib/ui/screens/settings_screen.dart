import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/sync/ha_websocket_client.dart';
import '../../state/app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _hostController = TextEditingController(text: '127.0.0.1');
  final _portController = TextEditingController(text: '8123');
  final _tokenController = TextEditingController();
  final _entityController = TextEditingController(text: 'todo.shopping_list');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Simulation', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Home Assistant Connection Card
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
                      const Text(
                        'Home Assistant Integration',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      _buildHaBadge(state.haState),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Bi-directional sync over /api/websocket subscribing to the todo domain with HLC/LWW conflict resolution.',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _hostController,
                          decoration: const InputDecoration(
                            labelText: 'Host / IP',
                            filled: true,
                            fillColor: Color(0xFF0F172A),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: _portController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Port',
                            filled: true,
                            fillColor: Color(0xFF0F172A),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _tokenController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Long-Lived Access Token',
                      filled: true,
                      fillColor: Color(0xFF0F172A),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _entityController,
                    decoration: const InputDecoration(
                      labelText: 'To-Do Entity ID',
                      filled: true,
                      fillColor: Color(0xFF0F172A),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Simulation Sandbox
          const Text(
            'Interactive Simulation Sandbox',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          const Text(
            'Simulate field GPS events, geofence hysteresis transitions, and remote Home Assistant mutations instantly.',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 12),

          // Simulation Buttons
          Card(
            color: const Color(0xFF1E293B),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.drive_eta, color: Color(0xFF6366F1)),
                  title: const Text('Simulate Drive to DMart (Inner 40m)'),
                  subtitle: const Text('Triggers PENDING_ENTRY & starts 120s dwell timer'),
                  trailing: const Icon(Icons.play_arrow, color: Color(0xFF6366F1)),
                  onTap: () async {
                    final dmart = state.stores.firstWhere((s) => s.id == 'store_dmart');
                    await state.simulateDriveToStore(dmart);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Simulated GPS fix inside DMart 40m arrival radius!')),
                      );
                    }
                  },
                ),
                const Divider(height: 1, color: Color(0xFF334155)),
                ListTile(
                  leading: const Icon(Icons.store, color: Color(0xFF10B981)),
                  title: const Text('Simulate 120s Dwell Complete (Enter Store)'),
                  subtitle: const Text('Transitions to INSIDE_STORE & triggers In-Store Mode'),
                  trailing: const Icon(Icons.play_arrow, color: Color(0xFF10B981)),
                  onTap: () async {
                    final dmart = state.stores.firstWhere((s) => s.id == 'store_dmart');
                    await state.simulateStoreEntry(dmart);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Entered DMart! In-Store shopping mode activated.')),
                      );
                    }
                  },
                ),
                const Divider(height: 1, color: Color(0xFF334155)),
                ListTile(
                  leading: const Icon(Icons.exit_to_app, color: Colors.redAccent),
                  title: const Text('Simulate Store Exit (Outer 80m + Grace)'),
                  subtitle: const Text('Completes visit & triggers Kahn/FAS layout learning'),
                  trailing: const Icon(Icons.play_arrow, color: Colors.redAccent),
                  onTap: () async {
                    await state.simulateStoreExit();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Exited store. Layout DAG graph updated!')),
                      );
                    }
                  },
                ),
                const Divider(height: 1, color: Color(0xFF334155)),
                ListTile(
                  leading: const Icon(Icons.cloud_download, color: Color(0xFF06B6D4)),
                  title: const Text('Simulate Incoming Remote HA Item'),
                  subtitle: const Text('Simulates family member adding "Organic Butter" remotely'),
                  trailing: const Icon(Icons.play_arrow, color: Color(0xFF06B6D4)),
                  onTap: () {
                    state.simulateHaItemAdd(
                      'Organic Unsalted Butter',
                      category: 'dairy',
                      isPerishable: true,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Remote item "Organic Unsalted Butter" synced via HA!')),
                    );
                  },
                ),
                const Divider(height: 1, color: Color(0xFF334155)),
                ListTile(
                  leading: const Icon(Icons.restart_alt, color: Colors.white60),
                  title: const Text('Reset Sample Database'),
                  subtitle: const Text('Restore default stores, items, and DAG edges'),
                  trailing: const Icon(Icons.refresh, color: Colors.white60),
                  onTap: () async {
                    await state.simulateResetData();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sample data reset successfully!')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHaBadge(HaConnectionState state) {
    Color color = Colors.grey;
    String label = 'Offline';

    if (state == HaConnectionState.connected) {
      color = const Color(0xFF10B981);
      label = 'Connected';
    } else if (state == HaConnectionState.mockConnected) {
      color = const Color(0xFF06B6D4);
      label = 'Mock Server';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
