// "At the grocery store" style reminders, without the user saving a place.
//
// 1. Every ~10 minutes the background service asks Geoapify Places for the stores of
//    the wanted kinds within [poiSearchRadius] and keeps the nearest
//    [maxStoreGeofences] in memory (and in SharedPreferences for the geofence isolate).
//    No request is sent unless the user moved [lookupMoveThreshold] since the last one.
// 2. Each store gets an Android geofence: [storeGeofenceRadius] wide, dwell after
//    [storeDwellDelay], expiring after one refresh period (a developer option,
//    [storeRefreshPeriod]) unless re-created by the next refresh.
// 3. On DWELL, a few accurate GPS fixes must place the user at the store's
//    coordinates (or inside its building outline) and the user must not be driving.
//    Only then are the reminders shown. EXIT ends the visit. Categories only support
//    arriving ("when I leave" can't be offered for them: see [storeCondition]).
//
// Every step is written to the store log (lib/store_log.dart), shown on the
// Debug log screen.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'collections.dart';
import 'geoapify.dart';
import 'geofence_callback.dart';
import 'notifications.dart';
import 'place_types.dart';
import 'store_log.dart';

const poiSearchRadius = 1500.0;
const maxStoreGeofences = 50;
const storeGeofenceRadius = 150.0;

/// How often the stores and their geofences are refreshed: a developer option.
const defaultStoreRefreshMinutes = 10;
/// Re-creating a geofence restarts its [storeDwellDelay] timer, so a refresh period
/// must leave the dwell time to pass in between.
const minStoreRefreshMinutes = 3;
const maxStoreRefreshMinutes = 15;
const _refreshMinutesKey = 'store_refresh_minutes';
const storeDwellDelay = Duration(seconds: 120);

/// The stores are looked up again only once the user is this far from the last lookup (meters).
const lookupMoveThreshold = 150.0;

/// The refresh period chosen in developer options (read fresh: the service isolate
/// sees changes made in the app).
Future<Duration> storeRefreshPeriod() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final minutes = prefs.getInt(_refreshMinutesKey) ?? defaultStoreRefreshMinutes;
  return Duration(minutes: minutes.clamp(minStoreRefreshMinutes, maxStoreRefreshMinutes));
}

Future<void> setStoreRefreshMinutes(int minutes) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_refreshMinutesKey, minutes.clamp(minStoreRefreshMinutes, maxStoreRefreshMinutes));
}

/// A fix is used only if Android says it is at least this accurate (meters).
const requiredFixAccuracy = 35.0;

/// A fix must be this close to the store's point, or its building, to count (meters).
const atStoreDistance = 25.0;

/// Fixes taken on DWELL, and how many of them must place the user at the store.
const fixesPerCheck = 3;
const requiredMatchingFixes = 2;

/// An "in vehicle" report older than this is no longer trusted.
const _vehicleStateMaxAge = Duration(hours: 2);

/// Geofence ids of stores start with this; other geofences are saved places.
const storeGeofencePrefix = 'store:';


/// Fuel station shops count as convenience stores too; they are not grocery stores.
const _fuelCategory = 'service.vehicle.fuel';

/// Caps lookups per day, so a bug can't burn the Geoapify credits.
const _dailyCapKey = 'store_lookups';
const _dailyCap = 100;

const _poisKey = 'store_pois';
const _lookupKey = 'store_lookup';
const _visitsKey = 'store_visits';

// Written by ActivityTransitionReceiver.kt (as "flutter.vehicle_state" etc.).
const _vehicleStateKey = 'vehicle_state';
const _vehicleStateAtKey = 'vehicle_state_at';

// ---------------------------------------------------------------- model

/// A building's extent.
class Bounds {
  const Bounds(this.minLat, this.minLon, this.maxLat, this.maxLon);

  final double minLat, minLon, maxLat, maxLon;

