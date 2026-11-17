// Kinds of stores a reminder can target without saving a specific place.
// They are stored as ordinary place reminders whose `location` is the key
// (e.g. 'grocery'); the background service finds them with Geoapify Places.

class StoreType {
  const StoreType({
    required this.label,
    required this.emoji,
    required this.keywords,
    required this.categories,
    required this.aiHint,
  });

  /// "grocery store"
  final String label;
  final String emoji;

  /// Words that identify this kind of store in what the user said.
  final List<String> keywords;

  /// What the AI model should map to this type, e.g. "any supermarket or grocery shop".
  final String aiHint;

  /// Geoapify place categories that count as this kind of store
  /// (https://apidocs.geoapify.com/docs/places/#categories).
  final List<String> categories;

  /// Whether a place with the Geoapify [placeCategories] is this kind of store.
  /// A category also covers its subcategories ('commercial.supermarket.x').
  bool matches(Iterable<String> placeCategories) =>
      placeCategories.any((c) => categories.any((k) => c == k || c.startsWith('$k.')));
}

const storeTypes = <String, StoreType>{
  'grocery': StoreType(
    label: 'grocery store',
    emoji: '🛒',
    keywords: ['grocery store', 'grocery', 'groceries', 'supermarket', 'food store', 'market'],
    // "convenience" covers small neighbourhood grocery shops in many countries.
    categories: [
      'commercial.supermarket',
      'commercial.convenience',
      'commercial.food_and_drink.fruit_and_vegetable',
    ],
    aiHint: 'any supermarket, grocery or food shop, including store brands',
  ),
  'hardware': StoreType(
    label: 'hardware store',
    emoji: '🔧',
    keywords: ['hardware store', 'hardware', 'diy store', 'home improvement store', 'home improvement'],
    categories: [
      'commercial.houseware_and_hardware.doityourself',
      'commercial.houseware_and_hardware.hardware_and_tools',
    ],
    aiHint: 'any hardware, DIY or home improvement store, including store brands',
  ),
  'pharmacy': StoreType(
    label: 'pharmacy',
    emoji: '💊',
    keywords: ['pharmacy', 'drugstore', 'drug store', 'chemist'],
    categories: [
      'healthcare.pharmacy',
      'commercial.health_and_beauty.pharmacy',
      'commercial.chemist',
    ],
    aiHint: 'any pharmacy or drugstore, including store brands',
  ),
};

bool isStoreType(String? location) => location != null && storeTypes.containsKey(location);

/// Maps what the user or AI called a place ("Grocery store", "the supermarket")
/// to a store type key, or null if it isn't one of them.
String? storeTypeFor(String placeName) {
  final s = placeName.toLowerCase().trim().replaceFirst(RegExp(r'^(the|a|an)\s+'), '');
  if (storeTypes.containsKey(s)) return s;
  for (final MapEntry(:key, :value) in storeTypes.entries) {
    if (value.keywords.any((k) => RegExp(r'\b' + RegExp.escape(k) + r'\b').hasMatch(s))) return key;
  }
  return null;
}

/// "at the grocery store". Nearby categories only support arriving: leaving can't be
/// detected reliably (the store's geofence may be gone by then).
String storeCondition(String key) => 'at the ${storeTypes[key]?.label ?? key}';
