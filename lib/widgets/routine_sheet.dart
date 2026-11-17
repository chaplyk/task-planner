import 'package:material_ui/material_ui.dart';

import '../llm/emoji.dart';
import '../models/recurrence.dart';
import '../recurring_repo.dart';
import 'emoji_picker_sheet.dart';
import 'reminder_composer.dart';

/// The intervals offered as one-tap chips.
const repeatPresets = <(String, Recurrence)>[
  ('Hourly', Recurrence(every: 1, unit: 'hour')),
  ('Daily', Recurrence(every: 1, unit: 'day')),
  ('Every 2 days', Recurrence(every: 2, unit: 'day')),
  ('Weekly', Recurrence(every: 1, unit: 'week')),
  ('Every 2 weeks', Recurrence(every: 2, unit: 'week')),
  ('Monthly', Recurrence(every: 1, unit: 'month')),
];

/// What the routine sheet returns.
class RoutineDraft {
  const RoutineDraft({required this.name, required this.recurrence, this.emoji, this.nextDue});

  final String name;
  final Recurrence recurrence;

  /// Set only when the user asked for a specific emoji; otherwise one is picked automatically.
  final String? emoji;

  /// Set only when the user picked the next due time by hand.
  final DateTime? nextDue;
}

/// Bottom sheet to create a routine, or edit [initial]. Returns null if dismissed.
Future<RoutineDraft?> showRoutineSheet(BuildContext context, {Routine? initial, String? name, Recurrence? recurrence}) {
  return showModalBottomSheet<RoutineDraft>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => _RoutineSheet(
      initial: initial,
      name: name,
      recurrence: recurrence,
    ),
  );
}

class _RoutineSheet extends StatefulWidget {
  const _RoutineSheet({this.initial, this.name, this.recurrence});

  final Routine? initial;
  final String? name;
  final Recurrence? recurrence;

  @override
  State<_RoutineSheet> createState() => _RoutineSheetState();
}

class _RoutineSheetState extends State<_RoutineSheet> {
  late final _name = TextEditingController(text: widget.initial?.name ?? widget.name ?? '');
  late Recurrence _recurrence =
      widget.initial?.recurrence ?? widget.recurrence ?? const Recurrence(every: 1, unit: 'day');
  late bool _custom = !repeatPresets.any((p) => _sameInterval(p.$2, _recurrence));
  String? _manualEmoji;
  DateTime? _nextDue;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  static bool _sameInterval(Recurrence a, Recurrence b) => a.every == b.every && a.unit == b.unit;

  /// The emoji shown: picked by hand, else the saved one, else a live keyword guess.
  String get _emoji => _manualEmoji ?? widget.initial?.emoji ?? keywordEmoji(_name.text);

  Future<void> _pickEmoji() async {
    final picked = await pickEmoji(context, current: _emoji, subject: _name.text);
    if (picked != null && mounted) setState(() => _manualEmoji = picked);
  }

  Future<void> _pickNextDue() async {
    final picked = await pickReminderDateTime(context, _nextDue ?? widget.initial?.nextDue);
    if (picked != null && mounted) setState(() => _nextDue = picked);
  }

