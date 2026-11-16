import 'package:material_ui/material_ui.dart';

import '../models/reminder.dart';
import '../notifications.dart';
import '../permissions.dart';
import 'reminder_tile.dart';

/// Full-screen moment after the user's very first reminder.
/// Doubles as the notification permission ask, when the value is clearest.
Future<void> showFirstReminderCelebration(BuildContext context, Reminder reminder) async {
  final needsNotifications = !await notificationsAllowed();
  if (!context.mounted) return;
  final enable = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 350),
    transitionBuilder: (context, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
    pageBuilder: (context, _, _) => _Celebration(reminder: reminder, askNotifications: needsNotifications),
  );
  if (enable == true) await askNotificationPermission();
}

class _Celebration extends StatelessWidget {
  const _Celebration({required this.reminder, required this.askNotifications});

  final Reminder reminder;
  final bool askNotifications;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Spacer(),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.elasticOut,
                builder: (context, v, child) => Transform.scale(scale: v, child: child),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [scheme.primary, scheme.tertiary],
                    ),
                    boxShadow: [
                      BoxShadow(color: scheme.primary.withValues(alpha: 0.4), blurRadius: 40, offset: const Offset(0, 16)),
                    ],
                  ),
                  child: const Icon(Icons.check_rounded, size: 72, color: Colors.white),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Done. I’ll remember,\nso you don’t have to.',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
              ReminderTile(
                data: {
                  'summary': reminder.summary,
                  'condition': reminder.condition,
                  'triggerType': reminder.triggerType,
                  'activity': reminder.activity,
                },
              ),
              const Spacer(),
              if (askNotifications) ...[
                Text(
                  'Turn on notifications so I can nudge you at the right moment.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                  icon: Icon(askNotifications ? Icons.notifications_active_rounded : Icons.thumb_up_rounded),
                  label: Text(askNotifications ? 'Turn on notifications' : 'Nice!'),
                  onPressed: () => Navigator.pop(context, askNotifications),
                ),
              ),
              if (askNotifications)
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Maybe later'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
