import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

import '../collections.dart';
import '../reminders_repo.dart';
import '../widgets/reminder_composer.dart';
import '../widgets/reminder_tile.dart';

typedef _Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  static const _completedLimit = 30;
  bool _showCompleted = false;

  // Rows swiped or ticked away, per list; hidden right away so a Dismissible never lingers in the tree.
  final _hiddenOpen = <String>{};
  final _hiddenDone = <String>{};

  // Groups open reminders into ordered, labelled sections.
  List<(String, List<_Doc>)> _group(List<_Doc> docs) {
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day + 1);
    DateTime? when(_Doc d) => (d.data()['when'] as Timestamp?)?.toDate();

    final overdue = <_Doc>[], today = <_Doc>[], later = <_Doc>[];
    final moving = <_Doc>[], places = <_Doc>[], anytime = <_Doc>[];
    for (final d in docs) {
      final w = when(d);
      switch (d.data()['triggerType']) {
        case 'time' when w != null:
          (w.isBefore(now)
                  ? overdue
                  : w.isBefore(endOfToday)
                  ? today
                  : later)
              .add(d);
        case 'activity':
          moving.add(d);
        case 'location':
          places.add(d);
        default:
          anytime.add(d);
      }
    }
    for (final list in [overdue, today, later]) {
      list.sort((a, b) => when(a)!.compareTo(when(b)!));
    }
    return [
      ('Overdue', overdue),
      ('Today', today),
      ('Upcoming', later),
      ('On the move', moving),
      ('At a place', places),
      ('Anytime', anytime),
    ].where((g) => g.$2.isNotEmpty).toList();
  }

  List<_Doc> _recentCompleted(List<_Doc> docs) {
    DateTime done(_Doc d) =>
        (d.data()['completedAt'] as Timestamp?)?.toDate() ??
        (d.data()['createdAt'] as Timestamp?)?.toDate() ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return (docs.toList()..sort((a, b) => done(b).compareTo(done(a)))).take(_completedLimit).toList();
  }

  // Shows only docs not swiped away, and forgets ids once Firestore confirms they left this list.
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

  void _snack(String text, VoidCallback undo) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Text(text),
          action: SnackBarAction(label: 'Undo', onPressed: undo),
        ),
      );
  }

  Future<void> _complete(_Doc doc) async {
    setState(() => _hiddenOpen.add(doc.id));
    await completeReminder(doc);
    if (mounted) _snack('✅  Done: ${doc.data()['summary']}', () => reopenReminder(doc));
  }

  Future<void> _reopen(_Doc doc) async {
    setState(() => _hiddenDone.add(doc.id));
    await reopenReminder(doc);
    if (mounted) _snack('Reopened: ${doc.data()['summary']}', () => completeReminder(doc));
  }

  Future<void> _delete(_Doc doc, {required bool done}) async {
    setState(() => (done ? _hiddenDone : _hiddenOpen).add(doc.id));
    final data = await deleteReminder(doc);
    if (mounted && data != null) {
      _snack('Deleted: ${data['summary']}', () => restoreReminder(doc.id, data));
    }
  }

  Future<void> _edit(_Doc doc) async {
    final updated = await showReminderComposer(context, initial: reminderFromDoc(doc), title: 'Edit reminder');
    if (updated != null) await updateReminder(doc, updated);
  }

  SliverPadding _list(List<_Doc> items, Map<String, String> emoji, {required bool done}) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final doc = items[i];
          return SwipeableReminder(
            key: ValueKey('swipe-${doc.id}-$done'),
            primaryLabel: done ? 'Reopen' : 'Done',
            primaryIcon: done ? Icons.undo_rounded : Icons.check_rounded,
            onPrimary: () => done ? _reopen(doc) : _complete(doc),
            onDelete: () => _delete(doc, done: done),
            child: ReminderTile(
              data: doc.data(),
              emoji: emoji[doc.data()['category']],
              done: done,
              onTap: () => _edit(doc),
              onToggle: () => done ? _reopen(doc) : _complete(doc),
            ),
          );
        },
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title, int count, {Color? color, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          Text(
            '$title · $count',
            style: theme.textTheme.titleSmall?.copyWith(
              color: color ?? theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: StreamBuilder(
        stream: remindersCollection().where('status', isEqualTo: 0).snapshots(),
        builder: (context, openSnap) {
          return StreamBuilder(
            stream: remindersCollection().where('status', isEqualTo: 1).snapshots(),
            builder: (context, doneSnap) {
              final open = _visible(openSnap, _hiddenOpen);
              final completed = _recentCompleted(_visible(doneSnap, _hiddenDone));
              return StreamBuilder(
                stream: categoryEmojiStream(),
                builder: (context, emojiSnap) {
                  final emoji = emojiSnap.data ?? const {};
                  final groups = _group(open);
                  return CustomScrollView(
                    slivers: [
                      SliverAppBar.large(title: const Text('Reminders'), backgroundColor: theme.colorScheme.surface),
                      if (!openSnap.hasData)
                        const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
                      else ...[
                        if (open.isEmpty)
                          const SliverToBoxAdapter(child: _AllClear())
                        else ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                              child: Text(
                                'Swipe right to complete, left to delete.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                          for (final (title, items) in groups) ...[
                            SliverToBoxAdapter(
                              child: _sectionTitle(
                                theme,
                                title,
                                items.length,
                                color: title == 'Overdue' ? theme.colorScheme.error : null,
                              ),
                            ),
                            _list(items, emoji, done: false),
                          ],
                        ],
                        if (completed.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: _sectionTitle(
                              theme,
                              'Completed',
                              completed.length,
                              color: theme.colorScheme.onSurfaceVariant,
                              trailing: TextButton(
                                onPressed: () => setState(() => _showCompleted = !_showCompleted),
                                child: Text(_showCompleted ? 'Hide' : 'Show'),
                              ),
                            ),
                          ),
                          if (_showCompleted) _list(completed, emoji, done: true),
                        ],
                        const SliverToBoxAdapter(child: SizedBox(height: 32)),
                      ],
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _AllClear extends StatelessWidget {
  const _AllClear();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 16),
      child: Column(
        children: [
          const Text('🌤️', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          Text('All clear', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Nothing to remember right now. Enjoy it.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
