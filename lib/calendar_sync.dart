// Shows open time reminders in the phone's calendar (one-way: app → calendar).
//
// Off by default and per device: turning it on in Settings asks for calendar access
// and creates a local "NagadAI" calendar; turning it off (or signing out) deletes that
// calendar with all its events. Event ids belong to this phone's calendar, so the
// reminder id → event id map lives in SharedPreferences, not Firestore.
//
// On Android the calendar is a LOCAL one (the only kind the plugin can create): calendar
// apps like Samsung Calendar show it, Google Calendar doesn't.
//
// iOS: when the ios/ project is created, add to ios/Runner/Info.plist:
//   NSCalendarsUsageDescription              (iOS 16 and below)
//   NSCalendarsFullAccessUsageDescription    (iOS 17+)
//   NSCalendarsWriteOnlyAccessUsageDescription (iOS 17+)
// e.g. "NagadAI adds your timed reminders to a NagadAI calendar."

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const calendarName = 'NagadAI';

/// Length of the event for a reminder without an end time.
const defaultEventLength = Duration(minutes: 15);

const _enabledKey = 'calendar_sync';
const _calendarIdKey = 'calendar_sync_calendar';
const _eventsKey = 'calendar_sync_events';
// Written by a version that let the user pick a calendar; removed on sight.
const _oldCalendarNameKey = 'calendar_sync_calendar_name';

/// Whether time reminders are synced to the phone calendar on this device.
final calendarSyncNotifier = ValueNotifier<bool>(false);

Future<void> loadCalendarSync() async {
  final prefs = await SharedPreferences.getInstance();
  calendarSyncNotifier.value = prefs.getBool(_enabledKey) ?? false;
}

/// The calendar event for a stored reminder, or null if it doesn't belong in the
/// calendar: only open reminders triggered by a time are shown.
({String title, DateTime start, DateTime end})? calendarEventFor(Map<String, dynamic>? data) {
  if (data == null || data['triggerType'] != 'time' || (data['status'] ?? 0) != 0) return null;
  // Documents saved before ranges existed keep the start in "when".
  final from = data['from'] ?? data['when'];
  if (from is! Timestamp) return null;
  final start = from.toDate();
  final to = data['to'];
  final end = to is Timestamp && to.toDate().isAfter(start) ? to.toDate() : start.add(defaultEventLength);
  final summary = (data['summary'] as String?)?.trim();
  return (title: summary == null || summary.isEmpty ? 'Reminder' : summary, start: start, end: end);
}

// Calendar calls run one at a time: a save right after app start must not race the
// full sync over the same events.
Future<void> _queue = Future.value();

Future<T?> _serial<T>(String what, Future<T> Function() run) {
  final result = Completer<T?>();
  _queue = _queue.then((_) async {
    try {
      result.complete(await run());
    } catch (e) {
      debugPrint('Calendar sync ($what) failed: $e');
      result.complete(null);
    }
  });
  return result.future;
}

DeviceCalendar get _calendar => DeviceCalendar.instance;

Map<String, String> _loadEvents(SharedPreferences prefs) {
  try {
    return (jsonDecode(prefs.getString(_eventsKey) ?? '{}') as Map).cast<String, String>();
  } catch (_) {
    return {};
  }
}

Future<void> _saveEvents(SharedPreferences prefs, Map<String, String> events) =>
    prefs.setString(_eventsKey, jsonEncode(events));

bool _isOurs(Calendar c) => c.name == calendarName && c.accountType == 'LOCAL' && !c.readOnly;

/// The NagadAI calendar's id: the stored one if it still exists, else one found by
/// name, else a new calendar. Creating one forgets the events of the old one.
Future<String> _calendarId(SharedPreferences prefs) async {
  final calendars = await _calendar.listCalendars();
  final stored = prefs.getString(_calendarIdKey);
  final current = calendars.where((c) => c.id == stored).firstOrNull;
  if (current != null && _isOurs(current)) return current.id;
  if (current != null) {
    // A calendar the user picked in an earlier version (e.g. their Google calendar):
    // take the app's events out of it before moving to the NagadAI calendar.
    for (final eventId in _loadEvents(prefs).values) {
      try {
        await _calendar.deleteEvent(instanceId: eventId);
      } on DeviceCalendarException catch (e) {
        if (e.errorCode != DeviceCalendarError.notFound) debugPrint('Calendar sync: removing $eventId failed: $e');
      }
    }
    debugPrint('Calendar sync: moved from "${current.name}" to the NagadAI calendar');
  }
  final id = calendars.where(_isOurs).firstOrNull?.id ?? await _calendar.createCalendar(name: calendarName);
  await prefs.setString(_calendarIdKey, id);
  await prefs.remove(_oldCalendarNameKey);
  await prefs.remove(_eventsKey); // event ids of a calendar that's gone
  return id;
}

