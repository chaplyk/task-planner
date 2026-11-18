import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/foundation.dart';

Future<void> initNotifications() => AwesomeNotifications().initialize(null, [
  NotificationChannel(
    channelKey: 'reminders',
    channelName: 'Reminders',
    channelDescription: 'Test channel for reminders',
    importance: NotificationImportance.Max,
  ),
]);

Future<void> askNotificationPermission() =>
    AwesomeNotifications().requestPermissionToSendNotifications();

/// What a notification is about, so tapping it can open that reminder or routine.
enum NotificationKind { reminder, routine }

/// A tapped notification: the reminder or routine document id it is about. [kind] is
/// null for notifications scheduled before they carried one.
typedef NotificationTarget = ({NotificationKind? kind, String id});

/// The last tapped notification, until the app's main screen opens its details.
final openedNotification = ValueNotifier<NotificationTarget?>(null);

/// Starts listening for notification taps, including the one that launched the app.
Future<void> listenForNotificationTaps() async {
  await AwesomeNotifications().setListeners(onActionReceivedMethod: _onNotificationAction);
  final initial = await AwesomeNotifications().getInitialNotificationAction(removeFromActionEvents: true);
  if (initial != null) _open(initial);
}

@pragma('vm:entry-point')
Future<void> _onNotificationAction(ReceivedAction action) async => _open(action);

void _open(ReceivedAction action) {
  final id = action.id;
  if (id == null) return;
  final kind = NotificationKind.values.asNameMap()[action.payload?['kind']];
  openedNotification.value = (kind: kind, id: '$id');
}

Future<void> showNotification(int id, String summary) =>
    AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: 'reminders',
        title: 'Reminder',
        body: summary,
        payload: {'kind': NotificationKind.reminder.name},
      ),
    );

Future<void> scheduleNotification(
  int id,
  String summary,
  DateTime when, {
  NotificationKind kind = NotificationKind.reminder,
}) async {
  if (when.isBefore(DateTime.now())) {
    debugPrint('Not scheduling $summary, its time has passed');
    return;
  }

  await AwesomeNotifications().createNotification(
    content: NotificationContent(
      id: id,
      channelKey: 'reminders',
      title: 'Reminder',
      body: summary,
      payload: {'kind': kind.name},
    ),
    // Fire on time even in Doze. Exact timing needs the "Alarms & reminders" access;
    // without it Android still delivers while idle, just within its own window.
    schedule: NotificationCalendar.fromDate(date: when, allowWhileIdle: true, preciseAlarm: true),
  );
  debugPrint('Scheduled "$summary" for $when');
}

Future<void> cancelNotification(int id) => AwesomeNotifications().cancel(id);
