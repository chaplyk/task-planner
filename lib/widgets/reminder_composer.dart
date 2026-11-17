import 'package:material_ui/material_ui.dart';

import '../collections.dart';
import '../lists.dart';
import '../llm/emoji.dart';
import '../models/reminder.dart';
import '../permissions.dart';
import '../place_types.dart';
import '../screens/locations.dart';
import 'emoji_picker_sheet.dart';

enum _Trigger { time, activity, location, none }

const _activityLabels = {
  'IN_VEHICLE': ('🚗', 'Driving', 'next time I drive'),
  'ON_BICYCLE': ('🚲', 'Cycling', 'next time I cycle'),
  'RUNNING': ('🏃', 'Running', 'next time I run'),
  'WALKING': ('🚶', 'Walking', 'next time I walk'),
};

/// "Today", "Tomorrow", "Yesterday", or "Mar 3, 2027".
String _dayLabel(BuildContext context, DateTime at, {DateTime? now}) {
  final n = now ?? DateTime.now();
  // UTC dates, so a 23-hour daylight-saving day still counts as one day.
  final today = DateTime.utc(n.year, n.month, n.day);
  final day = DateTime.utc(at.year, at.month, at.day);
  return switch (day.difference(today).inDays) {
    -1 => 'Yesterday',
    0 => 'Today',
    1 => 'Tomorrow',
    _ => MaterialLocalizations.of(context).formatMediumDate(at),
  };
}

String _time(BuildContext context, DateTime at) =>
    MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(at));

/// "Today at 6:00 PM", "Tomorrow at 9:00 AM", "Mar 3, 2027 at 8:00 AM".
String formatReminderFrom(BuildContext context, DateTime from, {DateTime? now}) =>
    '${_dayLabel(context, from, now: now)} at ${_time(context, from)}';

/// A start, or a start and end: "Today at 2:00 PM – 3:00 PM", "Tomorrow at 9:00 AM – Nov 20, 2026 at 6:00 PM".
String formatReminderRange(BuildContext context, DateTime from, DateTime? to, {DateTime? now}) {
  final start = formatReminderFrom(context, from, now: now);
  if (to == null) return start;
  final sameDay = from.year == to.year && from.month == to.month && from.day == to.day;
  return '$start – ${sameDay ? _time(context, to) : formatReminderFrom(context, to, now: now)}';
}

