import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:siri_wave/siri_wave.dart';

import '../collections.dart';
import '../lists.dart';
import '../llm/local_parser.dart';
import '../models/recurrence.dart';
import '../models/reminder.dart';
import '../permissions.dart';
import '../place_types.dart';
import '../screens/locations.dart';
import 'reminder_composer.dart';
import 'routine_sheet.dart';

/// What the smart input hands to the screen when the user sends.
class SmartDraft {
  const SmartDraft({
    required this.text,
    this.reminder,
    this.ai,
    this.needsRefine = false,
    this.categoryManual = false,
    this.category,
    this.listManual = false,
    this.list,
  });

  final String text;

  /// Ready to save: the user has a trigger selected.
  final Reminder? reminder;

  /// Cached AI result for [text], when no trigger is selected.
  final Reminder? ai;

  /// The summary/category came from local rules; refine them with AI in the background.
  final bool needsRefine;

  /// The user picked the category by hand ([category]), so AI must not change it.
  final bool categoryManual;
  final String? category;

  /// The user picked the list by hand ([list], null = Inbox); it wins over the AI's choice.
  final bool listManual;
  final String? list;
}

/// One input for everything: type or speak, triggers and category are suggested
/// live as chips, and any chip can be adjusted or picked manually in place.
class SmartInput extends StatefulWidget {
  const SmartInput({
    super.key,
    required this.recording,
    required this.timeout,
    required this.liveAi,
    required this.refine,
    required this.onSubmit,
    required this.onMicTap,
    required this.onMicHoldStart,
    required this.onMicHoldEnd,
  });

  final bool recording;
  final Duration timeout;

  /// Refine suggestions with AI while typing (only for fast cloud models).
  final bool liveAi;
  final Future<Reminder?> Function(String text) refine;
  final ValueChanged<SmartDraft> onSubmit;
  final VoidCallback onMicTap;
  final VoidCallback onMicHoldStart;
  final VoidCallback onMicHoldEnd;

  @override
  State<SmartInput> createState() => SmartInputState();
}

class SmartInputState extends State<SmartInput> {
  static const _aiDelay = Duration(milliseconds: 800);
  static const _aiMinLength = 8;

  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _aiCache = <String, Reminder>{};
  StreamSubscription<dynamic>? _placesSub, _categoriesSub, _listsSub;
  List<String> _lists = [];
  bool _listChosen = false;
  String? _manualList;
  List<String> _places = [];
  Map<String, String> _categories = {}; // name -> emoji
  Timer? _aiTimer;
  bool _aiBusy = false;

