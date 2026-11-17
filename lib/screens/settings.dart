import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../account.dart';
import '../collections.dart';
import '../gemma/download.dart';
import '../llm/extractor.dart';
import '../llm/model_choice.dart';
import '../theme_choice.dart';
import 'categories.dart';
import 'locations.dart';
import 'model.dart';
import 'store_debug.dart';

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
        if (kDebugMode)
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('Where am I? (debug)'),
            subtitle: const Text('Test store detection here and see its log'),
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const StoreDebugScreen())),
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