  /// Whether the point lies inside, with [padding] meters added on every side.
  bool contains(double lat, double lon, {double padding = 0}) {
    final dLat = padding / 111320;
    final dLon = padding / (111320 * cos(lat * pi / 180));
    return lat >= minLat - dLat && lat <= maxLat + dLat && lon >= minLon - dLon && lon <= maxLon + dLon;
  }

  /// The extent of a GeoJSON Polygon / MultiPolygon, or null for any other geometry.
  static Bounds? ofGeometry(Map<String, dynamic>? geometry) {
    final type = geometry?['type'];
    if (type != 'Polygon' && type != 'MultiPolygon') return null;
    final points = <List<dynamic>>[];
    void collect(dynamic c) {
      if (c is List && c.length >= 2 && c[0] is num) {
        points.add(c);
      } else if (c is List) {
        c.forEach(collect);
      }
    }

    collect(geometry!['coordinates']);
    if (points.isEmpty) return null;
    // GeoJSON is [lon, lat].
    final lons = points.map((p) => (p[0] as num).toDouble());
    final lats = points.map((p) => (p[1] as num).toDouble());
    return Bounds(lats.reduce(min), lons.reduce(min), lats.reduce(max), lons.reduce(max));
  }

  /// Rough size, for the log.
  String get size {
    final h = Geolocator.distanceBetween(minLat, minLon, maxLat, minLon);
    final w = Geolocator.distanceBetween(minLat, minLon, minLat, maxLon);
    return '${w.round()}×${h.round()} m';
  }

  List<double> toJson() => [minLat, minLon, maxLat, maxLon];

  static Bounds fromJson(List<dynamic> j) =>
      Bounds((j[0] as num).toDouble(), (j[1] as num).toDouble(), (j[2] as num).toDouble(), (j[3] as num).toDouble());
}

/// A store found by Geoapify.
class StorePoi {
  const StorePoi({
    required this.placeId,
    required this.name,
    required this.lat,
    required this.lon,
    required this.storeKeys,
    this.bounds,
  });

  /// Geoapify's place id, for Place Details.
  final String placeId;
  final String name;
  final double lat, lon;

  /// The building's extent, once looked up (see [_withBounds]).
  final Bounds? bounds;

  /// Store type keys ('grocery', ...) this place counts as.
  final Set<String> storeKeys;

  /// Short stable id: Geoapify place ids are long, Android geofence ids are limited to 100 chars.
  String get id => _fnv1a(placeId);

  String get geofenceId => '$storeGeofencePrefix$id';

  double distanceTo(double lat, double lon) => Geolocator.distanceBetween(lat, lon, this.lat, this.lon);

  StorePoi withBounds(Bounds? b) =>
      StorePoi(placeId: placeId, name: name, lat: lat, lon: lon, storeKeys: storeKeys, bounds: b);

  Map<String, dynamic> toJson() => {
    'pid': placeId,
    'name': name,
    'lat': lat,
    'lon': lon,
    if (bounds != null) 'bb': bounds!.toJson(),
    'keys': storeKeys.toList(),
  };

  static StorePoi fromJson(Map<String, dynamic> j) => StorePoi(
    placeId: j['pid'] as String,
    name: j['name'] as String,
    lat: (j['lat'] as num).toDouble(),
    lon: (j['lon'] as num).toDouble(),
    bounds: j['bb'] == null ? null : Bounds.fromJson(j['bb'] as List),
    storeKeys: {...(j['keys'] as List).cast<String>()},
  );
}

