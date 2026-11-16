import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

import 'notifications.dart';

Future<void> requestBackgroundLocationPermission(BuildContext context) async {
  // if background location permission is already granted, do nothing
  if (await Geolocator.checkPermission() == LocationPermission.always) return;

  // else request background location permission
  await Geolocator.requestPermission();

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Background location'),
      content: const Text(
        'To send location-based reminders, the app requires background location access. \n'
        'Please select "Allow all the time" in Permissions -> Location settings.',
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            Geolocator.openAppSettings();
          },
          child: const Text('Open settings'),
        ),
      ],
    ),
  );
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
