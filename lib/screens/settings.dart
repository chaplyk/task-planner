import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../account.dart';
import '../activity_watch.dart';
import '../collections.dart';
import '../gemma/download.dart';
import '../llm/extractor.dart';
import '../llm/model_choice.dart';
import '../place_types.dart';
import '../store_detection.dart';
import '../theme_choice.dart';
import 'categories.dart';
import 'locations.dart';
import 'model.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _packageInfo = PackageInfo.fromPlatform();
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

  Future<void> _signOut() async {
    try {
      await signOut();
    } catch (e) {
      debugPrint('Sign out failed: $e');
    }
  }

  /// Debug: runs the same lookup the background store check uses, right here.
  Future<void> _whereAmI() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Looking around…')));
    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('No position: $e')));
      return;
    }
    final radius = searchRadius(position);
    final stores = await nearbyStores(position, storeTypes.keys.toSet(), radius: 300);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stores within 300 m'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                'Fix accuracy ±${position.accuracy.round()} m · '
                'background check radius ${radius.round()} m',
              ),
              const SizedBox(height: 8),
              if (stores == null)
                const Text('Lookup failed: OpenStreetMap servers are busy. Try again in a minute.')
              else if (stores.isEmpty)
                const Text('No matching stores in OpenStreetMap here.'),
              for (final s in stores ?? const <NearbyStore>[])
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Text(
                    s.storeKeys.map((k) => storeTypes[k]!.emoji).join(),
                    style: const TextStyle(fontSize: 20),
                  ),
                  title: Text(s.name),
                  subtitle: Text(
                    '${s.distance.round()} m${s.distance <= radius ? ' · would trigger' : ''}',
                  ),
                ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
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

  Future<void> _pickPollPeriod() async {
    final picked = await showDialog<Duration>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Poll period'),
        children: [
          RadioGroup<Duration>(
            groupValue: pollPeriodNotifier.value,
            onChanged: (d) => Navigator.pop(context, d),
            child: Column(
              children: [
                for (final d in pollPeriods)
                  RadioListTile<Duration>(title: Text(formatPollPeriod(d)), value: d),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) await setPollPeriod(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
      children: [
        ValueListenableBuilder<LlmModel>(
          valueListenable: modelChoiceNotifier,
          builder: (context, model, _) => ListTile(
            title: const Text('Model'),
            subtitle: ValueListenableBuilder<int?>(
              valueListenable: localModelDownload,
              builder: (context, percent, _) => Text(
                percent == null ? modelLabel(model) : 'Downloading on-device model... $percent%',
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ModelScreen()),
            ),
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
        ListTile(
          title: const Text('Saved Locations'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const LocationsScreen()),
          ),
        ),
        const Divider(),
        const SwitchListTile(
          title: Text('Sync Calendar (coming soon)'),
          value: false,
          onChanged: null,
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
        ValueListenableBuilder<Duration>(
          valueListenable: pollPeriodNotifier,
          builder: (context, period, _) => ListTile(
            title: const Text('Poll period'),
            trailing: Text(formatPollPeriod(period)),
            onTap: _pickPollPeriod,
          ),
        ),
        if (kDebugMode)
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('Where am I? (debug)'),
            subtitle: const Text('Test store detection here (OpenStreetMap)'),
            onTap: _whereAmI,
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
        ValueListenableBuilder<String>(
          valueListenable: activeBackendNotifier,
          builder: (context, backend, _) => Text(
            'Inference: $backend',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        FutureBuilder<PackageInfo>(
          future: _packageInfo,
          builder: (context, snapshot) => Text(
            snapshot.hasData ? 'Version ${snapshot.data!.version}+${snapshot.data!.buildNumber}' : '',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ],
    ),
  );
  }
}
