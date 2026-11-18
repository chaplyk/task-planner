import 'package:flutter_test/flutter_test.dart';
import 'package:nagadai/geoapify.dart';

void main() {
  test('tile URL picks the style by theme and keeps flutter_map placeholders', () {
    expect(geoapifyTileUrl(dark: false, apiKey: 'k'), 'https://maps.geoapify.com/v1/tile/positron/{z}/{x}/{y}{r}.png?apiKey=k');
    expect(geoapifyTileUrl(dark: true, apiKey: 'k'), contains('/dark-matter-dark-grey/'));
  });

  test('autocomplete is biased to the map centre, lon first', () {
    final q = autocompleteUri('Main St 5', lat: 50.45, lon: 30.52, apiKey: 'k').queryParameters;
    expect(q['text'], 'Main St 5');
    expect(q['bias'], 'proximity:30.520000,50.450000');
    expect(q['format'], 'json');
  });

  test('reverse geocoding asks for one point', () {
    final q = reverseGeocodeUri(lat: 50.45, lon: 30.52, apiKey: 'k').queryParameters;
    expect([q['lat'], q['lon'], q['format']], ['50.450000', '30.520000', 'json']);
  });

  test('parses autocomplete and reverse results (shape of real responses)', () {
    final results = parseGeocodeResults({
      'results': [
        {
          'name': 'Eiffel Tower',
          'address_line1': 'Eiffel Tower',
          'address_line2': '5 Avenue Anatole France, 75007 Paris, France',
          'lat': 48.8582599,
          'lon': 2.2945006,
        },
        // A building: no name, the street is the main line.
        {'address_line1': '5 Avenue Anatole France', 'address_line2': '75007 Paris, France', 'lat': 48.85, 'lon': 2.29},
        {'address_line1': 'no coordinates'},
      ],
      'query': {},
    });
    expect(results, hasLength(2));
    expect(results[0].name, 'Eiffel Tower');
    expect(results[0].subtitle, '5 Avenue Anatole France, 75007 Paris, France');
    expect(results[1].name, isNull);
    expect(results[1].title, '5 Avenue Anatole France');
    expect(parseGeocodeResults({}), isEmpty);
  });
}