/// 64-bit FNV-1a as 16 hex digits.
String _fnv1a(String s) {
  var h = 0xcbf29ce484222325;
  for (final c in utf8.encode(s)) {
    h ^= c;
    h *= 0x100000001b3;
  }
  return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

// ---------------------------------------------------------------- Geoapify

/// Places API request: the wanted store kinds within [radius], nearest first.
Uri buildPlacesUri(double lat, double lon, Set<String> storeKeys, {double radius = poiSearchRadius, String apiKey = geoapifyApiKey}) {
  final categories = {for (final k in storeKeys) ...storeTypes[k]!.categories};
  final lonLat = '${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)}';
  return Uri.parse('$geoapifyApiBase/places').replace(queryParameters: {
    'categories': categories.join(','),
    'filter': 'circle:$lonLat,${radius.round()}',
    'bias': 'proximity:$lonLat',
    'limit': '$maxStoreGeofences',
    'apiKey': apiKey,
  });
}

/// Turns Places API `features` into stores of the [wanted] kinds.
List<StorePoi> parseFeatures(List<dynamic> features, Set<String> wanted) {
  final stores = <StorePoi>[];
  for (final f in features) {
    final p = (f['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
    final categories = ((p['categories'] as List?) ?? const []).cast<String>();
    if (categories.any((c) => c == _fuelCategory || c.startsWith('$_fuelCategory.'))) continue;
    final placeId = p['place_id'] as String?;
    final lat = p['lat'] as num?;
    final lon = p['lon'] as num?;
    if (placeId == null || lat == null || lon == null) continue;
    final keys = {
      for (final MapEntry(:key, :value) in storeTypes.entries)
        if (wanted.contains(key) && value.matches(categories)) key,
    };
    if (keys.isEmpty) continue;
    stores.add(StorePoi(
      placeId: placeId,
      name: (p['name'] ?? p['brand'] ?? storeTypes[keys.first]!.label) as String,
      lat: lat.toDouble(),
      lon: lon.toDouble(),
      storeKeys: keys,
    ));
  }
  return stores;
}

/// The [limit] stores nearest to the point, nearest first.
List<StorePoi> nearestPois(List<StorePoi> pois, double lat, double lon, {int limit = maxStoreGeofences}) {
  final sorted = [...pois]..sort((a, b) => a.distanceTo(lat, lon).compareTo(b.distanceTo(lat, lon)));
  return sorted.take(limit).toList();
}

/// GETs a Geoapify URL and returns the decoded JSON, or null (logged) on any failure.
Future<Map<String, dynamic>?> _getJson(Uri uri, String what) async {
  if (geoapifyApiKey.isEmpty) {
    await storeLog('$what: no GEOAPIFY_API_KEY in dart_defines.json');
    return null;
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 20));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      final snippet = body.replaceAll(RegExp(r'\s+'), ' ');
      await storeLog('$what: HTTP ${response.statusCode} ${snippet.substring(0, min(150, snippet.length))}');
      return null;
    }
    return (jsonDecode(body) as Map).cast<String, dynamic>();
  } catch (e) {
    await storeLog('$what failed: $e');
    return null;
  } finally {
    client.close();
  }
}

/// Stores of the given kinds within [poiSearchRadius] of the point, nearest first.
/// Returns null when the lookup failed, so callers can keep what they had.
Future<List<StorePoi>?> fetchNearbyStores(double lat, double lon, Set<String> storeKeys) async {
  final keys = storeKeys.where(storeTypes.containsKey).toSet();
  if (keys.isEmpty) return const [];
  final json = await _getJson(buildPlacesUri(lat, lon, keys), 'Places lookup');
  if (json == null) return null;
  final features = (json['features'] as List?) ?? const [];
  final stores = nearestPois(parseFeatures(features, keys), lat, lon);
  await storeLog('Places lookup ${keys.join('+')}: ${features.length} places, ${stores.length} stores kept');
  return stores;
}

/// The store's building outline from Place Details (1 credit), or null if it is
/// mapped as a point or the lookup failed.
Future<Bounds?> _fetchBounds(StorePoi poi) async {
  final uri = Uri.parse('$geoapifyApiBase/place-details').replace(queryParameters: {
    'id': poi.placeId,
    'features': 'details',
    'apiKey': geoapifyApiKey,
  });
  final json = await _getJson(uri, 'Place details ${poi.name}');
  for (final f in (json?['features'] as List?) ?? const []) {
    final b = Bounds.ofGeometry((f['geometry'] as Map?)?.cast<String, dynamic>());
    if (b != null) return b;
  }
  return null;
}

