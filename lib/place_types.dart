// Kinds of stores a reminder can target without saving a specific place.
// They are stored as ordinary place reminders whose `location` is the key
// (e.g. 'grocery'); the background service detects them with Google Places.

class StoreType {
  const StoreType({
    required this.label,
    required this.emoji,
    required this.keywords,
    required this.googleTypes,
  });

  /// "grocery store"
  final String label;
  final String emoji;

  /// Words that identify this kind of store in what the user said.
  final List<String> keywords;

  /// Google Places types that count as this kind of store.
  final Set<String> googleTypes;
}

const storeTypes = <String, StoreType>{
  'grocery': StoreType(
    label: 'grocery store',
    emoji: '🛒',
    keywords: ['grocery store', 'grocery', 'groceries', 'supermarket', 'food store', 'market'],
    googleTypes: {'grocery_store', 'supermarket', 'convenience_store', 'food_store', 'market'},
  ),
  'hardware': StoreType(
    label: 'hardware store',
    emoji: '🔧',
    keywords: ['hardware store', 'hardware', 'diy store', 'home improvement store', 'home improvement'],
    googleTypes: {'hardware_store', 'home_improvement_store'},
  ),
  'pharmacy': StoreType(
    label: 'pharmacy',
    emoji: '💊',
    keywords: ['pharmacy', 'drugstore', 'drug store', 'chemist'],
    googleTypes: {'pharmacy', 'drugstore'},
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

/// "at the grocery store" / "when I leave the grocery store"
String storeCondition(String key, String? event) {
  final label = storeTypes[key]?.label ?? key;
  return event == 'exit' ? 'when I leave the $label' : 'at the $label';
}