/// Date picker followed by a time picker. Returns null if either is dismissed.
Future<DateTime?> pickReminderDateTime(BuildContext context, DateTime? current) async {
  final now = DateTime.now();
  final initial = current ?? now.add(const Duration(hours: 1));
  final date = await showDatePicker(
    context: context,
    initialDate: initial.isBefore(now) ? now : initial,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: now.add(const Duration(days: 365 * 2)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// Opens a bottom sheet to create or edit a reminder by touch.
/// Returns the reminder, or null if the user dismissed the sheet.
Future<Reminder?> showReminderComposer(
  BuildContext context, {
  Reminder? initial,
  String title = 'New reminder',
  String? list,
}) {
  return showModalBottomSheet<Reminder>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => _Composer(initial: initial, title: title, list: list),
  );
}

class _Composer extends StatefulWidget {
  const _Composer({this.initial, required this.title, this.list});

  final Reminder? initial;
  final String title;

  /// List preselected for a new task (e.g. when adding from inside a list).
  final String? list;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  late final _summary = TextEditingController(text: widget.initial?.summary ?? '');
  late _Trigger _trigger = switch (widget.initial?.triggerType) {
    'activity' => _Trigger.activity,
    'location' => _Trigger.location,
    'none' => _Trigger.none,
    _ => widget.initial?.from != null ? _Trigger.time : _Trigger.none,
  };
  late DateTime? _from = widget.initial?.from;
  late DateTime? _to = widget.initial?.to;
  late String? _activity = widget.initial?.activity;
  late String? _location = widget.initial?.location;
  late String _locationEvent = widget.initial?.locationEvent ?? 'enter';
  late String? _category = widget.initial?.category;
  late String? _list = widget.initial?.list ?? widget.list;

  // The saved or hand-picked emoji; while null a keyword guess is shown and one is picked on save.
  late String? _emoji = widget.initial?.emoji;

  String get _shownEmoji => _emoji ?? keywordEmoji(_summary.text);

  Future<void> _pickEmoji() async {
    final picked = await pickEmoji(context, current: _shownEmoji, subject: _summary.text);
    if (picked != null && mounted) setState(() => _emoji = picked);
  }

  @override
  void initState() {
    super.initState();
    _summary.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _summary.dispose();
    super.dispose();
  }

  bool get _valid {
    if (_summary.text.trim().isEmpty) return false;
    return switch (_trigger) {
      _Trigger.time => _from != null && !_endBeforeStart,
      _Trigger.activity => _activity != null,
      _Trigger.location => _location != null,
      _Trigger.none => true,
    };
  }

  bool get _endBeforeStart => _from != null && _to != null && !_to!.isAfter(_from!);

  /// Moves the start; an end moves with it, so the event keeps its length.
  void _setFrom(DateTime from) => setState(() {
        if (_from != null && _to != null) _to = _to!.add(from.difference(_from!));
        _from = from;
      });

  String? _condition() => switch (_trigger) {
        _Trigger.time => formatReminderRange(context, _from!, _to),
        _Trigger.activity => _activityLabels[_activity]!.$3,
        _Trigger.location => isStoreType(_location)
            ? storeCondition(_location!)
            : _locationEvent == 'enter'
            ? 'when I arrive at $_location'
            : 'when I leave $_location',
        _Trigger.none => null,
      };

  void _save() {
    Navigator.pop(
      context,
      Reminder(
        summary: _summary.text.trim(),
        from: _trigger == _Trigger.time ? _from : null,
        to: _trigger == _Trigger.time ? _to : null,
        condition: _condition(),
        transcript: widget.initial?.transcript,
        triggerType: _trigger.name,
        activity: _trigger == _Trigger.activity ? _activity : null,
        location: _trigger == _Trigger.location ? _location : null,
        locationEvent: _trigger == _Trigger.location ? _locationEvent : null,
        category: _category ?? 'other',
        list: _list,
        confidence: 1.0,
        // A recurring task keeps repeating unless the user switched it to a place or activity.
        repeat: _trigger == _Trigger.time || _trigger == _Trigger.none ? widget.initial?.repeat : null,
        emoji: _emoji,
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final picked = await pickReminderDateTime(context, _from);
    if (picked != null && mounted) _setFrom(picked);
  }

  Future<void> _pickEnd() async {
    final from = _from ?? DateTime.now();
    final picked = await pickReminderDateTime(context, _to ?? from.add(const Duration(hours: 1)));
    if (picked != null && mounted) setState(() => _to = picked);
  }

  Future<void> _selectTrigger(_Trigger trigger) async {
    setState(() => _trigger = trigger);
    if (trigger == _Trigger.activity) await ensureActivityPermission(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),
            Row(
              children: [
                Tooltip(
                  message: 'Change emoji',
                  child: Material(
                    color: theme.colorScheme.primaryContainer,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _pickEmoji,
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                            child: Text(_shownEmoji, key: ValueKey(_shownEmoji), style: const TextStyle(fontSize: 28)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _summary,
                    autofocus: widget.initial == null,
                    textCapitalization: TextCapitalization.sentences,
                    style: theme.textTheme.titleMedium,
                    decoration: InputDecoration(
                      hintText: 'What should I remind you about?',
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _Label('When should I remind you?'),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<_Trigger>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _Trigger.none, label: Text('No alert')),
                  ButtonSegment(value: _Trigger.time, label: Text('Time')),
                  ButtonSegment(value: _Trigger.activity, label: Text('Activity')),
                  ButtonSegment(value: _Trigger.location, label: Text('Place')),
                ],
                selected: {_trigger},
                onSelectionChanged: (s) => _selectTrigger(s.first),
              ),
            ),
            const SizedBox(height: 12),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: switch (_trigger) {
                _Trigger.time => _timeOptions(),
                _Trigger.activity => _activityOptions(),
                _Trigger.location => _locationOptions(),
                _Trigger.none => const SizedBox(width: double.infinity),
              },
            ),
            const SizedBox(height: 24),
            _Label('List'),
            _listOptions(),
            const SizedBox(height: 24),
            _Label('Category'),
            _categoryOptions(),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _valid ? _save : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  textStyle: theme.textTheme.titleMedium,
                ),
                child: const Text('Save reminder'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeOptions() {
    final now = DateTime.now();
    final tonight = DateTime(now.year, now.month, now.day, 20);
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
    final quick = <(String, DateTime)>[
      ('In 1 hour', now.add(const Duration(hours: 1))),
      if (tonight.isAfter(now)) ('Tonight 8 PM', tonight),
      ('Tomorrow 9 AM', tomorrow),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, time) in quick)
              ChoiceChip(
                label: Text(label),
                selected: _from != null && _from!.difference(time).inMinutes.abs() < 1,
                onSelected: (_) => _setFrom(time),
              ),
            ActionChip(
              avatar: const Icon(Icons.calendar_month, size: 18),
              label: const Text('Pick…'),
              onPressed: _pickDateTime,
            ),
            if (_from != null && _to == null)
              ActionChip(
                avatar: const Icon(Icons.more_time_rounded, size: 18),
                label: const Text('Add end time'),
                onPressed: _pickEnd,
              ),
          ],
        ),
        if (_from != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _to == null ? null : _pickEnd,
                    child: Text(
                      '🔔 ${formatReminderRange(context, _from!, _to)}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ),
                ),
                if (_to != null)
                  IconButton(
                    tooltip: 'Remove end time',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() => _to = null),
                  ),
              ],
            ),
          ),
        if (_endBeforeStart)
          Text(
            'End must be after start',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }

  Widget _activityOptions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in activities)
          ChoiceChip(
            label: Text('${_activityLabels[a]!.$1} ${_activityLabels[a]!.$2}'),
            selected: _activity == a,
            onSelected: (_) => setState(() => _activity = a),
          ),
      ],
    );
  }

  Widget _locationOptions() {
    return StreamBuilder(
      stream: locationsCollection().snapshots(),
      builder: (context, snapshot) {
        final names = [
          for (final d in snapshot.data?.docs ?? const []) d.data()['name'] as String,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(value: 'enter', label: Text('When I arrive')),
                  // Nearby categories only work on arrival.
                  ButtonSegment(value: 'exit', label: const Text('When I leave'), enabled: !isStoreType(_location)),
                ],
                selected: {_locationEvent},
                onSelectionChanged: (s) => setState(() => _locationEvent = s.first),
              ),
            ),
            const SizedBox(height: 16),
            const PlaceSectionHeader('Nearby categories'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final MapEntry(:key, :value) in storeTypes.entries)
                  ChoiceChip(
                    label: Text('${value.emoji} ${value.label}'),
                    selected: _location == key,
                    onSelected: _locationEvent == 'exit' ? null : (_) => setState(() => _location = key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const PlaceSectionHeader('My places'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in names)
                  ChoiceChip(
                    label: Text(name),
                    selected: _location == name,
                    onSelected: (_) => setState(() => _location = name),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_location_alt_outlined, size: 18),
                  label: const Text('Add a place'),
                  onPressed: () async {
                    final name = await addPlace(context);
                    if (name != null && mounted) setState(() => _location = name);
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _listOptions() {
    return StreamBuilder(
      stream: listsCollection().orderBy('createdAt').snapshots(),
      builder: (context, snapshot) {
        final names = <String?>[
          null,
          for (final d in snapshot.data?.docs ?? const []) d.data()['name'] as String,
        ];
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in names)
              ChoiceChip(
                label: Text(name ?? inboxName),
                selected: _list == name,
                onSelected: (_) => setState(() => _list = name),
              ),
          ],
        );
      },
    );
  }

  Widget _categoryOptions() {
    return StreamBuilder(
      stream: categoriesCollection().snapshots(),
      builder: (context, snapshot) {
        final cats = [
          for (final d in snapshot.data?.docs ?? const [])
            (d.data()['name'] as String, d.data()['emoji'] as String? ?? '🏷️'),
          ('other', '📦'),
        ];
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (name, emoji) in cats)
              ChoiceChip(
                label: Text('$emoji $name'),
                selected: (_category ?? 'other') == name,
                onSelected: (_) => setState(() => _category = name),
              ),
          ],
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// Small uppercase header above a group of place chips.
class PlaceSectionHeader extends StatelessWidget {
  const PlaceSectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
