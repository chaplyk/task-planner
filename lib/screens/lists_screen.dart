import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

import '../collections.dart';
import '../lists.dart';
import '../models/reminder.dart';
import '../permissions.dart';
import '../reminders_repo.dart';
import '../widgets/reminder_composer.dart';
import '../widgets/reminder_tile.dart';
import '../widgets/text_input_dialog.dart';

typedef _Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

/// Lists tab: list names as tabs (Inbox first), swipe between lists,
/// each with a collapsible To-do and Done section.
class ListsScreen extends StatefulWidget {
  const ListsScreen({super.key});

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  static const _doneLimit = 30;

  final _pages = PageController();
  final _tabKeys = <String, GlobalKey>{};
  int _page = 0;
  bool _todoOpen = true;
  bool _doneOpen = true;
  bool _askedNotifications = false;

  // Rows swiped or ticked away, per section; hidden right away so a Dismissible never lingers in the tree.
  final _hiddenOpen = <String>{};
  final _hiddenDone = <String>{};

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- data helpers

  List<_Doc> _visible(AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap, Set<String> hidden) {
    final docs = snap.data?.docs ?? <_Doc>[];
    if (snap.hasData) {
      final ids = {for (final d in docs) d.id};
      hidden.removeWhere((id) => !ids.contains(id));
    }
    return [
      for (final d in docs)
        if (!hidden.contains(d.id)) d,
    ];
  }

  /// Tasks of one list. The Inbox also collects tasks whose list no longer exists.
  List<_Doc> _inList(List<_Doc> docs, String? list, Set<String> userLists) => [
    for (final d in docs)
      if (list == null ? !userLists.contains(d.data()['list']) : d.data()['list'] == list) d,
  ];

