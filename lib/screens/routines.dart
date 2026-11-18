import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:material_ui/material_ui.dart';

import '../collections.dart';
import '../models/recurrence.dart';
import '../permissions.dart';
import '../recurring_repo.dart';
import '../widgets/routine_card.dart';
import '../widgets/routine_history_sheet.dart';
import '../widgets/routine_sheet.dart';


void _snack(BuildContext context, String text, {VoidCallback? onUndo}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Text(text),
        persist: false, // with an action it would otherwise stay until dismissed
        action: onUndo == null ? null : SnackBarAction(label: 'Undo', onPressed: onUndo),
      ),
    );
}

/// Marks a routine's cycle done, with Undo.
Future<void> markRoutineDone(BuildContext context, RoutineDoc doc) async {
  final r = Routine(doc.id, doc.data() ?? const {});
  final previous = await completeRecurring(doc);
  FirebaseAnalytics.instance.logEvent(name: 'routine_done');
  if (!context.mounted) return;
  final next = r.recurrence.nextDueAfterDone(prevDue: r.nextDue, doneAt: DateTime.now());
  _snack(context, '✅  ${r.name} · ${dueLabel(DateTime.now(), next)}', onUndo: () => undoMove(doc, previous));
}

/// Skips a routine's current cycle, with Undo.
Future<void> skipRoutine(BuildContext context, RoutineDoc doc) async {
  final r = Routine(doc.id, doc.data() ?? const {});
  final previous = await skipRecurring(doc);
  if (!context.mounted) return;
  _snack(context, '⏭️  Skipped: ${r.name}', onUndo: () => undoMove(doc, previous));
}

Future<void> deleteRoutine(BuildContext context, RoutineDoc doc) async {
  final data = await deleteRecurring(doc);
  if (!context.mounted || data == null) return;
  _snack(context, 'Deleted: ${data['name']}', onUndo: () => restoreRecurring(doc.id, data));
}

Future<void> editRoutine(BuildContext context, RoutineDoc doc) async {
  final r = Routine(doc.id, doc.data() ?? const {});
  final draft = await showRoutineSheet(context, initial: r);
  if (draft == null) return;
  await updateRecurring(
    doc,
    name: draft.name,
    emoji: draft.emoji ?? r.emoji,
    recurrence: draft.recurrence,
    nextDue: draft.nextDue,
  );
}

/// Creates a routine from the sheet (optionally prefilled), asking for notification access the first time.
Future<String?> addRoutine(BuildContext context, {String? name, Recurrence? recurrence}) async {
  final draft = await showRoutineSheet(context, name: name, recurrence: recurrence);
  if (draft == null) return null;
  final id = await saveRecurring(draft.name, draft.recurrence, firstDue: draft.nextDue, emoji: draft.emoji);
  FirebaseAnalytics.instance.logEvent(name: 'routine_created', parameters: {'source': 'sheet', 'unit': draft.recurrence.unit});
  if (context.mounted) await primeNotifications(context, body: 'I’ll ping you when “${draft.name}” is due, if you let me.');
  return id;
}

class RoutinesScreen extends StatefulWidget {
  const RoutinesScreen({super.key});

  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends State<RoutinesScreen> {
  // Rings and "due in" labels move with the clock.
  late final Timer _tick = Timer.periodic(const Duration(minutes: 1), (_) {
    if (mounted) setState(() {});
  });

  static const _examples = <(String, String, Recurrence)>[
    ('🌱', 'Water plants', Recurrence(every: 3, unit: 'day')),
    ('💪', 'Gym', Recurrence(every: 2, unit: 'day')),
    ('💾', 'Back up laptop', Recurrence(every: 1, unit: 'week')),
    ('🛏️', 'Change bed sheets', Recurrence(every: 2, unit: 'week')),
  ];

  @override
  void initState() {
    super.initState();
    _tick;
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: recurringCollection().snapshots(),
          builder: (context, snapshot) {
            final now = DateTime.now();
            final docs = [...?snapshot.data?.docs]
              ..sort((a, b) => Routine(a.id, a.data()).nextDue.compareTo(Routine(b.id, b.data()).nextDue));
            final due = docs.where((d) => Routine(d.id, d.data()).isDue(now)).length;
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 12, 8),
                  sliver: SliverToBoxAdapter(child: _header(theme, docs.length, due)),
                ),
                if (!snapshot.hasData)
                  const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
                else if (docs.isEmpty)
                  SliverFillRemaining(hasScrollBody: false, child: _empty(theme))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    sliver: SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 240,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        return RoutineCard(
                          key: ValueKey(doc.id),
                          routine: Routine(doc.id, doc.data()),
                          now: now,
                          onDone: () => markRoutineDone(context, doc),
                          onOpen: () => showRoutineHistory(context, doc),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, int total, int due) {
    final subtitle = total == 0
        ? 'Things that come back on a rhythm'
        : due == 0
        ? 'Nothing due 🙌'
        : '$due due now';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Routines', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  subtitle,
                  key: ValueKey(subtitle),
                  style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'New routine',
          onPressed: () => addRoutine(context),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }

  Widget _empty(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🔁', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          Text('No routines yet', style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Add chores that repeat. You can also just type “water plants every 3 days” on Home.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (emoji, name, r) in _examples)
                ActionChip(
                  avatar: Text(emoji),
                  label: Text('$name · ${r.label.toLowerCase()}'),
                  onPressed: () => addRoutine(context, name: name, recurrence: r),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