/// Counts lookups per day and refuses once the cap is reached.
Future<bool> _takeDailyCall() async {
  final prefs = await SharedPreferences.getInstance();
  final today = DateTime.now().toIso8601String().substring(0, 10);
  final raw = prefs.getString(_dailyCapKey) ?? '';
  final count = raw.startsWith('$today:') ? int.parse(raw.split(':')[1]) : 0;
  if (count >= _dailyCap) return false;
  await prefs.setString(_dailyCapKey, '$today:${count + 1}');
  return true;
}

// ---------------------------------------------------------------- verification

/// Whether a fix is accurate enough to judge by.
bool fixUsable(Position fix) => fix.accuracy > 0 && fix.accuracy <= requiredFixAccuracy;

/// Whether a usable fix places the user at the store: near its point or inside its building.
bool fixMatchesStore(Position fix, StorePoi poi) {
  if (!fixUsable(fix)) return false;
  if (poi.distanceTo(fix.latitude, fix.longitude) <= atStoreDistance) return true;
  return poi.bounds?.contains(fix.latitude, fix.longitude, padding: atStoreDistance) ?? false;
}

/// Whether enough fixes place the user at the store.
bool visitConfirmed(Iterable<Position> fixes, StorePoi poi) =>
    fixes.where((f) => fixMatchesStore(f, poi)).length >= requiredMatchingFixes;

/// Whether Activity Recognition last said the user is in a vehicle. Unknown
/// (no permission, no report yet, or a stale one) counts as not driving.
bool inVehicle(String? state, int? atMillis, DateTime now) =>
    state == 'in' &&
    atMillis != null &&
    now.difference(DateTime.fromMillisecondsSinceEpoch(atMillis)) <= _vehicleStateMaxAge;

/// Takes up to [fixesPerCheck] fresh fixes, stopping once [requiredMatchingFixes] match.
Future<bool> _confirmAtStore(StorePoi poi) async {
  final fixes = <Position>[];
  for (var i = 0; i < fixesPerCheck; i++) {
    if (i > 0) await Future<void>.delayed(const Duration(seconds: 5));
    try {
      final fix = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 20),
        ),
      );
      fixes.add(fix);
      final inside = poi.bounds?.contains(fix.latitude, fix.longitude, padding: atStoreDistance) ?? false;
      await storeLog(
        '  GPS ${i + 1}/$fixesPerCheck ${poi.name}: ±${fix.accuracy.round()} m'
        '${fixUsable(fix) ? '' : ' (too coarse)'}, '
        '${poi.distanceTo(fix.latitude, fix.longitude).round()} m from point'
        '${inside ? ', inside building' : ''} → ${fixMatchesStore(fix, poi) ? 'MATCH' : 'no match'}',
      );
    } catch (e) {
      await storeLog('  GPS ${i + 1}/$fixesPerCheck ${poi.name}: no fix ($e)');
    }
    if (visitConfirmed(fixes, poi)) return true;
    // Not enough fixes left to reach the required number of matches.
    final matches = fixes.where((f) => fixMatchesStore(f, poi)).length;
    if (matches + (fixesPerCheck - i - 1) < requiredMatchingFixes) return false;
  }
  return false;
}

// ---------------------------------------------------------------- reminders

/// Open place reminders that have not fired yet: what the background service watches for.
Query<Map<String, dynamic>> waitingPlaceReminders() => remindersCollection()
    .where('status', isEqualTo: 0)
    .where('triggerType', isEqualTo: 'location')
    .where('notified', isEqualTo: false);

/// Whether a waiting reminder is one store detection serves: a category, on arrival.
/// (Older "when I leave" category reminders are ignored.)
bool isStoreArrival(Map<String, dynamic> data) =>
    isStoreType(data['location'] as String?) && data['locationEvent'] != 'exit';

