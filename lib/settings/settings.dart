import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../account.dart';
import '../calendar_sync.dart';
import '../collections.dart';
import 'categories.dart';
import 'developer_options.dart';
import 'locations.dart';
import 'theme_choice.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _packageInfo = PackageInfo.fromPlatform();

  /// Taps on the version that turn on developer options.
  static const _tapsToUnlock = 3;
  int _versionTaps = 0;

  Future<void> _onVersionTap() async {
    final messenger = ScaffoldMessenger.of(context);
    if (developerOptionsNotifier.value) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Developer options are already on')));
      return;
    }
    if (++_versionTaps < _tapsToUnlock) return;
    _versionTaps = 0;
    await setDeveloperOptions(true);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Developer options are on')));
  }
  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account'),
        content: const Text(
          'This permanently deletes your account and all your reminders, lists, '
          'categories and saved places. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await deleteAccount();
    } catch (e) {
      debugPrint('Delete account failed: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not finish deleting your account. Please try again.')),
      );
    }
  }

  bool _calendarBusy = false;

  /// Calendar access is asked for only here, when the user turns sync on.
  Future<void> _toggleCalendarSync(bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _calendarBusy = true);
    try {
      if (!on) {
        await disableCalendarSync();
        return;
      }
      final open = await remindersCollection().where('status', isEqualTo: 0).get();
      if (!await enableCalendarSync(open.docs)) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Calendar access is needed to show reminders in your calendar')),
        );
      }
    } catch (e) {
      debugPrint('Calendar sync toggle failed: $e');
      messenger.showSnackBar(const SnackBar(content: Text('Could not change calendar sync. Please try again.')));
    } finally {
      if (mounted) setState(() => _calendarBusy = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await signOut();
    } catch (e) {
      debugPrint('Sign out failed: $e');
    }
  }

  Future<void> _pickThemeMode() async {
    final picked = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Theme'),
        children: [
          RadioGroup<ThemeMode>(
            groupValue: themeModeNotifier.value,
            onChanged: (m) => Navigator.pop(context, m),
            child: Column(
              children: [
                for (final m in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    title: Text(themeModeLabel(m)),
                    subtitle: m == ThemeMode.system ? const Text('Follow phone settings') : null,
                    value: m,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) await setThemeMode(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
      children: [
        ListTile(
          title: const Text('Saved Locations'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const LocationsScreen()),
          ),
        ),
        const Divider(),
        StreamBuilder(
          stream: categoriesCollection().snapshots(),
          builder: (context, snapshot) {
            final docs = snapshot.data?.docs ?? [];
            final preview = docs
                .map((d) => '${d.data()['emoji'] ?? ''} ${d['name']}'.trim())
                .join(' · ');
            return ListTile(
              title: const Text('Categories'),
              subtitle: Text(
                preview.isEmpty ? 'No categories yet' : preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CategoriesScreen()),
              ),
            );
          },
        ),
        const Divider(),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeNotifier,
          builder: (context, mode, _) => ListTile(
            title: const Text('Theme'),
            trailing: Text(themeModeLabel(mode)),
            onTap: _pickThemeMode,
          ),
        ),
        const Divider(),
        ValueListenableBuilder<bool>(
          valueListenable: calendarSyncNotifier,
          builder: (context, enabled, _) => SwitchListTile(
            title: const Text('Sync with Device Calendar'),
            value: enabled,
            onChanged: _calendarBusy ? null : _toggleCalendarSync,
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: developerOptionsNotifier,
          builder: (context, enabled, _) => !enabled
              ? const SizedBox.shrink()
              : Column(
                  children: [
                    const Divider(),
                    ListTile(
                      title: const Text('Developer options'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(builder: (_) => const DeveloperOptionsScreen()),
                      ),
                    ),
                  ],
                ),
        ),
        const Divider(),
        if (FirebaseAuth.instance.currentUser?.isAnonymous == false)
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: _signOut,
          ),
        SizedBox(height: 16),
        TextButton(
          onPressed: _deleteAccount,
          child: const Text('Delete account', style: TextStyle(color: Colors.red)),
        ),
        SizedBox(height: 24),
        FutureBuilder<PackageInfo>(
          future: _packageInfo,
          builder: (context, snapshot) => GestureDetector(
            // Three taps turn on developer options.
            onTap: _onVersionTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                snapshot.hasData ? 'Version ${snapshot.data!.version}+${snapshot.data!.buildNumber}' : '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
        ),
      ],
    ),
  );
  }
}
