import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show lerpDouble;

import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../geoapify.dart';

/// The spot chosen on the map, and a name for it from its address (may be null).
typedef PickedPlace = ({LatLng point, String? suggestedName});

/// Reminders for a saved GPS place fire within this of its pin (its geofence radius).
const _reminderRadiusMeters = 75.0;

const _pinSize = 56.0;
const _liftHeight = 22.0;

/// Full-screen map with a pin in the middle: move the map (or tap, or search) to place
/// it, then "Save this place". Opens on the user's position when location access is
/// granted, else on [fallback], else on the whole world.
Future<PickedPlace?> pickPlaceOnMap(BuildContext context, {LatLng? fallback}) =>
    Navigator.push<PickedPlace>(
      context,
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => _PlacePicker(fallback: fallback)),
    );

class _PlacePicker extends StatefulWidget {
  const _PlacePicker({this.fallback});

  final LatLng? fallback;

  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> with TickerProviderStateMixin {
  final _map = MapController();
  final _search = SearchController();

  /// 0 = pin on the ground, 1 = lifted (the map is moving).
  late final _lift = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
  late final _ripple = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  AnimationController? _flight;

  ({LatLng center, double zoom})? _start; // null while looking for the first position
  late LatLng _center;
  LatLng? _me;
  bool _ready = false; // the map can be moved only once it's laid out
  bool _moving = false;
  bool _touched = false; // the user moved the map: stop following the first fix
  Timer? _settle;

  GeocodeResult? _address;
  bool _findingAddress = false;
  int _addressRequest = 0;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _settle?.cancel();
    _flight?.dispose();
    _lift.dispose();
    _ripple.dispose();
    _search.dispose();
    _map.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- position

  Future<bool> _hasLocationAccess() async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  /// Opens on the last known position at once, then glides to a fresh fix.
  Future<void> _locate() async {
    LatLng? last;
    var access = false;
    try {
      access = await _hasLocationAccess();
      if (access) {
        final p = await Geolocator.getLastKnownPosition().timeout(const Duration(seconds: 2));
        if (p != null) last = LatLng(p.latitude, p.longitude);
      }
    } catch (e) {
      debugPrint('Place picker: no last position: $e');
    }
    if (!mounted) return;
    final center = last ?? widget.fallback;
    setState(() {
      _me = last;
      _start = center == null ? (center: const LatLng(30, 10), zoom: 2.5) : (center: center, zoom: 17);
      _center = _start!.center;
    });
    if (center != null) _lookUpAddress(center);
    if (!access) return;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      if (!mounted) return;
      final fresh = LatLng(p.latitude, p.longitude);
      setState(() => _me = fresh);
      if (!_touched) _flyTo(fresh, zoom: 17);
    } catch (e) {
      debugPrint('Place picker: no fresh position: $e');
    }
  }

  // ---------------------------------------------------------------- camera

