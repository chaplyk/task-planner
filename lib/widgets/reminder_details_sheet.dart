import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../lists.dart';
import '../llm/emoji.dart';
import '../models/recurrence.dart';
import '../permissions.dart';
import '../reminders_repo.dart';
import 'reminder_composer.dart';
import 'reminder_tile.dart';

enum _DetailsAction { edit, delete }

/// Bottom sheet with a reminder's details, Mark as done / Reopen, and an Edit / Delete
/// menu. Follows the reminder live, so an edit shows up in place.
///
/// [onEdit] and [onDelete] let a screen use its own (e.g. hide the row before the delete
/// lands); without them the sheet edits and deletes by itself. Delete closes the sheet first.
Future<void> showReminderDetails(
  BuildContext context,
  ReminderDoc doc, {
  Future<void> Function(ReminderDoc doc)? onEdit,
  Future<void> Function(ReminderDoc doc)? onDelete,
}) {
  final screen = context;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: doc.reference.snapshots(),
      initialData: doc,
      builder: (context, snapshot) {
        final current = snapshot.data;
        // Deleted while open.
        if (current == null || current.data() == null) return const SizedBox.shrink();
        return _Details(
          doc: current,
          onEdit: onEdit ?? (d) => editReminder(screen, d),
          onDelete: onDelete ?? (d) => deleteReminderWithUndo(screen, d),
          screen: screen,
        );
      },
    ),
  );
}

/// Opens the composer on [doc] and saves the result, then sets up its trigger.
Future<void> editReminder(BuildContext context, ReminderDoc doc, {String title = 'Edit reminder'}) async {
  final updated = await showReminderComposer(context, initial: reminderFromDoc(doc), title: title);
  if (updated == null) return;
  await updateReminder(doc, updated);
  if (context.mounted) await prepareTrigger(context, updated);
}

/// Deletes [doc] and offers Undo in a snackbar.
Future<void> deleteReminderWithUndo(BuildContext context, ReminderDoc doc) async {
  final data = await deleteReminder(doc);
  if (!context.mounted || data == null) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Text('Deleted: ${data['summary']}'),
        action: SnackBarAction(label: 'Undo', onPressed: () => restoreReminder(doc.id, data)),
      ),
    );
}

class _Details extends StatelessWidget {
  const _Details({required this.doc, required this.onEdit, required this.onDelete, required this.screen});

  /// The latest snapshot.
  final ReminderDoc doc;
  final Future<void> Function(ReminderDoc doc) onEdit;
  final Future<void> Function(ReminderDoc doc) onDelete;

  /// The screen that opened the sheet: Delete closes the sheet and runs there.
  final BuildContext screen;

  void _onMenu(BuildContext context, _DetailsAction action) {
    switch (action) {
      case _DetailsAction.edit:
        onEdit(doc);
      case _DetailsAction.delete:
        Navigator.pop(context);
        if (screen.mounted) onDelete(doc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final data = doc.data()!;
    final done = data['status'] == 1;
    final summary = data['summary'] as String? ?? '';
    final storedEmoji = data['emoji'];
    final emoji = storedEmoji is String && storedEmoji.isNotEmpty ? storedEmoji : keywordEmoji(summary);

    final from = reminderStart(data), to = reminderEnd(data);
    final condition = data['triggerType'] == 'time' && from != null
        ? formatReminderRange(context, from, to)
        : data['condition'] as String?;
    final repeat = Recurrence.tryParse(data['repeat']);
    final category = data['category'] as String?;
    final transcript = (data['transcript'] as String?)?.trim();

    final String status;
    final Color statusColor;
    if (done) {
      (status, statusColor) = ('Done', scheme.primary);
    } else if (isOverdue(data)) {
      (status, statusColor) = ('Overdue', scheme.error);
    } else if (data['notified'] == true) {
      (status, statusColor) = ('Notified', scheme.primary);
    } else {
      (status, statusColor) = ('Waiting', scheme.onSurfaceVariant);
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Text(emoji, style: const TextStyle(fontSize: 28)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(status, style: theme.textTheme.bodyMedium?.copyWith(color: statusColor)),
                ],
              ),
            ),
            PopupMenuButton<_DetailsAction>(
              tooltip: 'More',
              onSelected: (a) => _onMenu(context, a),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _DetailsAction.edit,
                  child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit')),
                ),
                PopupMenuItem(
                  value: _DetailsAction.delete,
                  child: ListTile(leading: Icon(Icons.delete_outline_rounded), title: Text('Delete')),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (condition != null && condition.isNotEmpty) _InfoRow(icon: triggerIcon(data), text: condition),
        if (repeat != null) _InfoRow(icon: Icons.repeat_rounded, text: repeat.label),
        _InfoRow(icon: Icons.checklist_rounded, text: data['list'] as String? ?? inboxName),
        if (category != null && category.isNotEmpty)
          StreamBuilder<Map<String, String>>(
            stream: categoryEmojiStream(),
            builder: (context, emojis) {
              final e = emojis.data?[category];
              return _InfoRow(icon: Icons.label_outline_rounded, text: [?e, category].join('  '));
            },
          ),
        if (transcript != null && transcript.isNotEmpty && transcript != summary)
          _InfoRow(icon: Icons.format_quote_rounded, text: '“$transcript”', muted: true),
        const SizedBox(height: 16),
        done
            ? OutlinedButton.icon(
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  reopenReminder(doc);
                },
                icon: const Icon(Icons.undo_rounded),
                label: const Text('Reopen'),
              )
            : FilledButton.icon(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  completeReminder(doc);
                },
                icon: const Icon(Icons.check_rounded),
                label: const Text('Mark as done'),
              ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, this.muted = false});

  final IconData icon;
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: scheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyLarge?.copyWith(color: muted ? scheme.onSurfaceVariant : null),
            ),
          ),
        ],
      ),
    );
  }
}