  Suggestion? _manualTrigger;
  bool _triggerCleared = false;
  String? _manualCategory;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _focus.addListener(() => setState(() {}));
    _placesSub = locationsCollection().snapshots().listen((s) {
      setState(() => _places = [for (final d in s.docs) d.data()['name'] as String]);
    });
    _listsSub = userListsStream().listen((docs) {
      setState(() => _lists = [for (final d in docs) d.data()['name'] as String]);
    });
    _categoriesSub = categoriesCollection().snapshots().listen((s) {
      setState(
        () => _categories = {for (final d in s.docs) d.data()['name'] as String: d.data()['emoji'] as String? ?? '🏷️'},
      );
    });
  }

  @override
  void dispose() {
    _aiTimer?.cancel();
    _placesSub?.cancel();
    _categoriesSub?.cancel();
    _listsSub?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- public API

  void focus() => _focus.requestFocus();

  /// Puts a voice transcript in the field. Sends it right away when a trigger
  /// is clear (locally or from AI); otherwise leaves it with suggestions.
  Future<void> setTranscript(String text) async {
    _controller.text = text;
    // Setting the text scheduled a live AI request; this method makes its own, so one is enough.
    _aiTimer?.cancel();
    if (_localTriggers(text).isNotEmpty) {
      _send();
      return;
    }
    setState(() => _aiBusy = true);
    final r = await widget.refine(text);
    if (!mounted) return;
    setState(() => _aiBusy = false);
    if (_controller.text != text) return;
    if (r != null) {
      _aiCache[text] = r;
      final confident = r.triggerType != 'none' && (r.confidence ?? 0) >= 0.7;
      if (confident) {
        _send();
        return;
      }
      setState(() {});
    }
  }

  // ---------------------------------------------------------------- suggestions

  String get _text => _controller.text.trim();

  List<Suggestion> _local(String text) => suggestTriggers(text, places: _places, categories: _categories.keys.toList());

  List<Suggestion> _localTriggers(String text) => _local(text).where((s) => s.isTrigger).toList();

  List<Suggestion> _fromAi(Reminder r) => [
    if (r.repeat != null)
      Suggestion(kind: SuggestionKind.repeat, source: SuggestionSource.ai, repeat: r.repeat, when: r.when),
    if (r.triggerType == 'time' && r.when != null)
      Suggestion(kind: SuggestionKind.time, source: SuggestionSource.ai, when: r.when),
    if (r.triggerType == 'activity' && r.activity != null)
      Suggestion(kind: SuggestionKind.activity, source: SuggestionSource.ai, activity: r.activity),
    if (r.triggerType == 'location' && r.location != null)
      Suggestion(
        kind: SuggestionKind.location,
        source: SuggestionSource.ai,
        location: storeTypeFor(r.location!) ?? r.location,
        locationEvent: r.locationEvent ?? 'enter',
      ),
  ];

  /// Trigger candidates: AI first (when available), then local rules, de-duplicated.
  List<Suggestion> get _candidates {
    final text = _text;
    if (text.isEmpty) return const [];
    final ai = _aiCache[text];
    final all = <Suggestion>[...?(ai == null ? null : _fromAi(ai)), ..._localTriggers(text)];
    final unique = <Suggestion>[];
    for (final s in all) {
      if (!unique.any((u) => u.sameAs(s))) unique.add(s);
    }
    return unique;
  }

  Suggestion? get _selectedTrigger => _manualTrigger ?? (_triggerCleared ? null : _candidates.firstOrNull);

  bool get _categoryFromAi =>
      _manualCategory == null && _aiCache[_text]?.category == _category && _category != null;

  /// The list the task goes to: the user's pick, else the AI's, else the Inbox (null).
  String? get _list {
    if (_listChosen) return _manualList;
    final aiList = _aiCache[_text]?.list;
    return _lists.contains(aiList) ? aiList : null;
  }

  String? get _category {
    if (_manualCategory != null) return _manualCategory;
    final aiCat = _aiCache[_text]?.category;
    if (aiCat != null && _categories.containsKey(aiCat)) return aiCat;
    return _local(_text).where((s) => s.kind == SuggestionKind.category).firstOrNull?.category;
  }


  void _onTextChanged() {
    final text = _text;
    if (text.isEmpty) {
      _manualTrigger = null;
      _triggerCleared = false;
      _manualCategory = null;
      _listChosen = false;
      _manualList = null;
    }
    setState(() {});
    _aiTimer?.cancel();
    if (!widget.liveAi || text.length < _aiMinLength || _aiCache.containsKey(text)) return;
    // A trigger found locally is already shown as a chip; AI then only polishes the
    // wording, which happens once after sending instead of on every pause in typing.
    if (_localTriggers(text).isNotEmpty) return;
    _aiTimer = Timer(_aiDelay, () async {
      if (!mounted || _text != text) return;
      setState(() => _aiBusy = true);
      final r = await widget.refine(text);
      if (!mounted) return;
      setState(() {
        _aiBusy = false;
        if (r != null) _aiCache[text] = r;
      });
    });
  }

  // ---------------------------------------------------------------- send

  void _send() {
    final text = _text;
    if (text.isEmpty) return;
    final ai = _aiCache[text];
    final trigger = _selectedTrigger;
    final category = _category;

    SmartDraft draft;
    // Removing the trigger chip is a decision too: save with no trigger instead of letting AI add one back.
    if (trigger != null || _triggerCleared) {
      final spans = trigger == null ? const <(int, int)>[] : _local(text).expand((s) => s.spans);
      final repeating = trigger?.kind == SuggestionKind.repeat;
      final when = trigger?.kind == SuggestionKind.time || repeating ? trigger?.when : null;
      draft = SmartDraft(
        text: text,
        needsRefine: ai == null,
        categoryManual: _manualCategory != null,
        listManual: _listChosen,
        list: _list,
        reminder: Reminder(
          summary: ai?.summary ?? cleanSummary(text, spans),
          when: when,
          condition: !repeating && when != null ? formatReminderWhen(context, when) : trigger?.condition,
          transcript: text,
          triggerType: trigger?.triggerType ?? 'none',
          activity: trigger?.activity,
          location: trigger?.location,
          locationEvent: trigger?.locationEvent,
          category: category ?? ai?.category ?? 'other',
          list: _list,
          confidence: 1.0,
          repeat: trigger?.repeat,
        ),
      );
    } else {
      draft = SmartDraft(
        text: text,
        ai: ai,
        categoryManual: _manualCategory != null,
        category: _manualCategory,
        listManual: _listChosen,
        list: _list,
      );
    }

    _aiTimer?.cancel();
    _controller.clear();
    _focus.unfocus();
    widget.onSubmit(draft);
  }

  // ---------------------------------------------------------------- pickers

  Future<void> _adjust(SuggestionKind kind) async {
    final current = _selectedTrigger;
    final picked = switch (kind) {
      SuggestionKind.time => await _pickTime(current?.when),
      SuggestionKind.activity => await _pickActivity(),
      SuggestionKind.location => await _pickPlace(current),
      SuggestionKind.repeat => await _pickRepeat(current),
      SuggestionKind.category => null,
    };
    if (picked == null || !mounted) return;
    setState(() {
      _manualTrigger = picked;
      _triggerCleared = false;
    });
  }

  Future<Suggestion?> _pickTime(DateTime? current) async {
    final now = DateTime.now();
    final tonight = DateTime(now.year, now.month, now.day, 20);
    final quick = <(String, DateTime)>[
      ('In 1 hour', now.add(const Duration(hours: 1))),
      if (tonight.isAfter(now)) ('Tonight, 8 PM', tonight),
      ('Tomorrow, 9 AM', DateTime(now.year, now.month, now.day + 1, 9)),
      ('Next Monday, 9 AM', DateTime(now.year, now.month, now.day + (8 - now.weekday), 9)),
    ];
    final choice = await _sheet<Object>(
      title: 'When?',
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (label, time) in quick)
            ListTile(
              leading: const Icon(Icons.bolt_rounded),
              title: Text(label),
              onTap: () => Navigator.pop(context, time),
            ),
          ListTile(
            leading: const Icon(Icons.calendar_month_rounded),
            title: const Text('Pick date & time…'),
            onTap: () => Navigator.pop(context, 'custom'),
          ),
        ],
      ),
    );
    if (!mounted) return null;
    final when = choice == 'custom' ? await pickReminderDateTime(context, current) : choice as DateTime?;
    if (when == null) return null;
    return Suggestion(kind: SuggestionKind.time, source: SuggestionSource.manual, when: when);
  }

  Future<Suggestion?> _pickRepeat(Suggestion? current) async {
    final previous = current?.kind == SuggestionKind.repeat ? current : null;
    final repeat = await pickRecurrence(context, current: previous?.repeat);
    if (repeat == null) return null;
    return Suggestion(
      kind: SuggestionKind.repeat,
      source: SuggestionSource.manual,
      repeat: repeat.withMode(previous?.repeat?.mode ?? Recurrence.modeDone),
      when: previous?.when,
    );
  }

  Future<Suggestion?> _pickActivity() async {
    final activity = await _sheet<String>(
      title: 'Remind me when I start…',
      builder: (context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final a in activities)
            ActionChip(
              avatar: Text(activityEmoji[a]!),
              label: Text(_activityLabel(a)),
              onPressed: () => Navigator.pop(context, a),
            ),
        ],
      ),
    );
    if (activity == null || !mounted) return null;
    await ensureActivityPermission(context);
    return Suggestion(kind: SuggestionKind.activity, source: SuggestionSource.manual, activity: activity);
  }

  Future<Suggestion?> _pickPlace(Suggestion? current) async {
    var event = current?.locationEvent ?? 'enter';
    final choice = await _sheet<String>(
      title: 'Where?',
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'enter', label: Text('When I arrive')),
                ButtonSegment(value: 'exit', label: Text('When I leave')),
              ],
              selected: {event},
              onSelectionChanged: (s) => setSheet(() => event = s.first),
            ),
            const SizedBox(height: 16),
            const PlaceSectionHeader('Nearby stores'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final MapEntry(:key, :value) in storeTypes.entries)
                  ActionChip(
                    avatar: Text(value.emoji),
                    label: Text(_capitalize(value.label)),
                    onPressed: () => Navigator.pop(context, key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const PlaceSectionHeader('My places'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _places)
                  ActionChip(
                    avatar: const Icon(Icons.place_rounded, size: 18),
                    label: Text(p),
                    onPressed: () => Navigator.pop(context, p),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_location_alt_rounded, size: 18),
                  label: const Text('Add a place'),
                  onPressed: () => Navigator.pop(context, _addPlaceChoice),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return null;
    final place = choice == _addPlaceChoice ? await addPlace(context) : choice;
    if (place == null) return null;
    return Suggestion(
      kind: SuggestionKind.location,
      source: SuggestionSource.manual,
      location: place,
      locationEvent: event,
    );
  }

  Future<void> _pickList() async {
    final picked = await _sheet<String>(
      title: 'List',
      builder: (context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final name in [inboxName, ..._lists])
            ChoiceChip(
              label: Text(name),
              selected: (_list ?? inboxName) == name,
              onSelected: (_) => Navigator.pop(context, name),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _listChosen = true;
      _manualList = picked == inboxName ? null : picked;
    });
  }

  Future<void> _pickCategory() async {
    final picked = await _sheet<String>(
      title: 'Category',
      builder: (context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final MapEntry(key: name, value: emoji) in {..._categories, 'other': '📦'}.entries)
            ChoiceChip(
              label: Text('$emoji $name'),
              selected: _category == name,
              onSelected: (_) => Navigator.pop(context, name),
            ),
        ],
      ),
    );
    if (picked != null && mounted) setState(() => _manualCategory = picked);
  }

  Future<T?> _sheet<T>({required String title, required WidgetBuilder builder}) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              builder(context),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- labels

  static const _addPlaceChoice = '\u0000add-place';

  String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _activityLabel(String a) => switch (a) {
    'IN_VEHICLE' => 'Driving',
    'ON_BICYCLE' => 'Cycling',
    'RUNNING' => 'Running',
    _ => 'Walking',
  };

  String _triggerLabel(Suggestion s) => switch (s.kind) {
    SuggestionKind.time => formatReminderWhen(context, s.when!),
    SuggestionKind.activity => switch (s.activity) {
      'IN_VEHICLE' => 'Next drive',
      'ON_BICYCLE' => 'Next ride',
      'RUNNING' => 'Next run',
      _ => 'Next walk',
    },
    SuggestionKind.location =>
      isStoreType(s.location)
          ? _capitalize(storeCondition(s.location!, s.locationEvent))
          : s.locationEvent == 'exit'
          ? 'Leaving ${s.location}'
          : 'Arriving ${s.location}',
    SuggestionKind.repeat => s.when == null ? s.repeat!.label : '${s.repeat!.label} · from ${formatReminderWhen(context, s.when!)}',
    SuggestionKind.category => s.category ?? '',
  };

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasText = _text.isNotEmpty;
    final expanded = !widget.recording && (_focus.hasFocus || hasText);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(color: scheme.shadow.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, -4)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: widget.recording
                ? _RecordingPanel(timeout: widget.timeout)
                : expanded
                ? _chips(theme)
                : const SizedBox(width: double.infinity),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  enabled: !widget.recording,
                  minLines: 1,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: theme.textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: widget.recording ? 'Listening…' : 'Remind me to…',
                    prefixIcon: Icon(Icons.auto_awesome_rounded, color: scheme.primary, size: 20),
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: hasText
                    ? _SendButton(key: const ValueKey('send'), onTap: _send)
                    : _MicButton(
                        key: const ValueKey('mic'),
                        recording: widget.recording,
                        onTap: widget.onMicTap,
                        onHoldStart: widget.onMicHoldStart,
                        onHoldEnd: widget.onMicHoldEnd,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chips(ThemeData theme) {
    final scheme = theme.colorScheme;
    final selected = _selectedTrigger;
    final alternatives = _candidates.where((c) => selected == null || !c.sameAs(selected)).toList();
    final category = _category;

    Widget sourceBadge(SuggestionSource source) => source == SuggestionSource.ai
        ? Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(Icons.auto_awesome, size: 14, color: scheme.primary),
          )
        : const SizedBox.shrink();

    final chips = <Widget>[
      if (selected != null)
        InputChip(
          selected: true,
          showCheckmark: false,
          avatar: Text(selected.emoji),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Text(_triggerLabel(selected)), sourceBadge(selected.source)],
          ),
          onPressed: () => _adjust(selected.kind),
          onDeleted: () => setState(() {
            _manualTrigger = null;
            _triggerCleared = true;
          }),
        )
      else ...[
        ActionChip(avatar: const Text('⏰'), label: const Text('Time'), onPressed: () => _adjust(SuggestionKind.time)),
        ActionChip(
          avatar: const Text('🚗'),
          label: const Text('On the move'),
          onPressed: () => _adjust(SuggestionKind.activity),
        ),
        ActionChip(
          avatar: const Text('📍'),
          label: const Text('Place'),
          onPressed: () => _adjust(SuggestionKind.location),
        ),
        ActionChip(
          avatar: const Text('🔁'),
          label: const Text('Repeat'),
          onPressed: () => _adjust(SuggestionKind.repeat),
        ),
      ],
      for (final alt in alternatives)
        ActionChip(
          avatar: Text(alt.emoji),
          label: Row(mainAxisSize: MainAxisSize.min, children: [Text(_triggerLabel(alt)), sourceBadge(alt.source)]),
          onPressed: () => setState(() {
            _manualTrigger = alt;
            _triggerCleared = false;
          }),
        ),
      InputChip(
        avatar: const Icon(Icons.checklist_rounded, size: 18),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_list ?? inboxName),
            if (!_listChosen && _list != null) sourceBadge(SuggestionSource.ai),
          ],
        ),
        onPressed: _pickList,
      ),
      if (category != null)
        InputChip(
          avatar: Text(category == 'other' ? '📦' : _categories[category] ?? '🏷️'),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [Text(category), if (_categoryFromAi) sourceBadge(SuggestionSource.ai)],
          ),
          onPressed: _pickCategory,
        )
      else
        ActionChip(avatar: const Text('🏷️'), label: const Text('Category'), onPressed: _pickCategory),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 6),
            child: Row(
              children: [
                Text(
                  selected == null ? 'Add a trigger, or just send' : 'Remind me',
                  style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (_aiBusy) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: scheme.primary),
                  ),
                ],
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [for (final c in chips) Padding(padding: const EdgeInsets.only(right: 8), child: c)],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ parts

