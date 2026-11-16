import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../activity_watch.dart';
import '../collections.dart';
import '../gemma/download.dart';
import '../llm/extractor.dart';
import '../llm/model_choice.dart';
import 'categories.dart';
import 'locations.dart';
import 'model.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account'),
        content: const Text(
          'Are you sure?',
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

    if (confirmed == true) {
      await FirebaseAuth.instance.currentUser!.delete();
      await GoogleSignIn.instance.signOut();
    }
  }

  Future<void> _signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('Sign out failed: $e');
    }
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
        ValueListenableBuilder<Duration>(
          valueListenable: pollPeriodNotifier,
          builder: (context, period, _) => ListTile(
            title: const Text('Poll period'),
            trailing: Text(formatPollPeriod(period)),
            onTap: _pickPollPeriod,
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
        ValueListenableBuilder<String>(
          valueListenable: activeBackendNotifier,
          builder: (context, backend, _) => Text(
            'Inference: $backend',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snapshot) => Text(
            'Version ${snapshot.data!.version}+${snapshot.data!.buildNumber}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ],
    ),
  );
  }
}
