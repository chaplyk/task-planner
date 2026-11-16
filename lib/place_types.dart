// Kinds of stores a reminder can target without saving a specific place.
// They are stored as ordinary place reminders whose `location` is the key
// (e.g. 'grocery'); the background service detects them with OpenStreetMap.

class StoreType {
  const StoreType({
    required this.label,
    required this.emoji,
    required this.keywords,
    required this.osmTags,
    required this.aiHint,
  });

  /// "grocery store"
  final String label;
  final String emoji;

  /// Words that identify this kind of store in what the user said.
  final List<String> keywords;

  /// What the AI model should map to this type, e.g. "any supermarket or grocery shop".
  final String aiHint;

  /// OpenStreetMap tags (key -> values) that count as this kind of store.
  final Map<String, List<String>> osmTags;

  /// Whether an OpenStreetMap element with [tags] is this kind of store.
  bool matches(Map<String, dynamic> tags) =>
      osmTags.entries.any((e) => e.value.contains(tags[e.key]));
}

const storeTypes = <String, StoreType>{
  'grocery': StoreType(
    label: 'grocery store',
    emoji: '🛒',
    keywords: ['grocery store', 'grocery', 'groceries', 'supermarket', 'food store', 'market'],
    // "convenience" covers small neighbourhood grocery shops in many countries.
    osmTags: {
      'shop': ['supermarket', 'greengrocer', 'convenience'],
    },
    aiHint: 'any supermarket, grocery or food shop, including store brands',
  ),
  'hardware': StoreType(
    label: 'hardware store',
    emoji: '🔧',
    keywords: ['hardware store', 'hardware', 'diy store', 'home improvement store', 'home improvement'],
    osmTags: {
      'shop': ['hardware', 'doityourself'],
    },
    aiHint: 'any hardware, DIY or home improvement store, including store brands',
  ),
  'pharmacy': StoreType(
    label: 'pharmacy',
    emoji: '💊',
    keywords: ['pharmacy', 'drugstore', 'drug store', 'chemist'],
    osmTags: {
      'amenity': ['pharmacy'],
      'shop': ['chemist'],
    },
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

/// "at the grocery store" / "when I leave the grocery store"
String storeCondition(String key, String? event) {
  final label = storeTypes[key]?.label ?? key;
  return event == 'exit' ? 'when I leave the $label' : 'at the $label';
}
