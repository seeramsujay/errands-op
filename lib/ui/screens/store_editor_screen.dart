import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/categories.dart';
import '../../data/models/store.dart';
import '../../state/app_state.dart';

/// Create or edit a store: location, opening hours, service time and the
/// categories it stocks (which decide what the route planner sends there).
class StoreEditorScreen extends StatefulWidget {
  final Store? store;
  const StoreEditorScreen({super.key, this.store});

  @override
  State<StoreEditorScreen> createState() => _StoreEditorScreenState();
}

class _StoreEditorScreenState extends State<StoreEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _lat;
  late final TextEditingController _lon;
  late final TextEditingController _radius;
  late final TextEditingController _serviceMin;
  late bool _alwaysOpen;
  late TimeOfDay _open;
  late TimeOfDay _close;
  late Set<String> _categories;

  @override
  void initState() {
    super.initState();
    final s = widget.store;
    final state = context.read<AppState>();
    _name = TextEditingController(text: s?.name ?? '');
    _lat = TextEditingController(text: (s?.latitude ?? state.userLat).toStringAsFixed(6));
    _lon = TextEditingController(text: (s?.longitude ?? state.userLon).toStringAsFixed(6));
    _radius = TextEditingController(text: (s?.geofenceRadiusMeters ?? 40).toStringAsFixed(0));
    _serviceMin = TextEditingController(text: ((s?.avgCheckoutDelaySec ?? 600) ~/ 60).toString());
    _alwaysOpen = s?.isAlwaysOpen ?? false;
    _open = _fromSec(s?.openingTimeSec ?? 9 * 3600);
    _close = _fromSec(s?.closingTimeSec ?? 21 * 3600);
    _categories = {...?s?.supportedCategories};
    if (_categories.isEmpty) _categories.add(ItemCategories.generic);
  }

  @override
  void dispose() {
    for (final c in [_name, _lat, _lon, _radius, _serviceMin]) {
      c.dispose();
    }
    super.dispose();
  }

  static TimeOfDay _fromSec(int sec) => TimeOfDay(hour: (sec ~/ 3600) % 24, minute: (sec % 3600) ~/ 60);
  static int _toSec(TimeOfDay t) => t.hour * 3600 + t.minute * 60;

  String? _number(String? v, {double? min, double? max}) {
    final d = double.tryParse((v ?? '').trim());
    if (d == null) return 'Enter a number';
    if (min != null && d < min) return 'Must be at least $min';
    if (max != null && d > max) return 'Must be at most $max';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one category.')),
      );
      return;
    }
    final store = Store(
      id: widget.store?.id ?? 'store_${const Uuid().v4()}',
      name: _name.text.trim(),
      brand: widget.store?.brand,
      latitude: double.parse(_lat.text.trim()),
      longitude: double.parse(_lon.text.trim()),
      geofenceRadiusMeters: double.parse(_radius.text.trim()),
      openingTimeSec: _alwaysOpen ? null : _toSec(_open),
      closingTimeSec: _alwaysOpen ? null : _toSec(_close),
      avgCheckoutDelaySec: (double.parse(_serviceMin.text.trim()) * 60).round(),
      supportedCategories: ItemCategories.all
          .map((c) => c.id)
          .where(_categories.contains)
          .followedBy(_categories.where((c) => !ItemCategories.isKnown(c)))
          .toList(),
    );
    final navigator = Navigator.of(context);
    await context.read<AppState>().saveStore(store);
    navigator.pop();
  }

  Future<void> _delete() async {
    final store = widget.store!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${store.name}?'),
        content: const Text('Its visit history and learned aisle order are deleted too.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final navigator = Navigator.of(context);
    await context.read<AppState>().deleteStore(store.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    const decoration = InputDecoration(
      filled: true,
      fillColor: Color(0xFF1E293B),
      border: OutlineInputBorder(),
      isDense: true,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.store == null ? 'Add Store' : 'Edit Store'),
        actions: [
          if (widget.store != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete store',
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: decoration.copyWith(labelText: 'Name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _lat,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: decoration.copyWith(labelText: 'Latitude'),
                    validator: (v) => _number(v, min: -90, max: 90),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _lon,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: decoration.copyWith(labelText: 'Longitude'),
                    validator: (v) => _number(v, min: -180, max: 180),
                  ),
                ),
              ],
            ),
            if (state.hasLiveFix)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.my_location, size: 18),
                  label: const Text("I'm at this store - use my position"),
                  onPressed: () => setState(() {
                    _lat.text = state.userLat.toStringAsFixed(6);
                    _lon.text = state.userLon.toStringAsFixed(6);
                  }),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _radius,
                    keyboardType: TextInputType.number,
                    decoration: decoration.copyWith(
                      labelText: 'Arrival radius (m)',
                      helperText: 'Exit ring is twice this',
                    ),
                    validator: (v) => _number(v, min: 10, max: 500),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _serviceMin,
                    keyboardType: TextInputType.number,
                    decoration: decoration.copyWith(
                      labelText: 'Time spent (min)',
                      helperText: 'Shopping + queue',
                    ),
                    validator: (v) => _number(v, min: 0, max: 480),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Open 24 hours'),
              value: _alwaysOpen,
              onChanged: (v) => setState(() => _alwaysOpen = v),
            ),
            if (!_alwaysOpen)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(context: context, initialTime: _open);
                        if (t != null) setState(() => _open = t);
                      },
                      child: Text('Opens ${_open.format(context)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await showTimePicker(context: context, initialTime: _close);
                        if (t != null) setState(() => _close = t);
                      },
                      child: Text('Closes ${_close.format(context)}'),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            const Text('Sells / handles', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              '"Generic" means the store can serve any item.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in ItemCategories.all)
                  FilterChip(
                    label: Text(c.label),
                    selected: _categories.contains(c.id),
                    onSelected: (on) => setState(() {
                      on ? _categories.add(c.id) : _categories.remove(c.id);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _save, child: const Text('Save Store')),
          ],
        ),
      ),
    );
  }
}
