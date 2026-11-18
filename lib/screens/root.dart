import 'package:material_ui/material_ui.dart';

import '../collections.dart';
import '../notifications.dart';
import '../widgets/reminder_details_sheet.dart';
import '../widgets/routine_history_sheet.dart';
import 'home.dart';
import 'lists_screen.dart';
import 'routines.dart';
import '../settings/settings.dart';

// base screen with bottom navigation
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _currentIndex = 0;

  void _select(int index) => setState(() => _currentIndex = index);

  @override
  void initState() {
    super.initState();
    openedNotification.addListener(_openNotification);
    // A tap that launched the app arrived before this screen existed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openNotification());
  }

  @override
  void dispose() {
    openedNotification.removeListener(_openNotification);
    super.dispose();
  }

  /// Shows the details of the reminder or routine whose notification was tapped.
  Future<void> _openNotification() async {
    final target = openedNotification.value;
    if (target == null || !mounted) return;
    openedNotification.value = null;
    // Older notifications don't say which they are about: reminders first, then routines.
    final reminder = target.kind == NotificationKind.routine ? null : await remindersCollection().doc(target.id).get();
    if (!mounted) return;
    if (reminder != null && reminder.exists) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      await showReminderDetails(context, reminder);
      return;
    }
    final routine = target.kind == NotificationKind.reminder ? null : await recurringCollection().doc(target.id).get();
    if (!mounted) return;
    if (routine != null && routine.exists) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      await showRoutineHistory(context, routine);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This reminder was deleted')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(onSeeAll: () => _select(1)),
          const ListsScreen(),
          const RoutinesScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Lists',
          ),
          NavigationDestination(
            icon: Icon(Icons.autorenew_outlined),
            selectedIcon: Icon(Icons.autorenew_rounded),
            label: 'Routines',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
