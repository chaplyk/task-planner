// ignore_for_file: use_build_context_synchronously
import 'package:material_ui/material_ui.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../collections.dart';
import '../geofence_callback.dart';
import '../permissions.dart';
import '../widgets/text_input_dialog.dart';
import 'place_details.dart';
import 'place_picker.dart';

const maxPlaces = 10;

/// What a new place is recognised by.
enum PlaceKind { gps, wifi }

/// Wi-Fi names come back from Android in quotes ("Home"): drop them for display.
String wifiDisplayName(String raw) =>
    raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"') ? raw.substring(1, raw.length - 1) : raw;

/// The Wi-Fi network the phone is on, or null when it isn't on one or the name is hidden
/// (Android hides it without location access).
Future<String?> currentWifiName() async {
  try {
    final name = await NetworkInfo().getWifiName();
    return name == null || name.isEmpty || name.contains('<unknown ssid>') ? null : name;
  } catch (e) {
    debugPrint('Wi-Fi name unavailable: $e');
    return null;
  }
}

/// Saves a new named place and returns its name, or null if the user cancelled.
/// [kind] given (the Saved Locations add menu, the unknown place sheet): goes straight to
/// the map picker or the current Wi-Fi. Without it, offers both when the phone is on
/// Wi-Fi, and otherwise opens the map. [initialName] pre-fills the name.
Future<String?> addPlace(BuildContext context, {String? initialName, PlaceKind? kind}) async {
  if (kind != null) return _addPlaceOfKind(context, kind, initialName: initialName);
  final wifi = await currentWifiName();
  if (!context.mounted) return null;
  if (wifi == null) return _addPlaceOfKind(context, PlaceKind.gps, initialName: initialName);

  final picked = await showModalBottomSheet<PlaceKind>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Add a place', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('Pin on the map'),
                onPressed: () => Navigator.pop(context, PlaceKind.gps),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                icon: const Icon(Icons.wifi_rounded),
                label: Text('Use Wi-Fi “${wifiDisplayName(wifi)}”'),
                onPressed: () => Navigator.pop(context, PlaceKind.wifi),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (picked == null || !context.mounted) return null;
  return _addPlaceOfKind(context, picked, initialName: initialName);
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

Future<String?> _addPlaceOfKind(BuildContext context, PlaceKind kind, {String? initialName}) async {
  void snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  final count = (await locationsCollection().count().get()).count ?? 0;
  if (count >= maxPlaces) {
    snack('You can only have up to $maxPlaces locations');
    return null;
  }
  // Both need location access: Android hides the Wi-Fi name without it.
  await requestBackgroundLocationPermission(context);
  if (!context.mounted) return null;

  if (kind == PlaceKind.gps) return _addPinnedPlace(context, initialName: initialName);

  // Known at once: no point asking for a name when there's no network.
  final wifi = await NetworkInfo().getWifiName().catchError((Object e) {
    debugPrint('Wi-Fi name unavailable: $e');
    return null;
  });
  if (!context.mounted) return null;
  if (wifi == null) {
    snack('Connect to the Wi-Fi network you want to save first');
    return null;
  }
  final name = await _askPlaceName(
    context,
    title: 'Name the place with “${wifiDisplayName(wifi)}”',
    initial: initialName ?? '',
    hint: 'e.g. Home',
  );
  if (name == null) return null;
  sendWrite(locationsCollection().doc().set({'name': name, 'wifi': wifi}));
  return name;
}

/// Lets the user place a pin on a map (starting at their position), then name it.
Future<String?> _addPinnedPlace(BuildContext context, {String? initialName}) async {
  // Without a position, the map opens on the last saved GPS place.
  LatLng? fallback;
  try {
    for (final d in (await locationsCollection().get()).docs.reversed) {
      final lat = d.data()['latitude'], lon = d.data()['longitude'];
      if (lat is num && lon is num) {
        fallback = LatLng(lat.toDouble(), lon.toDouble());
        break;
      }
    }
  } catch (_) {}
  if (!context.mounted) return null;
  final picked = await pickPlaceOnMap(context, fallback: fallback);
  if (picked == null || !context.mounted) return null;
  final name = await _askPlaceName(
    context,
    title: 'Name this place',
    initial: initialName ?? picked.suggestedName ?? '',
    hint: 'e.g. Gym',
  );
  if (name == null) return null;
  final doc = locationsCollection().doc();
  sendWrite(doc.set({'name': name, 'latitude': picked.point.latitude, 'longitude': picked.point.longitude}));
  await _registerGeofence(doc.id, picked.point.latitude, picked.point.longitude);
  return name;
}

/// The name for a new place, trimmed; null if cancelled or left empty.
Future<String?> _askPlaceName(BuildContext context, {required String title, required String initial, required String hint}) async {
  final name = (await showTextInputDialog(
    context,
    title: title,
    action: 'Save',
    initial: initial,
    hintText: hint,
    filledAction: true,
  ))?.trim();
  if (name == null || !context.mounted) return null;
  if (name.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name cannot be empty')));
    return null;
  }
  return name;
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

/// Deletes a saved place: its geofence (GPS places only), cached maps and document.
Future<void> deletePlace(PlaceDoc doc) async {
  final data = doc.data() ?? const {};
  if (data['latitude'] is num) {
    try {
      await NativeGeofenceManager.instance.removeGeofenceById(doc.id);
    } catch (e) {
      debugPrint('Removing geofence ${doc.id} failed: $e');
    }
  }
  await deletePlaceMaps(doc.id);
  sendWrite(doc.reference.delete());
}

class LocationsScreen extends StatefulWidget {
  const LocationsScreen({super.key});

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  bool _adding = false;

  /// Where the user is, for "2.4 km away"; null until known or without location access.
  Position? _here;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  /// Uses location access only if already granted: this screen never asks for it.
  Future<void> _locate() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) return;
      // The last known fix shows distances at once; a fresh one corrects them.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) setState(() => _here = last);
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)),
      );
      if (mounted) setState(() => _here = current);
    } catch (e) {
      debugPrint('Saved places: no position: $e');
    }
  }

  /// "2.4 km away" for a GPS place, when the user's position is known.
  String? _distance(Map<String, dynamic> data) {
    final here = _here, lat = data['latitude'], lon = data['longitude'];
    if (here == null || lat is! num || lon is! num) return null;
    return distanceLabel(Geolocator.distanceBetween(here.latitude, here.longitude, lat.toDouble(), lon.toDouble()));
  }

  void _add(PlaceKind kind) {
    setState(() => _adding = false);
    addPlace(context, kind: kind);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Locations')),
      floatingActionButton: _AddPlaceDial(
        open: _adding,
        onToggle: () => setState(() => _adding = !_adding),
        onPick: _add,
      ),
      body: Stack(
        children: [
          _list(),
          // Dims the list while the add options are up; a tap outside closes them.
          IgnorePointer(
            ignoring: !_adding,
            child: AnimatedOpacity(
              opacity: _adding ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: () => setState(() => _adding = false),
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.32),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list() {
    return StreamBuilder(
      stream: locationsCollection().snapshots(),
      builder: (context, places) {
        // One listener for every place's reminder count, for the warning on Delete.
        return StreamBuilder(
          stream: remindersCollection()
              .where('status', isEqualTo: 0)
              .where('triggerType', isEqualTo: 'location')
              .snapshots(),
          builder: (context, reminders) {
            final byPlace = <String, int>{};
            for (final d in reminders.data?.docs ?? const []) {
              final location = d.data()['location'];
              if (location is String) byPlace[location] = (byPlace[location] ?? 0) + 1;
            }
            final docs = [...?places.data?.docs]
              ..sort((a, b) => (a.data()['name'] as String? ?? '').toLowerCase().compareTo(
                    (b.data()['name'] as String? ?? '').toLowerCase(),
                  ));
            if (!places.hasData) return const Center(child: CircularProgressIndicator());
            if (docs.isEmpty) return const _Empty();
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final doc = docs[i];
                final name = doc.data()['name'] as String? ?? '';
                final distance = _distance(doc.data());
                return _PlaceCard(
                  doc: doc,
                  distance: distance,
                  onTap: () => showPlaceDetails(
                    context,
                    place: doc,
                    reminderCount: byPlace[name] ?? 0,
                    distance: distance,
                    onDelete: () => deletePlace(doc),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// "Add a place" button; when open, the two ways to save a place slide up above it.
class _AddPlaceDial extends StatelessWidget {
  const _AddPlaceDial({required this.open, required this.onToggle, required this.onPick});

  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<PlaceKind> onPick;

  Widget _option(BuildContext context, int index, PlaceKind kind, IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedSlide(
      offset: open ? Offset.zero : Offset(0, 0.6 + index * 0.4),
      duration: Duration(milliseconds: 180 + index * 50),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: open ? 1 : 0,
        duration: Duration(milliseconds: 140 + index * 50),
        child: IgnorePointer(
          ignoring: !open,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FloatingActionButton.extended(
              heroTag: 'add_place_${kind.name}',
              backgroundColor: scheme.secondaryContainer,
              foregroundColor: scheme.onSecondaryContainer,
              elevation: 2,
              onPressed: () => onPick(kind),
              icon: Icon(icon),
              label: Text(label),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _option(context, 1, PlaceKind.wifi, Icons.wifi_rounded, 'Save current Wi-Fi'),
        _option(context, 0, PlaceKind.gps, Icons.add_location_alt_rounded, 'Pin on the map'),
        FloatingActionButton.extended(
          heroTag: 'add_place',
          onPressed: onToggle,
          icon: AnimatedRotation(
            turns: open ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.add_rounded),
          ),
          label: Text(open ? 'Close' : 'Add a place'),
        ),
      ],
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.doc, required this.onTap, this.distance});

  final PlaceDoc doc;

  /// How far the user is; the coordinates are shown while it's unknown.
  final String? distance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final data = doc.data() ?? const {};
    final wifi = data['wifi'] as String?;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              PlaceIcon(wifi: wifi != null),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['name'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      wifi != null
                          ? 'Wi-Fi · ${wifiDisplayName(wifi)}'
                          : distance ?? '${data['latitude']}, ${data['longitude']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📍', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text('No saved places yet', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Save places like home or the gym to get reminded when you arrive or leave.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
