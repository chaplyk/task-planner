// ignore_for_file: use_build_context_synchronously
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_geofence/native_geofence.dart';

import '../collections.dart';
import '../permissions.dart';

@pragma('vm:entry-point')
Future<void> geofenceTriggered(GeofenceCallbackParams params) async {
  debugPrint('Geofence triggered with params: $params');
}

class LocationsScreen extends StatelessWidget {
  const LocationsScreen({super.key});

  Future<void> _addCurrentLocation(BuildContext context) async {
    await requestBackgroundLocationPermission(context);
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
      final doc = await locationsCollection().add({
        'name': name,
        'latitude': position.latitude,
        'longitude': position.longitude,
      });

      final zone = Geofence(
        id: doc.id,
        location: Location(
          latitude: position.latitude,
          longitude: position.longitude,
        ),
        radiusMeters: 75, // minimum recommended minimum 100-150, will adjust later
        triggers: {
          GeofenceEvent.enter,
          GeofenceEvent.exit,
        },
        iosSettings: IosGeofenceSettings(),
        androidSettings: AndroidGeofenceSettings(
          initialTriggers: {},
        ),
      );
      await NativeGeofenceManager.instance.createGeofence(zone, geofenceTriggered);
    }
  }

  Future<void> _deleteLocation(DocumentReference doc) async {
    await NativeGeofenceManager.instance.removeGeofenceById(doc.id);
    await doc.delete();
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
          final docs = snapshot.data?.docs ?? [];
          return ListView(
            children: [
              const SwitchListTile(
                title: Text('Enable Reminders (coming soon)'),
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
                      onPressed: () => _deleteLocation(doc.reference),
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
