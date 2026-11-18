import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../geoapify.dart';

typedef PlaceDoc = DocumentSnapshot<Map<String, dynamic>>;

/// Within this of a saved GPS place (its geofence radius) the user counts as there.
const _hereRadiusMeters = 75;

/// "You're here" at the place, else "350 m away" / "2.4 km away".
String distanceLabel(double meters) {
  if (meters <= _hereRadiusMeters) return 'You’re here';
  if (meters < 1000) return '${(meters / 10).round() * 10} m away';
  final km = meters / 1000;
  return '${km < 10 ? km.toStringAsFixed(1) : km.round()} km away';
}

const _mapZoom = 16;
const _mapWidth = 600;
const _mapHeight = 338; // 16:9

/// Geoapify static map of a place with a pin. Light or dark to match the theme.
/// (No geofence circle: the API draws circle radii in pixels, not meters.)
Uri staticMapUri({
  required double lat,
  required double lon,
  required bool dark,
  required Color pin,
  String apiKey = geoapifyApiKey,
}) {
  final lonLat = '${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)}';
  final hex = pin.toARGB32().toRadixString(16).padLeft(8, '0').substring(2);
  return Uri.parse('$geoapifyMapsBase/staticmap').replace(queryParameters: {
    'style': geoapifyMapStyle(dark: dark),
    'width': '$_mapWidth',
    'height': '$_mapHeight',
    'scaleFactor': '2',
    'center': 'lonlat:$lonLat',
    'zoom': '$_mapZoom',
    'marker': 'lonlat:$lonLat;color:#$hex;size:large',
    'apiKey': apiKey,
  });
}

Future<File> _mapFile(String placeId, bool dark) async =>
    File('${(await getApplicationSupportDirectory()).path}/place_maps/$placeId-${dark ? 'dark' : 'light'}.jpg');

/// The place's map image, downloaded once per theme and kept on the phone
/// (each download costs Geoapify credits). Null when it can't be had.
Future<File?> placeMap(String placeId, double lat, double lon, {required bool dark, required Color pin}) async {
  try {
    final file = await _mapFile(placeId, dark);
    if (await file.exists()) return file;
    if (!geoapifyConfigured) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(staticMapUri(lat: lat, lon: lon, dark: dark, pin: pin));
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        debugPrint('Place map: HTTP ${response.statusCode}');
        return null;
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } finally {
      client.close();
    }
  } catch (e) {
    debugPrint('Place map failed: $e');
    return null;
  }
}

/// Forgets a deleted place's map images.
Future<void> deletePlaceMaps(String placeId) async {
  for (final dark in [false, true]) {
    try {
      final file = await _mapFile(placeId, dark);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

/// Details of a saved place: its map (GPS) or network (Wi-Fi), and Delete.
/// [reminderCount] open reminders use it (Delete warns about them); [onDelete] deletes it.
Future<void> showPlaceDetails(
  BuildContext context, {
  required PlaceDoc place,
  required int reminderCount,
  required Future<void> Function() onDelete,
  String? distance,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => _PlaceDetails(place: place, reminderCount: reminderCount, onDelete: onDelete, distance: distance),
  );
}

class _PlaceDetails extends StatelessWidget {
  const _PlaceDetails({required this.place, required this.reminderCount, required this.onDelete, this.distance});

  final PlaceDoc place;

  /// How far the user is, e.g. "2.4 km away"; null when unknown.
  final String? distance;
  final int reminderCount;
  final Future<void> Function() onDelete;

  Future<void> _confirmDelete(BuildContext context) async {
    final name = place.data()?['name'] ?? 'this place';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “$name”?'),
        content: Text(
          reminderCount == 0
              ? 'It will be removed from your saved places.'
              : '${reminderCount == 1 ? 'A reminder uses' : '$reminderCount reminders use'} this place. '
                  'They won’t fire until you save a place with this name again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    Navigator.pop(context);
    await onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final data = place.data() ?? const {};
    final wifi = data['wifi'] as String?;
    final lat = (data['latitude'] as num?)?.toDouble();
    final lon = (data['longitude'] as num?)?.toDouble();

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        Row(
          children: [
            PlaceIcon(wifi: wifi != null, size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(data['name'] as String? ?? '', style: theme.textTheme.headlineSmall),
                  Text(
                    wifi != null ? 'Wi-Fi place' : ['GPS place', ?distance].join(' · '),
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (wifi != null)
          _WifiCard(network: wifi)
        else if (lat != null && lon != null) ...[
          _MiniMap(placeId: place.id, lat: lat, lon: lon),
          const SizedBox(height: 6),
          Text(
            '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 24),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.error,
            side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () => _confirmDelete(context),
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Delete place'),
        ),
      ],
    );
  }
}

/// Round icon for a place: a pin for GPS, the Wi-Fi symbol for a network.
class PlaceIcon extends StatelessWidget {
  const PlaceIcon({super.key, required this.wifi, this.size = 44});

  final bool wifi;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: wifi ? scheme.tertiaryContainer : scheme.primaryContainer,
      ),
      child: Icon(
        wifi ? Icons.wifi_rounded : Icons.place_rounded,
        size: size * 0.5,
        color: wifi ? scheme.onTertiaryContainer : scheme.onPrimaryContainer,
      ),
    );
  }
}

class _WifiCard extends StatelessWidget {
  const _WifiCard({required this.network});

  final String network;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(Icons.wifi_rounded, size: 48, color: scheme.onTertiaryContainer),
          const SizedBox(height: 8),
          Text(
            network.length >= 2 && network.startsWith('"') && network.endsWith('"')
                ? network.substring(1, network.length - 1)
                : network,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Detected when your phone joins or leaves this network',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _MiniMap extends StatefulWidget {
  const _MiniMap({required this.placeId, required this.lat, required this.lon});

  final String placeId;
  final double lat, lon;

  @override
  State<_MiniMap> createState() => _MiniMapState();
}

class _MiniMapState extends State<_MiniMap> {
  Future<File?>? _file;
  bool? _dark;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    if (dark == _dark) return;
    _dark = dark;
    _file = placeMap(widget.placeId, widget.lat, widget.lon, dark: dark, pin: theme.colorScheme.primary);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AspectRatio(
        aspectRatio: _mapWidth / _mapHeight,
        child: FutureBuilder<File?>(
          future: _file,
          builder: (context, snapshot) {
            final file = snapshot.data;
            final placeholder = Container(
              color: scheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: snapshot.connectionState == ConnectionState.done
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map_outlined, size: 40, color: scheme.onSurfaceVariant),
                        const SizedBox(height: 6),
                        Text('Map unavailable', style: TextStyle(color: scheme.onSurfaceVariant)),
                      ],
                    )
                  : Icon(Icons.place_rounded, size: 40, color: scheme.primary.withValues(alpha: 0.5)),
            );
            if (file == null) return placeholder;
            return Image.file(
              file,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => placeholder,
            );
          },
        ),
      ),
    );
  }
}
