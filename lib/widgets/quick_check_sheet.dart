import 'package:material_ui/material_ui.dart';

import '../collections.dart';
import '../models/reminder.dart';
import 'reminder_composer.dart';
import 'reminder_tile.dart';

/// Lightweight confirmation for a reminder the AI wasn't sure about.
/// Shows the parsed result as tappable chips; "More options" opens the full composer.
Future<Reminder?> showQuickCheck(BuildContext context, Reminder reminder) async {
  final result = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => _QuickCheck(initial: reminder),
  );
  if (result is Reminder) return result;
  if (result is _MoreOptions && context.mounted) {
    return showReminderComposer(context, initial: result.reminder, title: 'Edit reminder');
  }
  return null;
}

class _MoreOptions {
  const _MoreOptions(this.reminder);
  final Reminder reminder;
}

class _QuickCheck extends StatefulWidget {
  const _QuickCheck({required this.initial});

  final Reminder initial;

  @override
  State<_QuickCheck> createState() => _QuickCheckState();
}

class _QuickCheckState extends State<_QuickCheck> {
  late final _summary = TextEditingController(text: widget.initial.summary);
  late Reminder _r = widget.initial;
  bool _pickingCategory = false;

  @override
  void dispose() {
    _summary.dispose();
    super.dispose();
  }

  Reminder _current({
    DateTime? from,
    DateTime? to,
    String? condition,
    String? triggerType,
    String? category,
  }) =>
      Reminder(
        summary: _summary.text.trim(),
        from: from ?? _r.from,
        to: from == null ? _r.to : to,
        condition: condition ?? _r.condition,
        transcript: _r.transcript,
        triggerType: triggerType ?? _r.triggerType,
        activity: _r.activity,
        location: _r.location,
        locationEvent: _r.locationEvent,
        category: category ?? _r.category,
        list: _r.list,
        confidence: 1.0,
        repeat: _r.repeat,
        emoji: _r.emoji,
      );

  Future<void> _editTime() async {
    final canEditTime = _r.triggerType == 'time' || _r.triggerType == 'none';
    if (!canEditTime) {
      Navigator.pop(context, _MoreOptions(_current()));
      return;
    }
    final picked = await pickReminderDateTime(context, _r.from);
    if (picked == null || !mounted) return;
    // An end moves with the start, so the event keeps its length.
    final to = _r.from != null && _r.to != null ? _r.to!.add(picked.difference(_r.from!)) : null;
    setState(() => _r = _current(
          from: picked,
          to: to,
          triggerType: 'time',
          condition: formatReminderRange(context, picked, to),
        ));
  }

  String _triggerLabel() => switch (_r.triggerType) {
        'time' when _r.from != null => formatReminderRange(context, _r.from!, _r.to),
        'none' => 'Add a time',
        _ => _r.condition ?? 'Trigger',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Did I get this right?', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Tap anything to fix it.',
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _summary,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  style: theme.textTheme.titleLarge,
                  decoration: const InputDecoration(border: InputBorder.none),
                  onChanged: (_) => setState(() {}),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: Text(triggerEmoji(_r.triggerType == 'none' ? 'time' : _r.triggerType)),
                      label: Text(_triggerLabel()),
                      onPressed: _editTime,
                    ),
                    ActionChip(
                      avatar: StreamBuilder(
                        stream: categoryEmojiStream(),
                        builder: (context, s) => Text(s.data?[_r.category] ?? '🏷️'),
                      ),
                      label: Text(_r.category ?? 'other'),
                      onPressed: () => setState(() => _pickingCategory = !_pickingCategory),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: _pickingCategory ? _categoryPicker() : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _summary.text.trim().isEmpty ? null : () => Navigator.pop(context, _current()),
              child: const Text('Looks good'),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context, _MoreOptions(_current())),
              child: const Text('More options'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryPicker() {
    return StreamBuilder(
      stream: categoriesCollection().snapshots(),
      builder: (context, snapshot) {
        final cats = [
          for (final d in snapshot.data?.docs ?? const [])
            (d.data()['name'] as String, d.data()['emoji'] as String? ?? '🏷️'),
          ('other', '📦'),
        ];
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (name, emoji) in cats)
                ChoiceChip(
                  label: Text('$emoji $name'),
                  selected: (_r.category ?? 'other') == name,
                  onSelected: (_) => setState(() {
                    _r = _current(category: name);
                    _pickingCategory = false;
                  }),
                ),
            ],
          ),
        );
      },
    );
  }
}