/// Shows the waiting arrival reminders for [poi]'s categories.
Future<void> _notifyStoreReminders(StorePoi poi) async {
  final waiting = await waitingPlaceReminders().get();
  var shown = 0;
  for (final doc in waiting.docs) {
    final data = doc.data();
    if (!isStoreArrival(data) || !poi.storeKeys.contains(data['location'])) continue;
    final summary = data['summary'] ?? 'Reminder';
    await showNotification(int.parse(doc.id), '$summary · ${poi.name}');
    sendWrite(doc.reference.update({'notified': true}));
    await storeLog('  NOTIFIED "$summary" (${poi.name})');
    shown++;
  }
  if (shown == 0) await storeLog('  no waiting reminders for ${poi.storeKeys.join('/')}');
}

// ---------------------------------------------------------------- persisted state

Future<SharedPreferences> _freshPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  // Other isolates (the service, the geofence callback, Kotlin) write these too.
  await prefs.reload();
  return prefs;
}

Map<String, StorePoi> _loadPois(SharedPreferences prefs) {
  final raw = prefs.getString(_poisKey);
  if (raw == null) return {};
  try {
    final pois = (jsonDecode(raw) as List).map((j) => StorePoi.fromJson((j as Map).cast<String, dynamic>()));
    return {for (final p in pois) p.id: p};
  } catch (e) {
    debugPrint('Stored stores unreadable: $e');
    return {};
  }
}

/// Per-store visit state: {id: {"since": ms, "confirmed": bool, "bb": [..] | false}}.
Map<String, dynamic> _loadVisits(SharedPreferences prefs) {
  try {
    return (jsonDecode(prefs.getString(_visitsKey) ?? '{}') as Map).cast<String, dynamic>();
  } catch (_) {
    return {};
  }
}

Future<void> _saveVisits(SharedPreferences prefs, Map<String, dynamic> visits) =>
    prefs.setString(_visitsKey, jsonEncode(visits));

/// Forgets the stores and visits kept on this device (on sign-out).
Future<void> clearStoreState() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_poisKey);
  await prefs.remove(_visitsKey);
  await prefs.remove(_lookupKey);
}

/// [poi] with its building outline: cached in the visit, looked up once per visit.
Future<StorePoi> _withBounds(StorePoi poi, Map<String, dynamic> visit) async {
  final cached = visit['bb'];
  if (cached is List) return poi.withBounds(Bounds.fromJson(cached));
  if (cached == false) return poi; // looked up already: a point, or failed
  final b = await _fetchBounds(poi);
  visit['bb'] = b?.toJson() ?? false;
  await storeLog('  ${poi.name}: ${b == null ? 'no building outline, using the point only' : 'building ${b.size}'}');
  return poi.withBounds(b);
}

// ---------------------------------------------------------------- geofence events

