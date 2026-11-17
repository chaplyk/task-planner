import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

import '../activity_watch.dart';
import '../collections.dart';
import '../llm/extractor.dart';
import '../llm/model_choice.dart';
import '../models/reminder.dart';
import '../notifications.dart';
import '../permissions.dart';
import '../place_types.dart';
import '../reminders_repo.dart';
import '../widgets/celebration.dart';
import 'locations.dart';
import '../widgets/quick_check_sheet.dart';
import '../widgets/reminder_composer.dart';
import '../widgets/reminder_tile.dart';
import '../widgets/smart_input.dart';
import '../widgets/typewriter.dart';

typedef _Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

class _Pending {
  _Pending(this.text) : id = UniqueKey();
  final Key id;
  final String text;
  bool failed = false;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onSeeAll});

  /// Switches to the full reminders list.
  final VoidCallback? onSeeAll;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _methods = MethodChannel('speech/methods');
  static const _events = EventChannel('speech/events');
  static const _timeout = Duration(seconds: 15);
  static const _upNextCount = 5;

  final _extractor = ReminderExtractor();
  final _inputKey = GlobalKey<SmartInputState>();
  final _pending = <_Pending>[];
  final _highlight = <String>{};
  // Rows swiped or ticked away; hidden right away so a Dismissible never lingers in the tree.
  final _hidden = <String>{};
  bool _recording = false;
  bool _askedNotificationsThisSession = false;
  bool _voiceDraft = false;
  Timer? _recordingTimer;

  @override
  void initState() {
    super.initState();
    _events.receiveBroadcastStream().listen(_onEvent);
    _rescheduleAllNotifications();
    _maybeStartWatch();
    syncGeofences();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _extractor.close();
    super.dispose();
  }

  // Restores what background reminders need on this device: activity events (they are
  // lost on reinstall) and, only if a place reminder is waiting, the watching service.
  Future<void> _maybeStartWatch() async {
    if (await Permission.activityRecognition.isGranted) await enableActivityReminders();
    final places = await remindersCollection()
        .where('status', isEqualTo: 0)
        .where('triggerType', isEqualTo: 'location')
        .limit(1)
        .get();
    if (places.docs.isNotEmpty) await startWatch();
  }

  Future<void> _rescheduleAllNotifications() async {
    final snapshot = await remindersCollection().where('status', isEqualTo: 0).get();
    for (final doc in snapshot.docs) {
      final when = doc.data()['when'] as Timestamp?;
      if (when == null || doc.data()['triggerType'] != 'time') continue;
      await scheduleNotification(int.parse(doc.id), doc.data()['summary'] as String? ?? 'Reminder', when.toDate());
    }
  }

  // ---------------------------------------------------------------- voice

  Future<void> _startRecording() async {
    if (_recording) return;
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _snack('Mic is off, so just type it below', action: 'Type', onAction: () => _inputKey.currentState?.focus());
      return;
    }
    await _methods.invokeMethod<void>('start');
    HapticFeedback.mediumImpact();
    setState(() => _recording = true);
    _recordingTimer = Timer(_timeout, _stopRecording);
    await FirebaseAnalytics.instance.logEvent(name: 'recording_started');
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _recordingTimer?.cancel();
    await _methods.invokeMethod<void>('stop');
    HapticFeedback.lightImpact();
    if (mounted) setState(() => _recording = false);
  }

  Future<void> _toggleRecording() => _recording ? _stopRecording() : _startRecording();

  // Called by the bridge when it has recognized the speech
  Future<void> _onEvent(dynamic event) async {
    if (event['type'] != 'transcript') {
      debugPrint('Ignored speech event: $event');
      return;
    }
    if (_recording) {
      _recordingTimer?.cancel();
      setState(() => _recording = false);
    }
    final text = (event['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return;
    _voiceDraft = true;
    await _inputKey.currentState?.setTranscript(text);
  }

  // ---------------------------------------------------------------- pipeline

  /// Called by the smart input on send (typed, or voice auto-send).
  Future<void> _onDraft(SmartDraft draft) async {
    final source = _voiceDraft ? 'voice' : 'text';
    _voiceDraft = false;
    final ready = draft.reminder;
    if (ready == null) {
      final listOverride = draft.listManual ? (list: draft.list) : null;
      await _process(
        draft.text,
        source: source,
        prefetched: draft.ai,
        listOverride: listOverride,
        categoryOverride: draft.categoryManual ? draft.category : null,
      );
      return;
    }
    final id = await _commit(ready, source: source);
    if (id != null && draft.needsRefine) {
      _refine(id, draft.text, keepCategory: draft.categoryManual, keepList: draft.listManual);
    }
  }

  /// Saved instantly from local rules; let AI polish the summary, category and list afterwards.
  Future<void> _refine(int id, String text, {required bool keepCategory, required bool keepList}) async {
    try {
      final r = await _extractor.extract(text);
      if (r == null || r.summary.isEmpty) return;
      await updateReminderText(
        id,
        summary: r.summary,
        category: keepCategory ? null : r.category,
        list: keepList ? null : r.list,
      );
    } catch (e) {
      debugPrint('Refinement failed: $e');
    }
  }

  Future<Reminder?> _safeExtract(String text) async {
    try {
      return await _extractor.extract(text);
    } catch (e) {
      debugPrint('Suggestion refinement failed: $e');
      return null;
    }
  }

  void _tryExample(String example) => _process('Remind me to $example', source: 'suggestion');

  /// Shows a pending card immediately, then turns it into a real reminder.
  /// [listOverride] is the list the user picked by hand (its `list` may be null = Inbox).
  Future<void> _process(
    String text, {
    required String source,
    Reminder? prefetched,
    ({String? list})? listOverride,
    String? categoryOverride,
  }) async {
    final pending = _Pending(text);
    setState(() => _pending.insert(0, pending));

    Reminder? reminder = prefetched;
    if (reminder == null) {
      final trace = FirebasePerformance.instance.newTrace('thinking');
      await trace.start();
      try {
        reminder = await _extractor.extract(text);
        debugPrint('Reminder: $reminder');
      } catch (e) {
        debugPrint('Extraction failed: $e');
      }
      await trace.stop();
    }
    if (!mounted) return;

    if (reminder == null) {
      HapticFeedback.heavyImpact();
      setState(() => pending.failed = true);
      return;
    }
    if (listOverride != null) reminder = reminder.withList(listOverride.list);
    if (categoryOverride != null) reminder = reminder.withCategory(categoryOverride);
    if ((reminder.confidence ?? 0) < 0.7) {
      reminder = await showQuickCheck(context, reminder);
      if (reminder == null) {
        setState(() => _pending.remove(pending));
        return;
      }
    }
    await _commit(reminder, source: source, pending: pending);
  }

  Future<void> _fixFailed(_Pending pending) async {
    final reminder = await showReminderComposer(
      context,
      initial: Reminder(summary: pending.text, triggerType: 'none'),
      title: 'Let’s fix this one',
    );
    if (reminder == null) return;
    await _commit(reminder, source: 'manual', pending: pending);
  }

  /// Makes sure a place reminder points at a saved place. Matches saved names
  /// case-insensitively; for an unknown place, offers to save it right now.
  Future<Reminder> _resolvePlace(Reminder r) async {
    final place = r.location?.trim();
    if (r.triggerType != 'location' || place == null || place.isEmpty) return r;

    final saved = [
      for (final d in (await locationsCollection().get()).docs) d.data()['name'] as String,
    ];
    final match = saved.where((s) => s.toLowerCase() == place.toLowerCase()).firstOrNull;
    if (match != null) return _withPlace(r, match);
    // "the supermarket" -> any grocery store, detected in the background with Google Places.
    final store = storeTypeFor(place);
    if (store != null) return _withPlace(r, store);
    if (!mounted) return r;

    final leaving = r.locationEvent == 'exit';
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('📍', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                Text('Where is “$place”?', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'I don’t know this place yet. Save it so I can remind you when you ${leaving ? 'leave' : 'arrive'}.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    icon: const Icon(Icons.my_location_rounded),
                    label: const Text('I’m here now: save it'),
                    onPressed: () => Navigator.pop(context, 'save'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: () => Navigator.pop(context, 'later'),
                    child: const Text('Save it later'),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'anytime'),
                  child: const Text('Remind me anytime instead'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return r;

    if (choice == 'save') {
      final name = await addPlace(context, initialName: place);
      if (name != null) return _withPlace(r, name);
    }
    if (choice == 'anytime') return _withPlace(r, null);
    // "Later" or dismissed: keep it; it starts working once a place with this name is saved.
    return _withPlace(r, place);
  }

  /// Copy of [r] pointing at [place], or with no trigger when [place] is null.
  Reminder _withPlace(Reminder r, String? place) {
    final event = r.locationEvent ?? 'enter';
    return Reminder(
      summary: r.summary,
      when: null,
      condition: place == null
          ? null
          : isStoreType(place)
          ? storeCondition(place, event)
          : (event == 'exit' ? 'when I leave $place' : 'when I arrive at $place'),
      transcript: r.transcript,
      triggerType: place == null ? 'none' : 'location',
      location: place,
      locationEvent: place == null ? null : event,
      category: r.category,
      list: r.list,
      confidence: r.confidence,
    );
  }

  Future<int?> _commit(Reminder reminder, {required String source, _Pending? pending}) async {
    reminder = await _resolvePlace(reminder);
    if (!mounted) return null;
    final first = await isFirstReminder();
    final id = await saveReminder(reminder);
    if (!mounted) return id;
    setState(() {
      if (pending != null) _pending.remove(pending);
      _highlight.add('$id');
    });
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _highlight.remove('$id'));
    });
    HapticFeedback.mediumImpact();
    FirebaseAnalytics.instance.logEvent(
      name: 'reminder_created',
      parameters: {'source': source, 'trigger': reminder.triggerType, 'first': first ? 1 : 0},
    );

    if (first) {
      await showFirstReminderCelebration(context, reminder);
      _askedNotificationsThisSession = true;
    } else {
      _undoSnack(reminder, id);
    }
    if (!mounted) return id;
    await _askContextualPermissions(reminder);
    return id;
  }

  Future<void> _askContextualPermissions(Reminder reminder) async {
    await prepareTrigger(context, reminder);
    if (!mounted || _askedNotificationsThisSession) return;
    _askedNotificationsThisSession = true;
    final when = reminder.when;
    await primeNotifications(
      context,
      body: when != null ? 'I’ll ping you ${formatReminderWhen(context, when).toLowerCase()}, if you let me.' : null,
    );
  }

  void _undoSnack(Reminder reminder, int id) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Text('${triggerEmoji(reminder.triggerType)}  Saved: ${reminder.summary}'),
          action: SnackBarAction(label: 'Undo', onPressed: () => deleteReminderById(id)),
        ),
      );
  }

  Future<void> _complete(_Doc doc) async {
    setState(() => _hidden.add(doc.id));
    await completeReminder(doc);
    if (!mounted) return;
    _snack('✅  Done: ${doc.data()['summary']}', action: 'Undo', onAction: () {
      setState(() => _hidden.remove(doc.id));
      reopenReminder(doc);
    });
  }

  Future<void> _delete(_Doc doc) async {
    setState(() => _hidden.add(doc.id));
    final data = await deleteReminder(doc);
    if (!mounted || data == null) return;
    _snack('Deleted: ${data['summary']}', action: 'Undo', onAction: () {
      setState(() => _hidden.remove(doc.id));
      restoreReminder(doc.id, data);
    });
  }

  Future<void> _edit(_Doc doc) async {
    final updated = await showReminderComposer(context, initial: reminderFromDoc(doc), title: 'Edit reminder');
    if (updated == null) return;
    await updateReminder(doc, updated);
    if (mounted) await prepareTrigger(context, updated);
  }

  void _snack(String text, {String? action, VoidCallback? onAction}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Text(text),
          action: action == null ? null : SnackBarAction(label: action, onPressed: onAction!),
        ),
      );
  }

  // ---------------------------------------------------------------- UI

  String _greeting() {
    final hour = DateTime.now().hour;
    final part = hour < 5
        ? 'Still up'
        : hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';
    final name = FirebaseAuth.instance.currentUser?.displayName?.trim().split(' ').first;
    return name == null || name.isEmpty ? part : '$part, $name';
  }

  List<_Doc> _sorted(List<_Doc> docs) {
    DateTime? when(_Doc d) => (d.data()['when'] as Timestamp?)?.toDate();
    DateTime created(_Doc d) =>
        (d.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
    final timed = docs.where((d) => d.data()['triggerType'] == 'time' && when(d) != null).toList()
      ..sort((a, b) => when(a)!.compareTo(when(b)!));
    final timedIds = timed.map((d) => d.id).toSet();
    final rest = docs.where((d) => !timedIds.contains(d.id)).toList()..sort((a, b) => created(b).compareTo(created(a)));
    return [...timed, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                behavior: HitTestBehavior.translucent,
                child: StreamBuilder(
                  stream: remindersCollection().where('status', isEqualTo: 0).snapshots(),
                  builder: (context, snapshot) {
                    final all = snapshot.data?.docs ?? <_Doc>[];
                    // Once Firestore confirms a row is gone, stop tracking it, so a later reopen shows it again.
                    if (snapshot.hasData) {
                      final ids = {for (final d in all) d.id};
                      _hidden.removeWhere((id) => !ids.contains(id));
                    }
                    final docs = _sorted([
                      for (final d in all)
                        if (!_hidden.contains(d.id)) d,
                    ]);
                    final loading = !snapshot.hasData;
                    final empty = !loading && docs.isEmpty && _pending.isEmpty;
                    return CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
                          sliver: SliverToBoxAdapter(child: _header(theme, docs)),
                        ),
                        if (loading)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (empty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                              child: _EmptyState(onExample: _tryExample),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                            sliver: SliverToBoxAdapter(child: _upNext(theme, docs)),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            ValueListenableBuilder<LlmModel>(
              valueListenable: modelChoiceNotifier,
              builder: (context, model, _) => SmartInput(
                key: _inputKey,
                recording: _recording,
                timeout: _timeout,
                liveAi: model == LlmModel.gemini,
                refine: _safeExtract,
                onSubmit: _onDraft,
                onMicTap: _toggleRecording,
                onMicHoldStart: _startRecording,
                onMicHoldEnd: _stopRecording,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, List<_Doc> docs) {
    final now = DateTime.now();
    final today = docs.where((d) {
      final when = (d.data()['when'] as Timestamp?)?.toDate();
      return when != null && when.year == now.year && when.month == now.month && when.day == now.day;
    }).length;
    final subtitle = docs.isEmpty
        ? 'What’s on your mind?'
        : today > 0
        ? '$today today · ${docs.length} total'
        : '${docs.length} reminder${docs.length == 1 ? '' : 's'} on my radar';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_greeting(), style: theme.textTheme.headlineMedium),
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
    );
  }

  Widget _upNext(ThemeData theme, List<_Doc> docs) {
    final shown = docs.take(_upNextCount).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Up next', style: theme.textTheme.titleLarge),
            const Spacer(),
            if (widget.onSeeAll != null && docs.length > shown.length)
              TextButton(onPressed: widget.onSeeAll, child: Text('See all ${docs.length}')),
          ],
        ),
        const SizedBox(height: 8),
        for (final p in _pending)
          Padding(
            key: p.id,
            padding: const EdgeInsets.only(bottom: 10),
            child: PendingTile(
              text: p.text,
              failed: p.failed,
              onTap: p.failed ? () => _fixFailed(p) : null,
              onDismiss: () => setState(() => _pending.remove(p)),
            ),
          ),
        for (final doc in shown)
          Padding(
            key: ValueKey(doc.id),
            padding: const EdgeInsets.only(bottom: 10),
            child: SwipeableReminder(
              key: ValueKey('swipe-${doc.id}'),
              onPrimary: () => _complete(doc),
              onDelete: () => _delete(doc),
              child: ReminderTile(
                data: doc.data(),
                highlight: _highlight.contains(doc.id),
                onTap: () => _edit(doc),
                onToggle: () => _complete(doc),
              ),
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------ empty state

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onExample});

  final ValueChanged<String> onExample;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.tertiaryContainer.withValues(alpha: 0.6)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🧠', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 12),
          Text(
            'Say it once.\nForget about it.',
            style: theme.textTheme.headlineMedium?.copyWith(color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 8),
          Text(
            'I’ll remind you at the right time, place or moment.',
            style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onPrimaryContainer.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 8),
          const Typewriter(),
          Text(
            'Try one, it takes a second:',
            style: theme.textTheme.labelLarge?.copyWith(color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in examples)
                ActionChip(
                  avatar: const Icon(Icons.bolt_rounded, size: 18),
                  label: Text(e),
                  backgroundColor: scheme.surface.withValues(alpha: 0.85),
                  side: BorderSide.none,
                  onPressed: () => onExample(e),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
