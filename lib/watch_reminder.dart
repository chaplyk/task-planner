import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_check.dart';
import 'llm/extractor.dart';
import 'models/reminder.dart';
import 'notifications.dart';
import 'recurring_repo.dart';
import 'reminders_repo.dart';

const _channel = MethodChannel('watch/reminder');

/// Started by WatchReminderWorker in a headless engine when the watch sends something
/// the user said. Tells the worker it is ready, then turns the text it sends into a
/// reminder and answers with what was saved ({summary, emoji, when}) for the watch.
@pragma('vm:entry-point')
void watchReminderMain() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  _channel.setMethodCallHandler((call) async {
    if (call.method != 'reminder') throw MissingPluginException(call.method);
    final text = ((call.arguments as Map)['text'] as String? ?? '').trim();
    if (text.isEmpty) throw PlatformException(code: 'empty');
    await Firebase.initializeApp();
    if (FirebaseAuth.instance.currentUser == null) throw PlatformException(code: 'signed_out');
    await activateAppCheck();
    await initNotifications();
    final saved = await _save(text);
    // Writes are not awaited (see sendWrite) and the worker destroys this engine next:
    // give them a chance to reach the server first. They are in the local cache anyway.
    await FirebaseFirestore.instance.waitForPendingWrites().timeout(
      const Duration(seconds: 15),
      onTimeout: () => debugPrint('Watch reminder: writes still pending, will sync later'),
    );
    return saved;
  });
  _channel.invokeMethod<void>('ready');
}

Future<Map<String, String?>> _save(String text) async {
  Reminder? reminder;
  final extractor = ReminderExtractor();
  try {
    reminder = await extractor.extract(text);
  } catch (e) {
    debugPrint('Watch reminder: extraction failed: $e');
  } finally {
    await extractor.close();
  }
  // Nothing the user said is lost: unparsed speech is kept as a plain task.
  reminder ??= Reminder(summary: text, triggerType: 'none', transcript: text);

  final repeat = reminder.repeat;
  if (repeat != null) {
    await saveRecurring(reminder.summary, repeat, firstDue: reminder.from, emoji: reminder.emoji);
    _log('routine_created', {'source': 'watch', 'unit': repeat.unit});
    return {'summary': reminder.summary, 'emoji': reminder.emoji ?? '🔁', 'when': repeat.label};
  }

  // An unknown place needs the picker on the phone; keep the task without a trigger.
  reminder = await matchKnownPlace(reminder) ?? reminderAtPlace(reminder, null);
  await saveReminder(reminder);
  _log('reminder_created', {'source': 'watch', 'trigger': reminder.triggerType});
  return {'summary': reminder.summary, 'emoji': reminder.emoji, 'when': _when(reminder)};
}

void _log(String name, Map<String, Object> parameters) {
  FirebaseAnalytics.instance
      .logEvent(name: name, parameters: parameters)
      .catchError((Object e) => debugPrint('Analytics: $e'));
}

/// A short description of when the reminder fires, for the watch screen.
String? _when(Reminder r) {
  final from = r.from;
  if (r.triggerType == 'time' && from != null) {
    final now = DateTime.now();
    final days = DateTime(from.year, from.month, from.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    final time = '${from.hour.toString().padLeft(2, '0')}:${from.minute.toString().padLeft(2, '0')}';
    if (days == 0) return 'Today $time';
    if (days == 1) return 'Tomorrow $time';
    return '${from.day}.${from.month.toString().padLeft(2, '0')} $time';
  }
  return r.condition;
}
