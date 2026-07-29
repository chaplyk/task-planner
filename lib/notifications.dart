import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/foundation.dart';

Future<void> initNotifications() async {
  await AwesomeNotifications().initialize(null, [
    NotificationChannel(
      channelKey: 'reminders',
      channelName: 'Reminders',
      channelDescription: 'Test channel for reminders',
      importance: NotificationImportance.Max,
    ),
  ]);
  await AwesomeNotifications().requestPermissionToSendNotifications();
}

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
    schedule: NotificationCalendar.fromDate(date: when),
  );
  debugPrint('Scheduled "$summary" for $when');
}