/// Whether syncing should run now: turned on here and access still granted.
Future<bool> _active() async {
  if (!calendarSyncNotifier.value) return false;
  return await _calendar.hasPermissions() == CalendarPermissionStatus.granted;
}

/// Creates or updates the event of one reminder, or removes it when [data] doesn't
/// belong in the calendar (see [calendarEventFor]).
Future<void> _apply(SharedPreferences prefs, String calendarId, Map<String, String> events, String id,
    Map<String, dynamic>? data) async {
  final event = calendarEventFor(data);
  final eventId = events[id];
  if (event == null) {
    if (eventId == null) return;
    events.remove(id);
    try {
      await _calendar.deleteEvent(instanceId: eventId);
    } on DeviceCalendarException catch (e) {
      if (e.errorCode != DeviceCalendarError.notFound) rethrow;
    }
    return;
  }
  if (eventId != null) {
    try {
      await _calendar.updateEvent(
        instanceId: eventId,
        title: event.title,
        startDate: event.start,
        endDate: event.end,
      );
      return;
    } on DeviceCalendarException catch (e) {
      // Deleted in the calendar app: create it again below.
      if (e.errorCode != DeviceCalendarError.notFound) rethrow;
    }
  }
  events[id] = await _calendar.createEvent(
    calendarId: calendarId,
    title: event.title,
    startDate: event.start,
    endDate: event.end,
  );
}

/// Updates the calendar after one reminder changed. [data] is the reminder as stored
/// now, or null when it was deleted. Does nothing unless sync is on.
Future<void> syncReminderToCalendar(String id, Map<String, dynamic>? data) => _serial('reminder $id', () async {
  if (!await _active()) return;
  final prefs = await SharedPreferences.getInstance();
  final calendarId = await _calendarId(prefs);
  final events = _loadEvents(prefs);
  await _apply(prefs, calendarId, events, id, data);
  await _saveEvents(prefs, events);
});

/// Makes the calendar match [openReminders] (all open reminders, from Firestore):
/// adds or updates their time reminders and removes every other event it made.
Future<void> syncAllToCalendar(List<DocumentSnapshot<Map<String, dynamic>>> openReminders) =>
    _serial('all', () async {
  if (!await _active()) return;
  final prefs = await SharedPreferences.getInstance();
  final calendarId = await _calendarId(prefs);
  final events = _loadEvents(prefs);
  final byId = {for (final d in openReminders) d.id: d.data()};
  for (final id in {...events.keys, ...byId.keys}) {
    try {
      await _apply(prefs, calendarId, events, id, byId[id]);
    } catch (e) {
      debugPrint('Calendar sync of reminder $id failed: $e');
    }
  }
  await _saveEvents(prefs, events);
  debugPrint('Calendar sync: ${events.length} events');
});

/// Turns sync on: asks for calendar access (only now), creates the NagadAI calendar
/// and fills it with [openReminders]. Returns false if access was not granted.
Future<bool> enableCalendarSync(List<DocumentSnapshot<Map<String, dynamic>>> openReminders) async {
  final status = await _calendar.requestPermissions();
  if (status != CalendarPermissionStatus.granted) return false;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_enabledKey, true);
  calendarSyncNotifier.value = true;
  await syncAllToCalendar(openReminders);
  return true;
}

/// Turns sync off and deletes the NagadAI calendar with all its events.
Future<void> disableCalendarSync() async {
  final prefs = await SharedPreferences.getInstance();
  final calendarId = prefs.getString(_calendarIdKey);
  calendarSyncNotifier.value = false;
  await prefs.remove(_enabledKey);
  await prefs.remove(_calendarIdKey);
  await prefs.remove(_oldCalendarNameKey);
  await prefs.remove(_eventsKey);
  if (calendarId == null) return;
  await _serial('delete calendar', () async {
    if (await _calendar.hasPermissions() != CalendarPermissionStatus.granted) return;
    final calendar = (await _calendar.listCalendars()).where((c) => c.id == calendarId).firstOrNull;
    // Only ever delete the app's own calendar, never one picked in an earlier version.
    if (calendar != null && _isOurs(calendar)) await _calendar.deleteCalendar(calendarId);
  });
}
