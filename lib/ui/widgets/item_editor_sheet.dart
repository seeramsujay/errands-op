import 'package:flutter/material.dart';

import '../../core/categories.dart';
import '../../data/models/todo_item.dart';

/// Values entered in the item editor.
class ItemDraft {
  final String summary;
  final String? description;
  final String category;
  final bool isPerishable;

  const ItemDraft({
    required this.summary,
    this.description,
    required this.category,
    required this.isPerishable,
  });
}

/// Bottom sheet for adding a new item or editing [existing]. Until the user
/// picks a category by hand, it is guessed from the title as they type.
Future<ItemDraft?> showItemEditorSheet(
  BuildContext context, {
  TodoItem? existing,
}) {
  return showModalBottomSheet<ItemDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0F172A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ItemEditor(existing: existing),
  );
}

class _ItemEditor extends StatefulWidget {
  final TodoItem? existing;
  const _ItemEditor({this.existing});

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late String _category;
  late bool _perishable;
  late bool _categoryChosen;
  bool _perishableChosen = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.summary ?? '');
    _notes = TextEditingController(text: e?.description ?? '');
    _category = e?.category ?? ItemCategories.generic;
    _perishable = e?.isPerishable ?? false;
    _categoryChosen = e != null;
    _perishableChosen = e != null;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _onTitleChanged(String text) {
    if (_categoryChosen) return;
    final guess = ItemCategories.classify(text);
    setState(() {
      _category = guess.id;
      if (!_perishableChosen) _perishable = guess.perishableByDefault;
    });
  }

  void _submit() {
    final summary = _title.text.trim();
    if (summary.isEmpty) return;
    final notes = _notes.text.trim();
    Navigator.pop(
      context,
      ItemDraft(
        summary: summary,
        description: notes.isEmpty ? null : notes,
        category: _category,
        isPerishable: _perishable,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final categories = [
      ...ItemCategories.all,
      if (!ItemCategories.isKnown(_category))
        ItemCategory(_category, _category),
    ];

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEdit ? 'Edit Item' : 'Add Errand / Item',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            autofocus: !isEdit,
            textInputAction: TextInputAction.next,
            onChanged: _onTitleChanged,
            decoration: const InputDecoration(
              hintText: 'What do you need?',
              hintStyle: TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Color(0xFF1E293B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(
              hintText: 'Notes / specifications (optional)',
              hintStyle: TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Color(0xFF1E293B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Category:', style: TextStyle(color: Colors.white70)),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButton<String>(
                  value: _category,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1E293B),
                  items: [
                    for (final c in categories)
                      DropdownMenuItem(value: c.id, child: Text(c.label)),
                  ],
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      _category = val;
                      _categoryChosen = true;
                      if (!_perishableChosen) {
                        _perishable = categories
                            .firstWhere((c) => c.id == val)
                            .perishableByDefault;
                      }
                    });
                  },
                ),
              ),
              if (!_categoryChosen && _title.text.trim().isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text(
                    'auto',
                    style: TextStyle(fontSize: 11, color: Color(0xFF818CF8)),
                  ),
                ),
            ],
          ),
          SwitchListTile(
            title: const Text('Perishable / Thermal Sensitive (Keep Cold)'),
            subtitle: const Text(
              'Route planner keeps it for late in the trip',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
            value: _perishable,
            activeThumbColor: const Color(0xFF06B6D4),
            onChanged: (val) => setState(() {
              _perishable = val;
              _perishableChosen = true;
            }),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _submit,
              child: Text(
                isEdit ? 'Save Changes' : 'Add to Errand List',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
