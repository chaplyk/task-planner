// ignore_for_file: use_build_context_synchronously
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../collections.dart';
import '../notifications.dart';
import '../permissions.dart';
import '../widgets/text_input_dialog.dart';

const maxPlaces = 10;

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

/// Saves the user's current position (GPS geofence) or Wi-Fi network as a named place.
/// [initialName] pre-fills the name, e.g. a place mentioned in a reminder.
/// Returns the saved name, or null if the user cancelled.
Future<String?> addPlace(BuildContext context, {String? initialName}) async {
  void snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  final count = (await locationsCollection().count().get()).count ?? 0;
  if (count >= maxPlaces) {
    snack('You can only have up to $maxPlaces locations');
    return null;
  }

  await requestBackgroundLocationPermission(context);
  if (!context.mounted) return null;

  // Fetch while the user types the name.
  final positionFuture = Geolocator.getCurrentPosition()
      .then<Position?>((p) => p)
      .catchError((Object e) {
    debugPrint('Position unavailable: $e');
    return null;
  });
  final wifiFuture = NetworkInfo().getWifiName().catchError((Object e) {
    debugPrint('Wi-Fi name unavailable: $e');
    return null;
  });

  final name = await showTextInputDialog(
    context,
    title: 'Name current location:',
    action: 'Next',
    initial: initialName ?? '',
    hintText: 'Location Name',
  );
  if (name == null) return null;
  if (name.isEmpty) {
    snack('Name cannot be empty');
    return null;
  }

  final position = await positionFuture;
  final wifi = await wifiFuture;
  if (!context.mounted) return null;

  final type = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Choose Location Type'),
      children: [
        SimpleDialogOption(
          onPressed: position == null ? null : () => Navigator.pop(context, 'gps'),
          child: ListTile(
            enabled: position != null,
            leading: const Icon(Icons.location_on),
            title: const Text('GPS Position'),
            subtitle: Text(
              position == null ? 'Unavailable' : '${position.latitude}, ${position.longitude}',
            ),
          ),
        ),
        SimpleDialogOption(
          onPressed: wifi == null ? null : () => Navigator.pop(context, 'wifi'),
          child: ListTile(
            enabled: wifi != null,
            leading: const Icon(Icons.wifi),
            title: const Text('WiFi Network'),
            subtitle: Text(wifi ?? 'Not connected'),
          ),
        ),
      ],
    ),
  );

  if (type == 'wifi' && wifi != null) {
    sendWrite(locationsCollection().doc().set({'name': name, 'wifi': wifi}));
    return name;
  }
  if (type == 'gps' && position != null) {
    final doc = locationsCollection().doc();
    sendWrite(doc.set({
      'name': name,
      'latitude': position.latitude,
      'longitude': position.longitude,
    }));
    await _registerGeofence(doc.id, position.latitude, position.longitude);
    return name;
  }
  return null;
}

Future<void> _registerGeofence(String id, double latitude, double longitude) {
  final zone = Geofence(
    id: id,
    location: Location(latitude: latitude, longitude: longitude),
    radiusMeters: 75, // minimum recommended minimum 100-150, will adjust later
    triggers: {GeofenceEvent.enter, GeofenceEvent.exit},
    iosSettings: IosGeofenceSettings(),
    androidSettings: AndroidGeofenceSettings(initialTriggers: {}),
  );
  return NativeGeofenceManager.instance.createGeofence(zone, geofenceTriggered);
}

/// Registers the geofences of saved GPS places that this device doesn't watch yet.
/// Geofences live on the device, so they are missing after signing in again or on
/// another phone, or after a reinstall.
Future<void> syncGeofences() async {
  try {
    final places = await locationsCollection().get();
    final registered = (await NativeGeofenceManager.instance.getRegisteredGeofenceIds()).toSet();
    for (final doc in places.docs) {
      final lat = doc.data()['latitude'], lng = doc.data()['longitude'];
      if (lat is! num || lng is! num || registered.contains(doc.id)) continue;
      await _registerGeofence(doc.id, lat.toDouble(), lng.toDouble());
    }
  } catch (e) {
    // Most likely no location permission yet; it is asked for when a place reminder is saved.
    debugPrint('Geofence sync failed: $e');
  }
}

class LocationsScreen extends StatelessWidget {
  const LocationsScreen({super.key});

  Future<void> _deleteLocation(DocumentReference doc) async {
    await NativeGeofenceManager.instance.removeGeofenceById(doc.id); // TO ADD: do not remove for wifi location
    sendWrite(doc.delete());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Locations'),
        actions: [
          IconButton(onPressed: () => addPlace(context), icon: const Icon(Icons.add)),
        ],
      ),
      body: StreamBuilder(
        stream: locationsCollection().snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          return ListView(
            children: [
              ...docs.map(
                (doc) => ListTile(
                  title: Text(doc.data()['name']),
                  subtitle: Text(
                    doc.data()['wifi'] ?? '${doc.data()['latitude']}, ${doc.data()['longitude']}',
                  ),
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