/// Handles geofence events of stores (ids starting with [storeGeofencePrefix]).
/// Runs in the geofence plugin's background isolate; Firebase and notifications
/// must already be initialized.
Future<void> storeGeofenceTriggered(GeofenceEvent event, List<String> geofenceIds) async {
  final prefs = await _freshPrefs();
  final pois = _loadPois(prefs);
  final visits = _loadVisits(prefs);

  for (final geofenceId in geofenceIds) {
    final id = geofenceId.substring(storeGeofencePrefix.length);
    final poi = pois[id];
    if (poi == null) {
      await storeLog('${event.name.toUpperCase()} $geofenceId: store no longer in the list, ignored');
      continue;
    }
    final visit = (visits[id] as Map?)?.cast<String, dynamic>() ?? {};
    switch (event) {
      case GeofenceEvent.enter:
        await storeLog('ENTER ${poi.name} (${poi.storeKeys.join('/')})');
        visits[id] = {'since': DateTime.now().millisecondsSinceEpoch, 'confirmed': false};
      case GeofenceEvent.dwell:
        if (visit['confirmed'] == true) {
          await storeLog('DWELL ${poi.name}: already confirmed this visit');
          continue;
        }
        await storeLog('DWELL ${poi.name}: checking');
        final state = prefs.getString(_vehicleStateKey);
        final at = prefs.getInt(_vehicleStateAtKey);
        final stateText = state == null
            ? 'no activity data'
            : '"$state" ${DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at ?? 0)).inMinutes} min ago';
        if (inVehicle(state, at, DateTime.now())) {
          await storeLog('  in a vehicle ($stateText) → skipped');
          continue;
        }
        await storeLog('  not in a vehicle ($stateText)');
        final checked = await _withBounds(poi, visit);
        visits[id] = visit;
        if (!await _confirmAtStore(checked)) {
          await storeLog('  NOT confirmed: fewer than $requiredMatchingFixes GPS fixes at ${poi.name}');
          continue;
        }
        await storeLog('  CONFIRMED at ${poi.name}');
        visits[id] = {...visit, 'confirmed': true};
        await _saveVisits(prefs, visits); // before notifying, so a retry doesn't repeat it
        await _notifyStoreReminders(poi);
      case GeofenceEvent.exit:
        visits.remove(id);
        await storeLog('EXIT ${poi.name}: visit ended${visit['confirmed'] == true ? '' : ' (never confirmed)'}');
    }
  }
  await _saveVisits(prefs, visits);
}

// ---------------------------------------------------------------- refresh (service)

/// Where and for which kinds the stores were last looked up.
class StoreLookup {
  const StoreLookup(this.lat, this.lon, this.kinds);

  final double lat, lon;
  final Set<String> kinds;

  double distanceTo(double lat, double lon) => Geolocator.distanceBetween(this.lat, this.lon, lat, lon);

  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon, 'kinds': kinds.toList()};

  static StoreLookup fromJson(Map<String, dynamic> j) => StoreLookup(
    (j['lat'] as num).toDouble(),
    (j['lon'] as num).toDouble(),
    {...(j['kinds'] as List).cast<String>()},
  );
}

/// Whether the stores must be looked up again: never looked up, a kind is now wanted
/// that the last lookup didn't ask for, or the user moved [lookupMoveThreshold] away.
bool lookupNeeded(StoreLookup? last, double lat, double lon, Set<String> wanted) =>
    last == null || !last.kinds.containsAll(wanted) || last.distanceTo(lat, lon) > lookupMoveThreshold;

/// Keeps geofences around the stores near the user. Driven by the background service
/// every [storeRefreshPeriod] while a store reminder is waiting.
class StoreGeofencer {
  /// The stores currently watched, kept to compare positions against.
  List<StorePoi> _pois = const [];
  StoreLookup? _last;
  bool _restored = false;

  /// After a service restart: the last lookup's stores, so it isn't repeated needlessly.
  Future<void> _restore() async {
    if (_restored) return;
    _restored = true;
    final prefs = await _freshPrefs();
    try {
      final raw = prefs.getString(_lookupKey);
      if (raw == null) return;
      _last = StoreLookup.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
      _pois = _loadPois(prefs).values.toList();
    } catch (e) {
      _last = null;
      _pois = const [];
    }
  }

  List<StorePoi> get pois => _pois;

