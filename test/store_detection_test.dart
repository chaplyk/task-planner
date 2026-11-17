import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nagadai/store_detection.dart';

Position _fix(double lat, double lon, {double accuracy = 10}) => Position(
  latitude: lat,
  longitude: lon,
  timestamp: DateTime(2026),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

// At latitude 50°: 0.0001° latitude ≈ 11 m, 0.0001° longitude ≈ 7 m.
const _store = StorePoi(placeId: 'p1', name: 'Corner Shop', lat: 50.0, lon: 30.0, storeKeys: {'grocery'});

// A hypermarket about 200 m × 140 m, its center at (50.0, 30.0).
const _hyper = StorePoi(
  placeId: 'p2',
  name: 'Hyper',
  lat: 50.0,
  lon: 30.0,
  bounds: Bounds(49.9991, 29.9986, 50.0009, 30.0014),
  storeKeys: {'grocery'},
);

void main() {
  group('fixMatchesStore', () {
    test('accurate fix within 25 m matches', () {
      expect(fixMatchesStore(_fix(50.00015, 30.0), _store), isTrue); // ~17 m
    });

    test('accurate fix 40 m away does not match', () {
      expect(fixMatchesStore(_fix(50.00036, 30.0), _store), isFalse);
    });

    test('fix worse than 35 m is rejected even at the store', () {
      expect(fixMatchesStore(_fix(50.0, 30.0, accuracy: 40), _store), isFalse);
      expect(fixMatchesStore(_fix(50.0, 30.0, accuracy: 35), _store), isTrue);
    });

    test('anywhere inside a large building matches', () {
      // ~90 m from the center, but inside the outline.
      expect(fixMatchesStore(_fix(50.0008, 30.0), _hyper), isTrue);
    });

    test('the building outline is padded by 25 m, not more', () {
      expect(fixMatchesStore(_fix(50.0011, 30.0), _hyper), isTrue); // ~22 m outside
      expect(fixMatchesStore(_fix(50.0013, 30.0), _hyper), isFalse); // ~44 m outside
    });
  });

  group('visitConfirmed', () {
    final at = _fix(50.0, 30.0);
    final away = _fix(50.001, 30.0);
    final blurry = _fix(50.0, 30.0, accuracy: 60);

    test('needs two matching fixes', () {
      expect(visitConfirmed([at, away, away], _store), isFalse);
      expect(visitConfirmed([at, away, at], _store), isTrue);
      expect(visitConfirmed([at, at], _store), isTrue);
    });

    test('inaccurate fixes do not count', () {
      expect(visitConfirmed([at, blurry, blurry], _store), isFalse);
    });
  });

  group('inVehicle', () {
    final now = DateTime(2026, 11, 17, 12);
    int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;

    test('recent "in" report means driving', () {
      expect(inVehicle('in', ago(const Duration(minutes: 10)), now), isTrue);
    });

    test('"out", stale or missing reports do not block', () {
      expect(inVehicle('out', ago(const Duration(minutes: 1)), now), isFalse);
      expect(inVehicle('in', ago(const Duration(hours: 3)), now), isFalse);
      expect(inVehicle(null, null, now), isFalse);
    });
  });

  group('Geoapify', () {
    test('places request asks only for the wanted kinds, nearest first', () {
      final uri = buildPlacesUri(50.0, 30.0, {'pharmacy'}, apiKey: 'k');
      expect(uri.path, '/v2/places');
      final q = uri.queryParameters;
      expect(q['categories']!.split(','), containsAll(['healthcare.pharmacy', 'commercial.chemist']));
      expect(q['categories'], isNot(contains('supermarket')));
      expect(q['filter'], 'circle:30.000000,50.000000,1500');
      expect(q['bias'], 'proximity:30.000000,50.000000');
      expect(q['limit'], '50');
      expect(q['apiKey'], 'k');
    });

    Map<String, dynamic> feature(String id, List<String> categories, {String? name}) => {
      'type': 'Feature',
      'properties': {'place_id': id, 'lat': 50.0, 'lon': 30.0, 'name': ?name, 'categories': categories},
      'geometry': {'type': 'Point', 'coordinates': [30.0, 50.0]},
    };

    test('parses places, skips fuel stations and unwanted kinds', () {
      final pois = parseFeatures([
        feature('a', ['commercial', 'commercial.supermarket'], name: 'Fresh'),
        feature('b', ['commercial.convenience']),
        feature('c', ['commercial.convenience', 'service.vehicle.fuel']),
        feature('d', ['healthcare.pharmacy']),
      ], {'grocery'});

      expect(pois.map((p) => p.placeId), ['a', 'b']);
      expect(pois[0].name, 'Fresh');
      expect(pois[1].name, 'grocery store'); // unnamed: the kind's label
      expect(pois[0].storeKeys, {'grocery'});
    });

    test('geofence ids are short and stable', () {
      final poi = StorePoi(placeId: 'x' * 200, name: 's', lat: 0, lon: 0, storeKeys: {'grocery'});
      expect(poi.geofenceId, startsWith('store:'));
      expect(poi.geofenceId.length, lessThanOrEqualTo(100));
      expect(poi.geofenceId, StorePoi(placeId: 'x' * 200, name: 'other', lat: 1, lon: 1, storeKeys: {}).geofenceId);
      expect(_store.id, isNot(_hyper.id));
    });

    test('building bounds come from a polygon, not a point', () {
      final b = Bounds.ofGeometry({
        'type': 'Polygon',
        'coordinates': [
          [[30.0, 50.0], [30.002, 50.0], [30.002, 50.001], [30.0, 50.001], [30.0, 50.0]],
        ],
      })!;
      expect([b.minLat, b.minLon, b.maxLat, b.maxLon], [50.0, 30.0, 50.001, 30.002]);
      expect(Bounds.ofGeometry({'type': 'Point', 'coordinates': [30.0, 50.0]}), isNull);
    });

    test('keeps the 50 nearest stores', () {
      final pois = [
        for (var i = 100; i > 0; i--)
          StorePoi(placeId: 'p$i', name: 's$i', lat: 50.0 + i * 0.0001, lon: 30.0, storeKeys: const {'grocery'}),
      ];
      final kept = nearestPois(pois, 50.0, 30.0);
      expect(kept, hasLength(50));
      expect(kept.first.placeId, 'p1');
      expect(kept.last.placeId, 'p50');
    });

    test('stores survive a JSON round trip', () {
      final back = StorePoi.fromJson(_hyper.toJson());
      expect(back.placeId, 'p2');
      expect(back.id, _hyper.id);
      expect(back.storeKeys, {'grocery'});
      expect(back.bounds!.maxLon, 30.0014);
    });
  });

  group('lookupNeeded', () {
    const last = StoreLookup(50.0, 30.0, {'grocery', 'pharmacy'});

    test('first time', () {
      expect(lookupNeeded(null, 50.0, 30.0, {'grocery'}), isTrue);
    });

    test('not after moving less than 150 m', () {
      expect(lookupNeeded(last, 50.0009, 30.0, {'grocery'}), isFalse); // ~100 m
    });

    test('after moving more than 150 m', () {
      expect(lookupNeeded(last, 50.0018, 30.0, {'grocery'}), isTrue); // ~200 m
    });

    test('when a kind is added, not when one is gone', () {
      expect(lookupNeeded(last, 50.0, 30.0, {'grocery', 'hardware'}), isTrue);
      expect(lookupNeeded(last, 50.0, 30.0, {'pharmacy'}), isFalse);
    });

    test('survives a JSON round trip', () {
      final back = StoreLookup.fromJson(last.toJson());
      expect([back.lat, back.lon], [50.0, 30.0]);
      expect(back.kinds, {'grocery', 'pharmacy'});
    });
  });
}
