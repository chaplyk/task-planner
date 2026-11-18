import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nagadai/settings/place_details.dart';

void main() {
  test('static map: lon,lat order, theme style and pin colour', () {
    final light = staticMapUri(lat: 50.45, lon: 30.52, dark: false, pin: const Color(0xFF30628A), apiKey: 'k');
    expect(light.path, '/v1/staticmap');
    final q = light.queryParameters;
    expect(q['style'], 'positron');
    expect(q['center'], 'lonlat:30.520000,50.450000');
    expect(q['marker'], 'lonlat:30.520000,50.450000;color:#30628a;size:large');
    expect(q['apiKey'], 'k');
    // "#" must be escaped in the URL, or everything after it is dropped as a fragment.
    expect(light.toString(), contains('color%3A%2330628a'));

    final dark = staticMapUri(lat: 50.45, lon: 30.52, dark: true, pin: const Color(0xFFDAEBFF), apiKey: 'k');
    expect(dark.queryParameters['style'], 'dark-matter');
  });

  test('distance labels', () {
    expect(distanceLabel(40), 'You’re here');
    expect(distanceLabel(75), 'You’re here');
    expect(distanceLabel(347), '350 m away');
    expect(distanceLabel(2380), '2.4 km away');
    expect(distanceLabel(12600), '13 km away');
  });
}
