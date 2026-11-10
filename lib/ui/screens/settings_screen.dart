import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/store.dart';
import '../../data/sync/ha_websocket_client.dart';
import '../../services/location_service.dart';
import '../../state/app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  final _entityController = TextEditingController();
  final _homeLatController = TextEditingController();
  final _homeLonController = TextEditingController();
  final _routingController = TextEditingController();
  final _remoteItemController = TextEditingController(
    text: 'Organic Unsalted Butter',
  );
  String? _simStoreId;
  bool _loaded = false;

  /// Fill the form once the app state has loaded the saved settings.
  void _loadFrom(AppState state) {
    if (!_loaded && state.initialized) {
      _loaded = true;
      _urlController.text = state.haClient.baseUrl;
      _entityController.text = state.haClient.entityId;
      _homeLatController.text = state.homeLat.toStringAsFixed(6);
      _homeLonController.text = state.homeLon.toStringAsFixed(6);
      _routingController.text = state.routingServer ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [
      _urlController,
      _tokenController,
      _entityController,
      _homeLatController,
      _homeLonController,
      _routingController,
      _remoteItemController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  InputDecoration _field(String label, {String? hint, String? helper}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        filled: true,
        fillColor: const Color(0xFF0F172A),
        border: const OutlineInputBorder(),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _loadFrom(state);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings & Simulation',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHaCard(state),
          const SizedBox(height: 16),
          _buildLocationCard(state),
          const SizedBox(height: 16),
          _buildRoutingCard(state),
          const SizedBox(height: 16),
          _buildSimulationSection(state),
        ],
      ),
    );
  }

  Widget _buildHaCard(AppState state) {
    final hasToken = state.haClient.hasToken;
    return Card(
      color: const Color(0xFF1E293B),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Flexible(
                  child: Text(
                    'Home Assistant Integration',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                _buildHaBadge(state.haState),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Two-way sync with a Home Assistant to-do list over /api/websocket. Edits made '
              'offline are queued and sent when the connection is back.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
            if (state.haState == HaConnectionState.error &&
                state.haError != null) ...[
              const SizedBox(height: 8),
              Text(
                state.haError!,
                style: const TextStyle(fontSize: 12, color: Color(0xFFF87171)),
              ),
            ],
            if (state.failedSyncCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${state.failedSyncCount} change(s) could not be sent to Home Assistant after retrying.',
                style: const TextStyle(fontSize: 12, color: Color(0xFFFBBF24)),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              decoration: _field(
                'Home Assistant URL',
                hint: 'http://homeassistant.local:8123',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tokenController,
              obscureText: true,
              decoration: _field(
                'Long-Lived Access Token',
                hint: hasToken ? 'Saved - leave blank to keep it' : null,
                helper:
                    'Create one in Home Assistant under Profile > Security.',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _entityController,
              decoration: _field('To-Do Entity ID', hint: 'todo.shopping_list'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Save & Connect'),
                  onPressed: () async {
                    if (_urlController.text.trim().isEmpty ||
                        (!hasToken && _tokenController.text.trim().isEmpty)) {
                      _toast(
                        'Enter the Home Assistant URL and an access token.',
                      );
                      return;
                    }
                    await state.saveHaSettings(
                      url: _urlController.text,
                      token: _tokenController.text,
                      entityId: _entityController.text,
                    );
                    _tokenController.clear();
                  },
                ),
                if (state.haState == HaConnectionState.connected ||
                    state.haState == HaConnectionState.connecting ||
                    state.haState == HaConnectionState.error)
                  OutlinedButton(
                    onPressed: state.disconnectHa,
                    child: const Text('Disconnect'),
                  ),
                if (state.haClient.isConfigured)
                  TextButton(
                    onPressed: () async {
                      await state.forgetHa();
                      _tokenController.clear();
                      _urlController.clear();
                    },
                    child: const Text('Forget'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard(AppState state) {
    return Card(
      color: const Color(0xFF1E293B),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Location',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Live GPS'),
              subtitle: const Text(
                'Detects store arrival/exit and plans routes from where you are.',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
              value: state.gpsTracking,
              onChanged: (on) async {
                if (!on) {
                  await state.stopGpsTracking();
                  return;
                }
                final result = await state.startGpsTracking();
                if (!mounted) return;
                switch (result) {
                  case LocationStartResult.started:
                    break;
                  case LocationStartResult.serviceDisabled:
                    _toast('Location services are turned off.');
                  case LocationStartResult.permissionDenied:
                    _toast('Location permission was denied.');
                  case LocationStartResult.unsupported:
                    _toast(
                      'Live GPS is not available on this platform. Use the simulator below.',
                    );
                }
              },
            ),
            const SizedBox(height: 4),
            Text(
              state.homeIsSet
                  ? 'Home (route start & end when there is no GPS fix):'
                  : 'Home is not set yet; routes start from a default point in Bangalore.',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _homeLatController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: _field('Latitude'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _homeLonController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: _field('Longitude'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    final lat = double.tryParse(_homeLatController.text.trim());
                    final lon = double.tryParse(_homeLonController.text.trim());
                    if (lat == null ||
                        lon == null ||
                        lat.abs() > 90 ||
                        lon.abs() > 180) {
                      _toast('Enter a valid latitude and longitude.');
                      return;
                    }
                    await state.setHomeLocation(lat, lon);
                    if (mounted) _toast('Home location saved.');
                  },
                  child: const Text('Save Home'),
                ),
                if (state.hasLiveFix)
                  TextButton(
                    onPressed: () async {
                      await state.setHomeLocation(state.userLat, state.userLon);
                      _homeLatController.text = state.homeLat.toStringAsFixed(
                        6,
                      );
                      _homeLonController.text = state.homeLon.toStringAsFixed(
                        6,
                      );
                    },
                    child: const Text('Use current position'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoutingCard(AppState state) {
    return Card(
      color: const Color(0xFF1E293B),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Road Routing Server (optional)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'An OSRM-compatible server gives real road travel times (cached for 7 days). '
              'Without one, straight-line distance x 1.28 at ~40 km/h is used.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _routingController,
              keyboardType: TextInputType.url,
              decoration: _field(
                'OSRM URL',
                hint: 'http://router.project-osrm.org',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                await state.setRoutingServer(_routingController.text);
                if (mounted) _toast('Routing server saved.');
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimulationSection(AppState state) {
    final stores = state.stores;
    Store? simStore;
    for (final s in stores) {
      if (s.id == _simStoreId) simStore = s;
    }
    simStore ??= stores.isNotEmpty ? stores.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Interactive Simulation Sandbox',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Simulate field GPS events, geofence hysteresis transitions, and remote Home Assistant edits.',
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFF1E293B),
          child: Column(
            children: [
              if (simStore != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      const Text(
                        'Store:',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButton<String>(
                          value: simStore.id,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E293B),
                          items: [
                            for (final s in stores)
                              DropdownMenuItem(
                                value: s.id,
                                child: Text(s.name),
                              ),
                          ],
                          onChanged: (id) => setState(() => _simStoreId = id),
                        ),
                      ),
                    ],
                  ),
                ),
              ListTile(
                enabled: simStore != null,
                leading: const Icon(Icons.drive_eta, color: Color(0xFF6366F1)),
                title: const Text('Simulate GPS fix at the store'),
                subtitle: const Text(
                  'Inside the arrival ring: starts the 120 s dwell timer',
                ),
                trailing: const Icon(
                  Icons.play_arrow,
                  color: Color(0xFF6366F1),
                ),
                onTap: () async {
                  await state.simulateDriveToStore(simStore!);
                  if (mounted) _toast('GPS fix placed at ${simStore!.name}.');
                },
              ),
              const Divider(height: 1, color: Color(0xFF334155)),
              ListTile(
                enabled: simStore != null,
                leading: const Icon(Icons.store, color: Color(0xFF10B981)),
                title: const Text('Skip dwell: enter store now'),
                subtitle: const Text(
                  'Transitions to INSIDE_STORE & starts In-Store Mode',
                ),
                trailing: const Icon(
                  Icons.play_arrow,
                  color: Color(0xFF10B981),
                ),
                onTap: () async {
                  await state.simulateStoreEntry(simStore!);
                  if (mounted) _toast('Entered ${simStore!.name}.');
                },
              ),
              const Divider(height: 1, color: Color(0xFF334155)),
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.redAccent),
                title: const Text('Leave store now'),
                subtitle: const Text(
                  'Completes the visit & updates the learned aisle order',
                ),
                trailing: const Icon(Icons.play_arrow, color: Colors.redAccent),
                onTap: () async {
                  await state.simulateStoreExit();
                  if (mounted) _toast('Visit closed; layout graph updated.');
                },
              ),
              const Divider(height: 1, color: Color(0xFF334155)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _remoteItemController,
                  decoration: _field('Remote item text'),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.cloud_download,
                  color: Color(0xFF06B6D4),
                ),
                title: const Text('Simulate item added in Home Assistant'),
                subtitle: const Text(
                  'Category & perishability are guessed from the text',
                ),
                trailing: const Icon(
                  Icons.play_arrow,
                  color: Color(0xFF06B6D4),
                ),
                onTap: () async {
                  final text = _remoteItemController.text.trim();
                  if (text.isEmpty) return;
                  await state.simulateHaItemAdd(text);
                  if (mounted) _toast('"$text" arrived from Home Assistant.');
                },
              ),
              const Divider(height: 1, color: Color(0xFF334155)),
              ListTile(
                leading: const Icon(Icons.restart_alt, color: Colors.white60),
                title: const Text('Reset Sample Database'),
                subtitle: const Text(
                  'Restore default stores, items and DAG edges (keeps settings)',
                ),
                trailing: const Icon(Icons.refresh, color: Colors.white60),
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Reset all data?'),
                      content: const Text(
                        'Items, stores, visits and everything learned will be replaced by the sample data.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  await state.simulateResetData();
                  if (mounted) _toast('Sample data restored.');
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHaBadge(HaConnectionState state) {
    final (Color color, String label) = switch (state) {
      HaConnectionState.connected => (const Color(0xFF10B981), 'Connected'),
      HaConnectionState.connecting || HaConnectionState.authenticating => (
        const Color(0xFFF59E0B),
        'Connecting',
      ),
      HaConnectionState.error => (const Color(0xFFF87171), 'Error'),
      HaConnectionState.notConfigured => (
        const Color(0xFF94A3B8),
        'Not set up',
      ),
      HaConnectionState.disconnected => (Colors.grey, 'Offline'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