  /// Glides the camera to [target], easing position and zoom together.
  void _flyTo(LatLng target, {double? zoom}) {
    if (!_ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _flyTo(target, zoom: zoom);
      });
      return;
    }
    final from = _map.camera;
    final toZoom = zoom ?? from.zoom;
    final far = const Distance().as(LengthUnit.Kilometer, from.center, target) > 50;
    _flight?.dispose();
    final flight = _flight = AnimationController(vsync: this, duration: Duration(milliseconds: far ? 900 : 550));
    final t = CurvedAnimation(parent: flight, curve: Curves.easeInOutCubic);
    flight.addListener(() {
      final v = t.value;
      // Far jumps zoom out midway, so the trip reads as a flight rather than a smear.
      final dip = far ? (1 - (2 * v - 1) * (2 * v - 1)) * 3 : 0.0;
      _map.move(
        LatLng(lerpDouble(from.center.latitude, target.latitude, v)!, lerpDouble(from.center.longitude, target.longitude, v)!),
        lerpDouble(from.zoom, toZoom, v)! - dip,
      );
    });
    flight.forward();
  }

  void _onMapEvent(MapEvent event) {
    if (event is! MapEventWithMove) return;
    _center = event.camera.center;
    if (event.source != MapEventSource.mapController) _touched = true;
    if (!_moving) {
      _moving = true;
      _lift.animateTo(1, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
      setState(() {});
    }
    // Drags, flings, zooms and glides all end the same way: no move for a moment.
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 180), _drop);
  }

  void _drop() {
    if (!mounted) return;
    setState(() => _moving = false);
    _lift.animateTo(0, duration: const Duration(milliseconds: 650), curve: Curves.bounceOut);
    // The first impact of bounceOut lands at about a third of the way.
    Future<void>.delayed(const Duration(milliseconds: 230), () {
      if (!mounted || _moving) return;
      HapticFeedback.lightImpact();
      _ripple.forward(from: 0);
    });
    _lookUpAddress(_center);
  }

  // ---------------------------------------------------------------- Geoapify

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    if (!geoapifyConfigured) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final response = await (await client.getUrl(uri)).close().timeout(const Duration(seconds: 10));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) return null;
      return (jsonDecode(body) as Map).cast<String, dynamic>();
    } catch (e) {
      debugPrint('Place picker: request failed: $e');
      return null;
    } finally {
      client.close();
    }
  }

  /// The address under the pin, shown in the card and offered as the place's name.
  Future<void> _lookUpAddress(LatLng at) async {
    final request = ++_addressRequest;
    setState(() => _findingAddress = true);
    // Waits until the pin has rested, so a quick nudge after a drop costs one lookup.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted || request != _addressRequest) return;
    final json = await _getJson(reverseGeocodeUri(lat: at.latitude, lon: at.longitude));
    if (!mounted || request != _addressRequest) return;
    final results = json == null ? const <GeocodeResult>[] : parseGeocodeResults(json);
    setState(() {
      _address = results.firstOrNull;
      _findingAddress = false;
    });
  }

  String _lastQuery = '';
  Iterable<Widget> _lastSuggestions = const [];

  Future<Iterable<Widget>> _suggestions(BuildContext context, SearchController controller) async {
    final query = controller.text.trim();
    if (query.length < 4) return const [];
    if (query == _lastQuery) return _lastSuggestions;
    // Debounce: only the query still in the field after a pause is sent (1 credit each).
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (controller.text.trim() != query) return _lastSuggestions;
    final near = _center;
    final json = await _getJson(autocompleteUri(query, lat: near.latitude, lon: near.longitude));
    final results = json == null ? const <GeocodeResult>[] : parseGeocodeResults(json);
    _lastQuery = query;
    _lastSuggestions = results.isEmpty
        ? [const ListTile(leading: Icon(Icons.search_off_rounded), title: Text('No matches'))]
        : [
            for (final r in results)
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: r.subtitle == null ? null : Text(r.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  controller.closeView(r.title);
                  FocusScope.of(context).unfocus();
                  _touched = true;
                  _flyTo(LatLng(r.lat, r.lon), zoom: 17);
                },
              ),
          ];
    return _lastSuggestions;
  }

  // ---------------------------------------------------------------- build

  void _save() {
    final a = _address;
    Navigator.pop<PickedPlace>(context, (point: _center, suggestedName: a?.name ?? a?.title));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final start = _start;
    if (start == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final dark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: start.center,
              initialZoom: start.zoom,
              minZoom: 2,
              maxZoom: 19,
              onMapReady: () => _ready = true,
              onMapEvent: _onMapEvent,
              onTap: (_, point) {
                _touched = true;
                _flyTo(point);
              },
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            ),
            children: [
              TileLayer(
                urlTemplate: geoapifyTileUrl(dark: dark),
                retinaMode: RetinaMode.isHighDensity(context),
                userAgentPackageName: 'com.chaplyk.memory',
                maxZoom: 19,
              ),
              // The reminder area: hidden while moving, back around the pin once it lands.
              AnimatedOpacity(
                opacity: _moving ? 0 : 1,
                duration: Duration(milliseconds: _moving ? 120 : 350),
                child: CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _center,
                      radius: _reminderRadiusMeters,
                      useRadiusInMeter: true,
                      color: scheme.primary.withValues(alpha: 0.14),
                      borderColor: scheme.primary.withValues(alpha: 0.7),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
          IgnorePointer(child: Center(child: _pin(scheme))),
          SafeArea(child: _topBar(scheme)),
          Positioned(left: 0, right: 0, bottom: 0, child: _bottom(theme)),
        ],
      ),
    );
  }

  /// The pin, its shadow, the line to the exact spot while lifted, the landing ripple,
  /// and the first-time hint. Its tip sits exactly at the map's centre.
  Widget _pin(ColorScheme scheme) {
    return AnimatedBuilder(
      animation: Listenable.merge([_lift, _ripple]),
      builder: (context, _) {
        final lift = _lift.value.clamp(-0.2, 1.2);
        final r = _ripple.value;
        return SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Landing ripple.
              if (_ripple.isAnimating)
                Container(
                  width: 16 + r * 96,
                  height: 16 + r * 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.primary.withValues(alpha: (1 - r) * 0.8), width: 2.5),
                  ),
                ),
              // Ground shadow: smaller and fainter the higher the pin.
              Transform.scale(
                scale: 1 - 0.45 * lift.clamp(0, 1),
                child: Container(
                  width: 18,
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.black.withValues(alpha: 0.28 * (1 - 0.6 * lift.clamp(0, 1))),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 4)],
                  ),
                ),
              ),
              // While lifted, a line and a dot mark the exact spot under the pin.
              if (lift > 0.05) ...[
                Transform.translate(
                  offset: Offset(0, -lift * _liftHeight / 2),
                  child: Container(width: 2, height: lift * _liftHeight, color: scheme.primary.withValues(alpha: 0.8)),
                ),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary),
                ),
              ],
              // The pin: its tip (bottom of the icon) at the centre, raised by the lift.
              Transform.translate(
                offset: Offset(0, -_pinSize / 2 + 4 - lift * _liftHeight),
                child: Icon(
                  Icons.location_on_rounded,
                  size: _pinSize,
                  color: scheme.primary,
                  shadows: [Shadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))],
                ),
              ),
              // First-time hint, above the pin.
              Transform.translate(
                offset: const Offset(0, -_pinSize - 30),
                child: AnimatedOpacity(
                  opacity: _touched ? 0 : 1,
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.inverseSurface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Move the map to place the pin',
                      style: TextStyle(color: scheme.onInverseSurface, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _topBar(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: 'Back',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SearchAnchor(
              searchController: _search,
              viewHintText: 'Search for an address or place',
              builder: (context, controller) => SearchBar(
                controller: controller,
                hintText: 'Search for an address',
                leading: const Icon(Icons.search_rounded),
                elevation: const WidgetStatePropertyAll(3),
                onTap: controller.openView,
                onChanged: (_) => controller.openView(),
              ),
              suggestionsBuilder: _suggestions,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottom(ThemeData theme) {
    final scheme = theme.colorScheme;
    final address = _address;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Required by the map data and tile providers.
              Expanded(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Powered by Geoapify · © OpenMapTiles · © OpenStreetMap contributors',
                      style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 9),
                    ),
                  ),
                ),
              ),
              if (_me != null)
                FloatingActionButton.small(
                  heroTag: 'picker_me',
                  tooltip: 'My location',
                  onPressed: () {
                    _touched = true;
                    _flyTo(_me!, zoom: 17);
                  },
                  child: const Icon(Icons.my_location_rounded),
                ),
            ],
          ),
        ),
        Material(
          color: scheme.surfaceContainerLow,
          elevation: 8,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.place_rounded, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Column(
                            key: ValueKey('${address?.title}$_findingAddress$_moving'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _moving
                                    ? 'Moving…'
                                    : _findingAddress
                                    ? 'Finding address…'
                                    : address?.title ?? 'Unnamed spot',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              if (!_moving && !_findingAddress && address?.subtitle != null)
                                Text(
                                  address!.subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Reminders fire within ${_reminderRadiusMeters.round()} m of the pin',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      onPressed: _moving ? null : _save,
                      child: const Text('Save this place'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