  List<_Doc> _sortOpen(List<_Doc> docs) {
    DateTime? when(_Doc d) => d.data()['triggerType'] == 'time' ? (d.data()['when'] as Timestamp?)?.toDate() : null;
    DateTime created(_Doc d) =>
        (d.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
    return docs.toList()..sort((a, b) {
      final wa = when(a), wb = when(b);
      if (wa != null && wb != null) return wa.compareTo(wb);
      if (wa != null) return -1;
      if (wb != null) return 1;
      return created(b).compareTo(created(a));
    });
  }

  List<_Doc> _sortDone(List<_Doc> docs) {
    DateTime done(_Doc d) =>
        (d.data()['completedAt'] as Timestamp?)?.toDate() ??
        (d.data()['createdAt'] as Timestamp?)?.toDate() ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return (docs.toList()..sort((a, b) => done(b).compareTo(done(a)))).take(_doneLimit).toList();
  }

  // ---------------------------------------------------------------- actions

  void _snack(String text, {VoidCallback? undo}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Text(text),
          action: undo == null ? null : SnackBarAction(label: 'Undo', onPressed: undo),
        ),
      );
  }

  Future<void> _complete(_Doc doc) async {
    setState(() => _hiddenOpen.add(doc.id));
    await completeReminder(doc);
    if (mounted) _snack('Done: ${doc.data()['summary']}', undo: () => reopenReminder(doc));
  }

  Future<void> _reopen(_Doc doc) async {
    setState(() => _hiddenDone.add(doc.id));
    await reopenReminder(doc);
    if (mounted) _snack('Reopened: ${doc.data()['summary']}', undo: () => completeReminder(doc));
  }

  Future<void> _delete(_Doc doc, {required bool done}) async {
    setState(() => (done ? _hiddenDone : _hiddenOpen).add(doc.id));
    final data = await deleteReminder(doc);
    if (mounted && data != null) _snack('Deleted: ${data['summary']}', undo: () => restoreReminder(doc.id, data));
  }

  Future<void> _edit(_Doc doc) async {
    final updated = await showReminderComposer(context, initial: reminderFromDoc(doc), title: 'Edit task');
    if (updated == null) return;
    await updateReminder(doc, updated);
    if (mounted) await _prepare(updated);
  }

  Future<void> _addTask(String? list) async {
    final reminder = await showReminderComposer(context, title: 'New task', list: list);
    if (reminder == null) return;
    await saveReminder(reminder);
    if (!mounted) return;
    _snack('Added to ${reminder.list ?? inboxName}');
    await _prepare(reminder);
  }

  /// A reminder with a trigger only fires with its permission, the background
  /// service and notifications in place, same as one created on the Home tab.
  Future<void> _prepare(Reminder reminder) async {
    if (reminder.triggerType == 'none') return;
    await prepareTrigger(context, reminder);
    if (!mounted || _askedNotifications) return;
    _askedNotifications = true;
    await primeNotifications(context);
  }

  Future<String?> _askName({required String title, String initial = '', required String action}) =>
      showTextInputDialog(
        context,
        title: title,
        action: action,
        initial: initial,
        hintText: 'e.g. Trip to Rome, Shopping',
        filledAction: true,
      );

  Future<void> _newList(List<String> existing) async {
    if (existing.length >= maxLists) {
      _snack('You can only have up to $maxLists lists');
      return;
    }
    final name = await _askName(title: 'New list', action: 'Create');
    if (name == null || name.trim().isEmpty) return;
    final created = await createList(name, existing);
    if (!mounted) return;
    if (created == null) {
      _snack('A list called "${name.trim()}" already exists');
      return;
    }
    // Jump to the new list once it arrives from Firestore (it is added last).
    WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(existing.length + 1));
  }

  Future<void> _manageList(ListDoc list, List<String> existing) async {
    final name = list.data()['name'] as String;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename list'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: Text('Delete list', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              subtitle: const Text('Its tasks move to $inboxName'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'rename') {
      final newName = (await _askName(title: 'Rename list', initial: name, action: 'Save'))?.trim();
      if (newName == null || newName.isEmpty || newName == name) return;
      final lower = newName.toLowerCase();
      if (lower == inboxName.toLowerCase() || existing.any((e) => e != name && e.toLowerCase() == lower)) {
        _snack('A list called "$newName" already exists');
        return;
      }
      await renameList(list.id, name, newName);
    } else if (action == 'delete') {
      await deleteList(list.id, name);
      _goTo(0);
      if (mounted) _snack('Deleted "$name". Its tasks moved to $inboxName');
    }
  }

  void _goTo(int page) {
    if (!_pages.hasClients) return;
    _pages.animateToPage(page, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  void _onPageChanged(int page, List<String?> names) {
    setState(() => _page = page);
    final key = _tabKeys[names[page] ?? inboxName];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.3, duration: const Duration(milliseconds: 250));
    }
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: StreamBuilder<List<ListDoc>>(
          stream: userListsStream(),
          builder: (context, listsSnap) {
            final userLists = listsSnap.data ?? const <ListDoc>[];
            final listNames = [for (final l in userLists) l.data()['name'] as String];
            final pages = <String?>[null, ...listNames]; // null = Inbox
            if (_page >= pages.length) _page = pages.length - 1;

            return StreamBuilder(
              stream: remindersCollection().where('status', isEqualTo: 0).snapshots(),
              builder: (context, openSnap) => StreamBuilder(
                stream: remindersCollection().where('status', isEqualTo: 1).snapshots(),
                builder: (context, doneSnap) {
                  final open = _visible(openSnap, _hiddenOpen);
                  final done = _visible(doneSnap, _hiddenDone);
                  final userSet = listNames.toSet();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _tabs(theme, pages, userLists, listNames, open, userSet),
                      Divider(height: 1, color: theme.colorScheme.outlineVariant),
                      Expanded(
                        child: PageView.builder(
                          controller: _pages,
                          itemCount: pages.length,
                          onPageChanged: (p) => _onPageChanged(p, pages),
                          itemBuilder: (context, i) => _listPage(
                            theme,
                            pages[i],
                            _sortOpen(_inList(open, pages[i], userSet)),
                            _sortDone(_inList(done, pages[i], userSet)),
                            loading: !openSnap.hasData,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _tabs(
    ThemeData theme,
    List<String?> pages,
    List<ListDoc> userLists,
    List<String> listNames,
    List<_Doc> open,
    Set<String> userSet,
  ) {
    final scheme = theme.colorScheme;
    return SizedBox(
      height: 72,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < pages.length; i++)
              _tab(
                theme,
                label: pages[i] ?? inboxName,
                selected: i == _page,
                onTap: () => _goTo(i),
                onLongPress: i == 0 ? null : () => _manageList(userLists[i - 1], listNames),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: TextButton.icon(
                onPressed: () => _newList(listNames),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New list'),
                style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(
    ThemeData theme, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    final key = _tabKeys.putIfAbsent(label, GlobalKey.new);
    final style = selected
        ? theme.textTheme.headlineMedium?.copyWith(color: theme.colorScheme.onSurface)
        : theme.textTheme.titleLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            fontWeight: FontWeight.w500,
          );
    return InkWell(
      key: key,
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: style ?? const TextStyle(),
          child: Text(label),
        ),
      ),
    );
  }

  Widget _listPage(ThemeData theme, String? list, List<_Doc> open, List<_Doc> done, {required bool loading}) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            _sectionPill(theme, 'TO-DO (${open.length})', _todoOpen, () => setState(() => _todoOpen = !_todoOpen)),
            const Spacer(),
            IconButton.filledTonal(
              tooltip: 'Add task to ${list ?? inboxName}',
              onPressed: () => _addTask(list),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_todoOpen) ...[
          if (open.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  done.isEmpty ? 'Nothing here yet. Tap + to add a task.' : 'All done here.',
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          for (final doc in open) _row(doc, done: false),
        ],
        if (done.isNotEmpty) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: _sectionPill(theme, 'DONE (${done.length})', _doneOpen, () => setState(() => _doneOpen = !_doneOpen)),
          ),
          const SizedBox(height: 10),
          if (_doneOpen)
            for (final doc in done) _row(doc, done: true),
        ],
      ],
    );
  }

  Widget _row(_Doc doc, {required bool done}) {
    return Padding(
      key: ValueKey('${doc.id}-$done'),
      padding: const EdgeInsets.only(bottom: 10),
      child: SwipeableReminder(
        key: ValueKey('swipe-${doc.id}-$done'),
        primaryLabel: done ? 'Reopen' : 'Done',
        primaryIcon: done ? Icons.undo_rounded : Icons.check_rounded,
        onPrimary: () => done ? _reopen(doc) : _complete(doc),
        onDelete: () => _delete(doc, done: done),
        child: ReminderTile(
          data: doc.data(),
          done: done,
          onTap: () => _edit(doc),
          onClearNotified: () => clearNotified(doc),
          onToggle: () => done ? _reopen(doc) : _complete(doc),
        ),
      ),
    );
  }

  Widget _sectionPill(ThemeData theme, String label, bool open, VoidCallback onTap) {
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: theme.textTheme.labelLarge?.copyWith(letterSpacing: 0.8)),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: open ? 0 : -0.25,
                duration: const Duration(milliseconds: 150),
                child: const Icon(Icons.expand_more_rounded, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
