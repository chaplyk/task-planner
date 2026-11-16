import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'collections.dart';
import 'notifications.dart';
import 'place_types.dart';

/// Public Overpass API servers, tried in order (a busy one returns 429/504).
const _overpassServers = [
  'https://overpass-api.de/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
];

/// Overpass usage policy asks clients to identify themselves.
const _userAgent = 'NagadAI/0.5 (Android reminder app)';

const _dailyCapKey = 'store_lookups';
const _dailyCap = 30;

class NearbyStore {
  const NearbyStore({required this.name, required this.tags, required this.distance});

  final String name;
  final Map<String, dynamic> tags;

  /// Meters from the position used for the search (to the store's point or building center).
  final double distance;

  /// Store type keys ('grocery', ...) this place counts as.
  Set<String> get storeKeys => {
    for (final MapEntry(:key, :value) in storeTypes.entries)
      if (value.matches(tags)) key,
  };
}

/// Search radius for a position fix: tight, but never tighter than the fix is accurate.
double searchRadius(Position p) => p.accuracy.clamp(60, 150).toDouble();

/// Overpass QL: every node/way/relation with a matching tag within [radius] of the point.
/// Uses exact key=value filters (one statement each): they hit Overpass' tag index,
/// unlike regex filters, which can make the server scan far more data and time out.
String _query(Position p, Set<String> storeKeys, double radius) {
  final around = '(around:${radius.round()},${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)})';
  final statements = <String>{
    for (final k in storeKeys)
      for (final MapEntry(:key, :value) in storeTypes[k]!.osmTags.entries)
        for (final v in value) 'nwr["$key"="$v"]$around;',
  };
  return '[out:json][timeout:25];(${statements.join()});out center tags;';
}

/// Stores of the given types around [position], nearest first.
/// Returns null when every server failed, so callers can retry later.
Future<List<NearbyStore>?> nearbyStores(Position position, Set<String> storeKeys, {double? radius}) async {
  final keys = storeKeys.where(storeTypes.containsKey).toSet();
  if (keys.isEmpty) return const [];
  final query = _query(position, keys, radius ?? searchRadius(position));

  for (final server in _overpassServers) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = _userAgent;
    try {
      final request = await client.postUrl(Uri.parse(server));
      request.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      request.write('data=${Uri.encodeQueryComponent(query)}');
      final response = await request.close().timeout(const Duration(seconds: 35));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        final snippet = body.replaceAll(RegExp(r'\s+'), ' ');
        debugPrint(
          'Overpass $server: HTTP ${response.statusCode} '
          '${snippet.substring(0, min(200, snippet.length))}, trying next server',
        );
        continue;
      }
      final elements = (jsonDecode(body)['elements'] as List?) ?? const [];
      final stores = <NearbyStore>[];
      for (final e in elements) {
        final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
        // Fuel station shops are tagged shop=convenience too; they are not grocery stores.
        if (tags['amenity'] == 'fuel') continue;
        final lat = (e['lat'] ?? e['center']?['lat']) as num?;
        final lon = (e['lon'] ?? e['center']?['lon']) as num?;
        if (lat == null || lon == null) continue;
        stores.add(NearbyStore(
          name: (tags['name'] ?? tags['brand'] ?? 'Store') as String,
          tags: tags,
          distance: Geolocator.distanceBetween(position.latitude, position.longitude, lat.toDouble(), lon.toDouble()),
        ));
      }
      debugPrint('Overpass $server: ${stores.length} stores');
      return stores..sort((a, b) => a.distance.compareTo(b.distance));
    } catch (e) {
      debugPrint('Overpass $server: request failed: $e');
    } finally {
      client.close();
    }
  }
  debugPrint('Overpass: all servers failed');
  return null;
}

/// Counts store lookups per day and refuses once the cap is reached (fair use of public servers).
Future<bool> _takeDailyCall() async {
  final prefs = await SharedPreferences.getInstance();
  final today = DateTime.now().toIso8601String().substring(0, 10);
  final raw = prefs.getString(_dailyCapKey) ?? '';
  final count = raw.startsWith('$today:') ? int.parse(raw.split(':')[1]) : 0;
  if (count >= _dailyCap) return false;
  await prefs.setString(_dailyCapKey, '$today:${count + 1}');
  return true;
}