  /// [waiting] is the open, not yet notified place reminders (see [waitingPlaceReminders]).
  Future<void> refresh(List<QueryDocumentSnapshot<Map<String, dynamic>>> waiting) async {
    final wanted = {
      for (final d in waiting)
        if (isStoreArrival(d.data())) d.data()['location'] as String,
    };
    if (wanted.isEmpty) {
      await clear();
      return;
    }
    await storeLog('Refresh: looking for ${wanted.join(', ')}');

    final Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (e) {
      await storeLog('Refresh: no position ($e)');
      return;
    }
    await storeLog(
      'Refresh: at ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)} '
      '±${position.accuracy.round()} m',
    );

    await _restore();
    final last = _last;
    if (!lookupNeeded(last, position.latitude, position.longitude, wanted)) {
      await storeLog(
        'Refresh: moved ${last!.distanceTo(position.latitude, position.longitude).round()} m since last lookup '
        '(new lookup after ${lookupMoveThreshold.round()} m), reusing ${_pois.length} stores',
      );
      await _syncGeofences();
      return;
    }

    List<StorePoi>? found;
    if (await _takeDailyCall()) {
      found = await fetchNearbyStores(position.latitude, position.longitude, wanted);
    } else {
      await storeLog('Refresh: daily lookup cap ($_dailyCap) reached');
    }
    if (found != null) {
      _pois = found;
      _last = StoreLookup(position.latitude, position.longitude, wanted);
      final prefs = await _freshPrefs();
      await prefs.setString(_poisKey, jsonEncode([for (final p in found) p.toJson()]));
      await prefs.setString(_lookupKey, jsonEncode(_last!.toJson()));
      if (found.isNotEmpty) {
        await storeLog(
          'Refresh: nearest ${found.take(3).map((p) => '${p.name} ${p.distanceTo(position.latitude, position.longitude).round()} m').join(', ')}',
        );
      }
    } else {
      // Keep the last list: re-creating its geofences still renews their expiration.
      await storeLog('Refresh: keeping ${_pois.length} stores from the last lookup');
    }
    await _syncGeofences();
  }

  /// Registers a geofence per store (re-creating one renews its expiration, set to one
  /// refresh period) and removes the geofences of stores no longer in the list.
  Future<void> _syncGeofences() async {
    final manager = NativeGeofenceManager.instance;
    final expiration = await storeRefreshPeriod();
    final keep = {for (final p in _pois) p.geofenceId};
    var removed = 0;
    try {
      for (final id in await manager.getRegisteredGeofenceIds()) {
        if (id.startsWith(storeGeofencePrefix) && !keep.contains(id)) {
          await manager.removeGeofenceById(id);
          removed++;
        }
      }
    } catch (e) {
      await storeLog('Geofences: listing failed ($e)');
    }
    var ok = 0;
    String? error;
    for (final poi in _pois) {
      try {
        await manager.createGeofence(_geofenceFor(poi, expiration), geofenceTriggered);
        ok++;
      } catch (e) {
        error ??= '$e';
      }
    }
    await storeLog(
      'Geofences: $ok/${_pois.length} registered (${storeGeofenceRadius.round()} m, '
      'expire ${expiration.inMinutes} min, dwell ${storeDwellDelay.inSeconds} s), '
      '$removed removed${error == null ? '' : ', error: $error'}',
    );
  }

  /// Removes every store geofence and forgets the stores.
  Future<void> clear() async {
    var removed = 0;
    try {
      final manager = NativeGeofenceManager.instance;
      for (final id in await manager.getRegisteredGeofenceIds()) {
        if (id.startsWith(storeGeofencePrefix)) {
          await manager.removeGeofenceById(id);
          removed++;
        }
      }
    } catch (e) {
      await storeLog('Geofences: clearing failed ($e)');
    }
    if (removed > 0 || _pois.isNotEmpty) {
      await storeLog('No store reminders waiting: $removed store geofences removed');
    }
    _pois = const [];
    _last = null;
    await clearStoreState();
  }
}

Geofence _geofenceFor(StorePoi poi, Duration expiration) => Geofence(
  id: poi.geofenceId,
  location: Location(latitude: poi.lat, longitude: poi.lon),
  radiusMeters: storeGeofenceRadius,
  triggers: {GeofenceEvent.enter, GeofenceEvent.dwell, GeofenceEvent.exit},
  iosSettings: const IosGeofenceSettings(),
  androidSettings: AndroidGeofenceSettings(
    // Re-creating a geofence the user is already inside must still lead to a DWELL.
    initialTriggers: const {GeofenceEvent.dwell},
    expiration: expiration,
    loiteringDelay: storeDwellDelay,
  ),
);