  void _save() {
    Navigator.pop(
      context,
      RoutineDraft(
        name: _name.text.trim(),
        recurrence: _recurrence,
        emoji: _manualEmoji,
        nextDue: _nextDue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_editing ? 'Edit routine' : 'New routine', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),
            Row(
              children: [
                Tooltip(
                  message: 'Change emoji',
                  child: InkWell(
                    onTap: _pickEmoji,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                      child: Text(_emoji, style: const TextStyle(fontSize: 28)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _name,
                    autofocus: !_editing && widget.name == null,
                    textCapitalization: TextCapitalization.sentences,
                    style: theme.textTheme.titleMedium,
                    decoration: InputDecoration(
                      hintText: 'Water plants, gym, backup…',
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _Label('How often?'),
            RecurrencePicker(
              value: _recurrence,
              custom: _custom,
              onChanged: (r, custom) => setState(() {
                _recurrence = r.withMode(_recurrence.mode);
                _custom = custom;
              }),
            ),
            const SizedBox(height: 24),
            const _Label('Next time is due…'),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: Recurrence.modeDone, label: Text('After I finish it')),
                  ButtonSegment(value: Recurrence.modeFixed, label: Text('On a fixed schedule')),
                ],
                selected: {_recurrence.mode},
                onSelectionChanged: (s) => setState(() => _recurrence = _recurrence.withMode(s.first)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _recurrence.fixed
                    ? 'Keeps its rhythm even if you do it late.'
                    : 'Counts from the moment you mark it done.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: Text(_editing ? 'Next due' : 'First due'),
              subtitle: Text(
                _nextDue != null
                    ? formatReminderFrom(context, _nextDue!)
                    : _editing
                    ? formatReminderFrom(context, widget.initial!.nextDue)
                    : '${_recurrence.label.replaceFirst('Every', 'In')} from now',
              ),
              trailing: _nextDue == null
                  ? const Icon(Icons.chevron_right_rounded)
                  : IconButton(
                      tooltip: 'Reset',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _nextDue = null),
                    ),
              onTap: _pickNextDue,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _name.text.trim().isEmpty ? null : _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  textStyle: theme.textTheme.titleMedium,
                ),
                child: Text(_editing ? 'Save' : 'Add routine'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Preset interval chips plus a "Custom…" stepper (N × hour/day/week/month).
class RecurrencePicker extends StatelessWidget {
  const RecurrencePicker({super.key, required this.value, required this.custom, required this.onChanged});

  final Recurrence value;

  /// Whether the custom stepper is open.
  final bool custom;
  final void Function(Recurrence value, bool custom) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, preset) in repeatPresets)
              ChoiceChip(
                label: Text(label),
                selected: !custom && preset.every == value.every && preset.unit == value.unit,
                onSelected: (_) => onChanged(preset, false),
              ),
            ChoiceChip(
              avatar: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Custom…'),
              selected: custom,
              onSelected: (_) => onChanged(value, true),
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: !custom
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Text('Every', style: theme.textTheme.titleMedium),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.remove_rounded),
                        onPressed: value.every > 1
                            ? () => onChanged(Recurrence(every: value.every - 1, unit: value.unit), true)
                            : null,
                      ),
                      SizedBox(
                        width: 32,
                        child: Text('${value.every}', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_rounded),
                        onPressed: value.every < 365
                            ? () => onChanged(Recurrence(every: value.every + 1, unit: value.unit), true)
                            : null,
                      ),
                      const SizedBox(width: 4),
                      DropdownButton<String>(
                        value: value.unit,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final u in Recurrence.units)
                            DropdownMenuItem(value: u, child: Text(value.every == 1 ? u : '${u}s')),
                        ],
                        onChanged: (u) => onChanged(Recurrence(every: value.every, unit: u!), true),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// Small sheet to pick only an interval (used by the smart input's repeat chip).
Future<Recurrence?> pickRecurrence(BuildContext context, {Recurrence? current}) {
  var value = current ?? const Recurrence(every: 1, unit: 'day');
  var custom = current != null && !repeatPresets.any((p) => p.$2.every == value.every && p.$2.unit == value.unit);
  return showModalBottomSheet<Recurrence>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: StatefulBuilder(
          builder: (context, setSheet) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Repeat', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              RecurrencePicker(
                value: value,
                custom: custom,
                onChanged: (r, c) {
                  if (!c) {
                    Navigator.pop(context, r.withMode(value.mode));
                    return;
                  }
                  setSheet(() {
                    value = r.withMode(value.mode);
                    custom = true;
                  });
                },
              ),
              if (custom) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(onPressed: () => Navigator.pop(context, value), child: const Text('Done')),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}
