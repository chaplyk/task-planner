// ignore_for_file: use_build_context_synchronously
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_geofence/native_geofence.dart';

import '../collections.dart';
import '../notifications.dart';
import '../permissions.dart';

@pragma('vm:entry-point')
Future<void> geofenceTriggered(GeofenceCallbackParams params) async {
  debugPrint('Geofence triggered with params: $params');

  await Firebase.initializeApp();
  for (final geofence in params.geofences) {
    final locationDoc = await locationsCollection().doc(geofence.id).get();
    final locationName = locationDoc.data()?['name'];

    String event;
    if (params.event == GeofenceEvent.enter) {
      event = "enter";
    } else if (params.event == GeofenceEvent.exit) {
      event = "exit";
    } else {
      return;
    }

    final snapshot = await remindersCollection()
        .where('status', isEqualTo: 0)
        .where('location', isEqualTo: locationName)
        .where('locationEvent', isEqualTo: event)
        .where('notified', isEqualTo: false)
        .get();

    for (final doc in snapshot.docs) {
      await showNotification(int.parse(doc.id), doc.data()['summary'] ?? 'Reminder');
      await doc.reference.update({'notified': true});
    }
  }
}

class LocationsScreen extends StatefulWidget {
  const LocationsScreen({super.key});

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  Position? _position;

  @override
  void initState() {
    super.initState();
    _fetchPosition();
  }

  Future<void> _fetchPosition() async {
    await requestBackgroundLocationPermission(context);

    final position = await Geolocator.getCurrentPosition();
    setState(() => _position = position);
  }

  Future<void> _addLocation(BuildContext context) async {
    final existingLocations = await locationsCollection().count().get();
    final existingLocationsCount = existingLocations.count ?? 0;
    if (existingLocationsCount >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can only have up to 10 locations')),
      );
      return;
    }

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name current location:'),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: 'Location Name')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Next'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')),
      );
      return;
    }

    await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add Location'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'gps'),
            child: const ListTile(
              leading: Icon(Icons.location_on),
              title: Text('Current GPS location'),
            ),
          ),
          const SimpleDialogOption(
            onPressed: null,
            child: ListTile(
              leading: Icon(Icons.wifi),
              title: Text('WiFi network'),
              subtitle: Text('Coming soon'),
            ),
          ),
        ],
      ),
    );

    await _addCurrentGpsLocation(context, name);
  }

  Future<void> _addCurrentGpsLocation(BuildContext context, String? name) async {
    var position = _position;
    position ??= await Geolocator.getCurrentPosition();

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
          IconButton(onPressed: () => _addLocation(context), icon: const Icon(Icons.add)),
        ],),
      body: StreamBuilder(
        stream: locationsCollection().snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          return ListView(
            children: [
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
