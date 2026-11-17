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

Future<void> showNotification(int id, String summary) =>
    AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: 'reminders',
        title: 'Reminder',
        body: summary,
      ),
    );

Future<void> scheduleNotification(int id, String summary, DateTime when) async {
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
    ),
    // Fire on time even in Doze. Exact timing needs the "Alarms & reminders" access;
    // without it Android still delivers while idle, just within its own window.
    schedule: NotificationCalendar.fromDate(date: when, allowWhileIdle: true, preciseAlarm: true),
  );
  debugPrint('Scheduled "$summary" for $when');
}

Future<void> cancelNotification(int id) => AwesomeNotifications().cancel(id);