class _RecordingPanel extends StatelessWidget {
  const _RecordingPanel({required this.timeout});

  final Duration timeout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      child: Column(
        children: [
          SiriWaveform.ios7(
            controller: IOS7SiriWaveformController(amplitude: 0.7, color: scheme.primary, frequency: 4, speed: 0.15),
            options: const IOS7SiriWaveformOptions(height: 72, width: 360),
          ),
          Text('Say: “Remind me to…”', style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text('Release or tap to finish', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 1, end: 0),
            duration: timeout,
            builder: (context, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: v, minHeight: 4),
            ),
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 56, height: 56, child: Icon(Icons.arrow_upward_rounded, color: scheme.onPrimary)),
      ),
    );
  }
}

class _MicButton extends StatefulWidget {
  const _MicButton({
    super.key,
    required this.recording,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final bool recording;
  final VoidCallback onTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> with SingleTickerProviderStateMixin {
  static const _size = 56.0;
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recording = widget.recording;
    return Semantics(
      button: true,
      label: recording ? 'Stop recording' : 'Record a reminder. Tap, or hold to talk',
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPressStart: (_) => widget.onHoldStart(),
        onLongPressEnd: (_) => widget.onHoldEnd(),
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final t = _pulse.value;
            final breathe = (sin(t * 2 * pi) + 1) / 2;
            return SizedBox(
              width: _size,
              height: _size,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (recording)
                    for (final o in const [0.0, 0.5]) _ring(scheme.error, (t + o) % 1),
                  AnimatedScale(
                    scale: recording ? 1.12 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: _size,
                      height: _size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: recording ? [scheme.error, scheme.tertiary] : [scheme.primary, scheme.tertiary],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (recording ? scheme.error : scheme.primary).withValues(alpha: 0.30 + breathe * 0.25),
                            blurRadius: 12 + breathe * 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(recording ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 28),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _ring(Color color, double progress) {
    final size = _size + progress * 40;
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: (1 - progress) * 0.6), width: 2),
        ),
      ),
    );
  }
}