/// Decides when the user has stayed in one area long enough to look up where they are.
/// Position based, so walking around inside a store still counts as staying.
class StayTracker {
  StayTracker({this.threshold = const Duration(minutes: 5), this.areaRadius = 100});

  final Duration threshold;
  final double areaRadius;

  /// How many lookups one stay may try when servers fail.
  static const maxAttempts = 3;

  Position? _anchor;
  DateTime? _since;
  bool _checked = false;
  int _attempts = 0;
  int _stayId = 0;

  /// Changes every time the user moves to a new area, so callers can tell a stay has ended.
  int get stayId => _stayId;

  /// Feeds a new position fix. Returns true once per stay, when it should be checked.
  bool update(Position p, DateTime now) {
    final anchor = _anchor;
    final sameArea = anchor != null &&
        Geolocator.distanceBetween(anchor.latitude, anchor.longitude, p.latitude, p.longitude) <=
            max(areaRadius, p.accuracy);
    if (!sameArea) {
      _stayId++;
      _anchor = p;
      _since = now;
      _checked = false;
      _attempts = 0;
      return false;
    }
    if (_checked || now.difference(_since!) < threshold) return false;
    _checked = true;
    _attempts++;
    return true;
  }

  /// The lookup for this stay failed: allow another try on a later poll.
  void retryLater() {
    if (_attempts < maxAttempts) _checked = false;
  }

  void reset() {
    _anchor = null;
    _since = null;
    _checked = false;
    _attempts = 0;
  }
}

/// Background check for "at the grocery store" style reminders. Cheap when idle:
/// no position fix unless such a reminder is waiting, no lookup unless the
/// user has stayed in one area for [StayTracker.threshold].
class StoreReminderWatcher {
  final _stay = StayTracker();

  /// Kinds of stores found at the current stay (key -> store name), kept so
  /// "when I leave" reminders can fire once the user moves on.
  var _here = <String, String>{};
  int _hereStay = -1;

  Future<void> _notify(QueryDocumentSnapshot<Map<String, dynamic>> doc, String storeName) async {
    await showNotification(int.parse(doc.id), '${doc.data()['summary'] ?? 'Reminder'} · $storeName');
    await doc.reference.update({'notified': true});
  }

  Future<void> tick(DateTime now) async {
    final waiting = await remindersCollection()
        .where('status', isEqualTo: 0)
        .where('triggerType', isEqualTo: 'location')
        .where('notified', isEqualTo: false)
        .get();
    final storeDocs = waiting.docs.where((d) => isStoreType(d.data()['location'] as String?)).toList();
    if (storeDocs.isEmpty) {
      _stay.reset();
      _here = {};
      return;
    }

    final Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (e) {
      debugPrint('Store check: no position: $e');
      return;
    }

    final due = _stay.update(position, now);
    if (_here.isNotEmpty && _stay.stayId != _hereStay) {
      // The user has moved away from the stores found earlier: fire the "when I leave" reminders.
      final left = _here;
      _here = {};
      for (final doc in storeDocs) {
        final name = left[doc.data()['location']];
        if (doc.data()['locationEvent'] == 'exit' && name != null) await _notify(doc, name);
      }
    }
    if (!due) return;
    if (!await _takeDailyCall()) {
      debugPrint('Store check: daily lookup cap reached');
      return;
    }

    final wanted = {for (final d in storeDocs) d.data()['location'] as String};
    final stores = await nearbyStores(position, wanted);
    if (stores == null) {
      _stay.retryLater();
      return;
    }
    debugPrint('Store check: ${stores.map((s) => '${s.name} ${s.distance.round()}m ${s.storeKeys}').join(', ')}');

    _here = {
      for (final key in wanted)
        if (stores.where((s) => s.storeKeys.contains(key)).firstOrNull case final store?) key: store.name,
    };
    _hereStay = _stay.stayId;

    for (final doc in storeDocs) {
      final name = _here[doc.data()['location']];
      // "When I leave" reminders wait until this stay ends (see above).
      if (name == null || doc.data()['locationEvent'] == 'exit') continue;
      await _notify(doc, name);
    }
  }
}
