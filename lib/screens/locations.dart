import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../collections.dart';

class LocationsScreen extends StatelessWidget {
  const LocationsScreen({super.key});

  Future<void> _addCurrentLocation(BuildContext context) async {
    await Geolocator.requestPermission();
    final position = await Geolocator.getCurrentPosition();

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Current Location'),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: 'Location Name')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name != null) {
      await locationsCollection().add({
        'name': name,
        'latitude': position.latitude,
        'longitude': position.longitude,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Locations'),
              actions: [
          IconButton(onPressed: () => _addCurrentLocation(context), icon: const Icon(Icons.add)),
        ],),
      body: StreamBuilder(
        stream: locationsCollection().snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data!.docs;
          return ListView(
            children: [
              const SwitchListTile(
                title: Text('Enable reminders (coming soon)'),
                value: false,
                onChanged: null,
              ),
              const Divider(),
              ...docs.map(
                  (doc) => ListTile(
                    title: Text(doc.data()['name']),
                    subtitle: Text('${doc.data()['latitude']}, ${doc.data()['longitude']}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => doc.reference.delete(),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
