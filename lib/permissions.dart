import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

import 'activity_watch.dart';
import 'models/reminder.dart';
import 'notifications.dart';
import 'place_types.dart';

// Asked at most once per app run, so saving several place reminders doesn't nag.
bool _askedBackgroundLocation = false;

/// Asks for location access for place reminders: first an in-app disclosure of what
/// is collected and why, then the system prompts (while in use, then "all the time").
Future<void> requestBackgroundLocationPermission(BuildContext context) async {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.always) return;
  final hasForeground = permission == LocationPermission.whileInUse;
  // With "while in use" the app can still save a place, so don't ask again this run.
  if (hasForeground && _askedBackgroundLocation) return;
  if (!context.mounted) return;

  final accepted = await showPrimeSheet(
    context,
    emoji: '📍',
    title: 'Remind you at the right place',
    body: 'NagadAI collects location data to remind you when you arrive at or leave your saved places '
        'and nearby stores, even when the app is closed or not in use. '
        'Choose "Allow all the time" on the next screen to turn this on.',
    cta: 'Continue',
  );
  _askedBackgroundLocation = true;
  if (!accepted) return;

  if (!hasForeground) {
    permission = await Geolocator.requestPermission();
    if (permission != LocationPermission.whileInUse) return; // denied, or already "always"
  }
  // Android only offers "Allow all the time" after "while in use" has been granted.
  await Permission.locationAlways.request();
}

/// Gets what a reminder's trigger needs to work in the background: the permission
/// (activity, or location for stores), then activity events or the watching service.
Future<void> prepareTrigger(BuildContext context, Reminder reminder) async {
  switch (reminder.triggerType) {
    case 'activity':
      if (await ensureActivityPermission(context)) await enableActivityReminders();
    case 'location':
      // Store reminders are found by position in the background, which needs "Allow all the time".
      if (isStoreType(reminder.location)) await requestBackgroundLocationPermission(context);
      await startWatch();
    default:
      break;
  }
}

Future<bool> notificationsAllowed() => AwesomeNotifications().isNotificationAllowed();

/// Explains why notifications matter, then shows the system prompt.
/// Asked right after the user saves a reminder, when the value is obvious.
Future<void> primeNotifications(BuildContext context, {String? body}) async {
  if (await notificationsAllowed() || !context.mounted) return;
  final accepted = await showPrimeSheet(
    context,
    emoji: '🔔',
    title: 'Want me to ping you?',
    body: body ?? "Reminders only work if I can nudge you at the right moment.",
    cta: 'Turn on notifications',
  );
  if (accepted) await askNotificationPermission();
}

/// Explains activity detection, then requests the permission.
/// Returns whether the permission is granted.
Future<bool> ensureActivityPermission(BuildContext context) async {
  if (await Permission.activityRecognition.isGranted) return true;
  if (!context.mounted) return false;
  final accepted = await showPrimeSheet(
    context,
    emoji: '🚗',
    title: 'Remind you on the move',
    body: 'Allow activity detection so I can remind you when you start driving, '
        'cycling or walking. It stays on your phone.',
    cta: 'Allow',
  );
  if (!accepted) return false;
  return (await Permission.activityRecognition.request()).isGranted;
}

/// Short in-app explanation shown before a system permission dialog.
Future<bool> showPrimeSheet(
  BuildContext context, {
  required String emoji,
  required String title,
  required String body,
  required String cta,
}) async {
  final result = await showModalBottomSheet<bool>(
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
              Text(emoji, style: const TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(cta),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}
