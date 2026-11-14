/// Shared item category catalog used by the item editor, the store editor and
/// the keyword classifier for items that arrive from Home Assistant (voice
/// assistants and HA dashboards only send a free-text summary).
class ItemCategory {
  final String id;
  final String label;
  final bool perishableByDefault;
  final List<String> keywords;

  const ItemCategory(
    this.id,
    this.label, {
    this.perishableByDefault = false,
    this.keywords = const [],
  });
}

class ItemCategories {
  static const String generic = 'generic';

  // Order matters for classification: earlier categories win ties, so the
  // more specific ones (frozen before dairy, e.g. "ice cream") come first.
  static const List<ItemCategory> all = [
    ItemCategory(
      'frozen',
      'Frozen Foods',
      perishableByDefault: true,
      keywords: [
        'ice cream',
        'gelato',
        'frozen',
        'popsicle',
        'ice',
        'kulfi',
        'sorbet',
        'peas frozen',
        'fries',
      ],
    ),
    ItemCategory(
      'dairy',
      'Dairy',
      perishableByDefault: true,
      keywords: [
        'milk',
        'yogurt',
        'yoghurt',
        'curd',
        'cheese',
        'butter',
        'paneer',
        'cream',
        'ghee',
        'dahi',
        'buttermilk',
      ],
    ),
    ItemCategory(
      'produce',
      'Fresh Produce',
      keywords: [
        'apple',
        'banana',
        'tomato',
        'onion',
        'potato',
        'spinach',
        'lettuce',
        'carrot',
        'fruit',
        'vegetable',
        'veggies',
        'lemon',
        'garlic',
        'ginger',
        'coriander',
        'mango',
        'grapes',
        'cucumber',
      ],
    ),
    ItemCategory(
      'bakery',
      'Bakery',
      keywords: ['bread', 'bun', 'cake', 'croissant', 'bagel', 'muffin', 'pav'],
    ),
    ItemCategory(
      'pharmacy',
      'Pharmacy',
      keywords: [
        'medicine',
        'tablet',
        'paracetamol',
        'vitamin',
        'prescription',
        'syrup',
        'bandage',
        'antiseptic',
        'ointment',
        'pharmacy',
      ],
    ),
    ItemCategory(
      'personal_care',
      'Personal Care',
      keywords: [
        'shampoo',
        'soap',
        'toothpaste',
        'toothbrush',
        'deodorant',
        'razor',
        'conditioner',
        'lotion',
        'sanitary',
      ],
    ),
    ItemCategory(
      'hardware',
      'Hardware',
      keywords: [
        'screw',
        'nail',
        'drill',
        'hammer',
        'wrench',
        'bulb',
        'tape',
        'glue',
        'wire',
        'cable',
        'battery',
        'batteries',
        'paint',
        'hex key',
        'plug',
      ],
    ),
    ItemCategory(
      'admin_errand',
      'Admin / Documents',
      keywords: [
        'passport',
        'license',
        'licence',
        'rto',
        'bank',
        'post office',
        'attestation',
        'notary',
        'aadhaar',
        'pan card',
        'document',
        'courier',
      ],
    ),
    ItemCategory(
      'snacks',
      'Snacks',
      keywords: ['chips', 'biscuit', 'cookie', 'chocolate', 'namkeen', 'snack'],
    ),
    ItemCategory(
      'groceries',
      'Groceries',
      keywords: [
        'rice',
        'flour',
        'atta',
        'sugar',
        'salt',
        'oil',
        'dal',
        'lentil',
        'pasta',
        'cereal',
        'coffee',
        'tea',
        'spice',
        'eggs',
        'egg',
      ],
    ),
    ItemCategory('organic', 'Organic'),
    ItemCategory('health', 'Health'),
    ItemCategory('tools', 'Tools'),
    ItemCategory('cables', 'Cables & Electronics'),
    ItemCategory('documents', 'Documents'),
    ItemCategory(generic, 'Generic'),
  ];

  static final Map<String, ItemCategory> _byId = {for (final c in all) c.id: c};

  static String labelFor(String id) => _byId[id]?.label ?? id;

  static bool isKnown(String id) => _byId.containsKey(id);

  /// Best-effort category guess from free text. Matches whole words (or
  /// multi-word phrases) so "creamer" does not become dairy via "cream".
  static ItemCategory classify(String text) {
    final normalized =
        ' ${text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')} '
            .replaceAll(RegExp(r'\s+'), ' ');
    for (final category in all) {
      for (final keyword in category.keywords) {
        if (normalized.contains(' $keyword ') ||
            normalized.contains(' ${keyword}s ') ||
            normalized.contains(' ${keyword}es ')) {
          return category;
        }
      }
    }
    return _byId[generic]!;
  }
}
