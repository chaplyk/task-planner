import 'package:cloud_firestore/cloud_firestore.dart';

import 'collections.dart';

/// The default list: tasks with no list (`list == null`) live here. It always exists.
const inboxName = 'Inbox';

/// Most lists a user can create (the Inbox doesn't count).
const maxLists = 5;

typedef ListDoc = QueryDocumentSnapshot<Map<String, dynamic>>;

/// The user's own lists, oldest first (the Inbox is not stored).
Stream<List<ListDoc>> userListsStream() =>
    listsCollection().orderBy('createdAt').snapshots().map((s) => s.docs);

/// Creates a list. Returns null if the name is empty or already taken, or the
/// user already has [maxLists] lists.
Future<String?> createList(String name, List<String> existing) async {
  if (existing.length >= maxLists) return null;
  final clean = name.trim();
  if (clean.isEmpty) return null;
  final lower = clean.toLowerCase();
  if (lower == inboxName.toLowerCase() || existing.any((e) => e.toLowerCase() == lower)) return null;
  await listsCollection().add({'name': clean, 'createdAt': Timestamp.now()});
  return clean;
}
