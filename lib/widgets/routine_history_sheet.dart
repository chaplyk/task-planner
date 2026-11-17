import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/recurrence.dart';
import '../recurring_repo.dart';
import '../screens/routines.dart';

/// Bottom sheet listing when a routine was marked done or skipped. Follows the routine live.
Future<void> showRoutineHistory(BuildContext context, RoutineDoc doc) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      // Its own messenger, so the Undo snackbar shows inside the sheet instead of behind it.
      builder: (context, scroll) => ScaffoldMessenger(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: doc.reference.snapshots(),
            initialData: doc,
            builder: (context, snapshot) {
              final current = snapshot.data;
              final data = current?.data();
              // Deleted while open.
              if (current == null || data == null) return const SizedBox.shrink();
              return _History(doc: current, routine: Routine(doc.id, data), scroll: scroll);
            },
          ),
        ),
      ),
    ),
  );
}

class _History extends StatelessWidget {
  const _History({required this.doc, required this.routine, required this.scroll});

  /// The latest snapshot, so Done / Skip work from the current due time.
  final RoutineDoc doc;
  final Routine routine;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final events = routine.history;
    final done = events.where((e) => !e.skipped).toList();
    final skipped = events.length - done.length;
    final timed = done.where((e) => e.due != null).toList();
    final onTime = timed.isEmpty ? null : timed.where((e) => e.late == null).length * 100 ~/ timed.length;

    // Rows grouped under a day header, newest first.
    final rows = <Widget>[];
    String? lastDay;
    for (final e in events) {
      final day = _dayLabel(context, e.at);
      if (day != lastDay) {
        rows.add(_DayHeader(day));
        lastDay = day;
      }
      rows.add(_EventRow(event: e));
    }

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, shape: BoxShape.circle),
              child: Text(routine.emoji, style: const TextStyle(fontSize: 28)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(routine.name, style: theme.textTheme.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '${routine.recurrence.label} · ${dueLabel(DateTime.now(), routine.nextDue)}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  markRoutineDone(context, doc);
                },
                icon: const Icon(Icons.check_rounded),
                label: const Text('Mark as done'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  skipRoutine(context, doc);
                },
                icon: const Icon(Icons.skip_next_rounded),
                label: const Text('Skip'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Stat(value: '${done.length}', label: 'Done'),
            const SizedBox(width: 10),
            _Stat(value: '$skipped', label: 'Skipped'),
            const SizedBox(width: 10),
            _Stat(value: onTime == null ? '–' : '$onTime%', label: 'On time'),
          ],
        ),
        const SizedBox(height: 12),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                const Text('🗓️', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 8),
                Text('No history yet', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Press and hold the card to mark it done.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          )
        else
          ...rows,
      ],
    );
  }

  static String _dayLabel(BuildContext context, DateTime at) {
    final now = DateTime.now();
    final days = DateTime.utc(now.year, now.month, now.day).difference(DateTime.utc(at.year, at.month, at.day)).inDays;
    return switch (days) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => MaterialLocalizations.of(context).formatMediumDate(at),
    };
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, letterSpacing: 0.8),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final RoutineEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final late = event.late;
    final time = MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(event.at));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: event.skipped ? scheme.surfaceContainerHighest : scheme.primaryContainer,
        child: Icon(
          event.skipped ? Icons.skip_next_rounded : Icons.check_rounded,
          color: event.skipped ? scheme.onSurfaceVariant : scheme.onPrimaryContainer,
        ),
      ),
      title: Text(event.skipped ? 'Skipped' : 'Done'),
      subtitle: Text(time),
      trailing: event.skipped || event.due == null
          ? null
          : Text(
              late == null ? 'on time' : '${spanLabel(late)} late',
              style: theme.textTheme.labelLarge?.copyWith(color: late == null ? scheme.primary : scheme.error),
            ),
    );
  }
}
