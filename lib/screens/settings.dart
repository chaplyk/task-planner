import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:material_tag_editor/tag_editor.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../collections.dart';
import '../gemma/extractor.dart';
import 'locations.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
      children: [
        const Divider(),
        const ListTile(
          title: Text('Categories'),
        ),
        StreamBuilder(
          stream: categoriesCollection().snapshots(),
          builder: (context, snapshot) {
            final docs = snapshot.data?.docs ?? [];
            return TagEditor(
              length: docs.length,
              delimiters: const [',', ' '],
              hasAddButton: true,
              inputDecoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Add Category...',
              ),
              onTagChanged: (newValue) {
                categoriesCollection().add({'name': newValue});
              },
              tagBuilder: (context, index) => Chip(
                label: Text(docs[index]['name']),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () {
                  docs[index].reference.delete();
                },
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
