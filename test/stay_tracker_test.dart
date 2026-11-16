import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nagadai/store_detection.dart';

Position _at(double lat, double lng, {double accuracy = 30}) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2026),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

// ~0.0004° latitude ≈ 45 m; 0.002° ≈ 220 m.
void main() {
  final t0 = DateTime(2026, 11, 16, 12);
  Duration m(int minutes) => Duration(minutes: minutes);

  test('triggers once after staying 5 minutes while moving inside the area', () {
    final stay = StayTracker();
    expect(stay.update(_at(50.0, 30.0), t0), isFalse);
    expect(stay.update(_at(50.0004, 30.0), t0.add(m(2))), isFalse); // walking the aisles
    expect(stay.update(_at(49.9996, 30.0003), t0.add(m(5))), isTrue);
    expect(stay.update(_at(50.0, 30.0), t0.add(m(7))), isFalse); // already checked
  });

  test('passing by never triggers', () {
    final stay = StayTracker();
    for (var i = 0; i < 10; i++) {
      expect(stay.update(_at(50.0 + i * 0.002, 30.0), t0.add(m(i))), isFalse);
    }
  });

  test('leaving and coming back starts a new stay', () {
    final stay = StayTracker();
    stay.update(_at(50.0, 30.0), t0);
    expect(stay.update(_at(50.0, 30.0), t0.add(m(5))), isTrue);
    stay.update(_at(50.01, 30.0), t0.add(m(10))); // drove away
    stay.update(_at(50.0, 30.0), t0.add(m(20))); // back
    expect(stay.update(_at(50.0, 30.0), t0.add(m(26))), isTrue);
  });

  test('a failed lookup is retried, at most 3 times per stay', () {
    final stay = StayTracker();
    stay.update(_at(50.0, 30.0), t0);
    var tries = 0;
    for (var i = 5; i < 15; i++) {
      if (stay.update(_at(50.0, 30.0), t0.add(m(i)))) {
        tries++;
        stay.retryLater(); // servers busy
      }
    }
    expect(tries, StayTracker.maxAttempts);
  });

  test('a poor fix still counts as the same area', () {
    final stay = StayTracker();
    stay.update(_at(50.0, 30.0), t0);
    // 220 m jump but the fix is only accurate to ±300 m
    expect(stay.update(_at(50.002, 30.0, accuracy: 300), t0.add(m(6))), isTrue);
  });
}
