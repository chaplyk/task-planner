// Geoapify: nearby store lookups (store_detection.dart) and place minimaps
// (settings/place_details.dart).

/// Set in dart_defines.json (see the Makefile): {"GEOAPIFY_API_KEY": "..."}.
const geoapifyApiKey = String.fromEnvironment('GEOAPIFY_API_KEY');

const geoapifyApiBase = 'https://api.geoapify.com/v2';
const geoapifyMapsBase = 'https://maps.geoapify.com/v1';

bool get geoapifyConfigured => geoapifyApiKey.isNotEmpty;

const _geocodeBase = 'https://api.geoapify.com/v1/geocode';

/// Raster map tiles for flutter_map: `{r}` becomes "@2x" on high-density screens.
String geoapifyTileUrl({required bool dark, String apiKey = geoapifyApiKey}) =>
    '$geoapifyMapsBase/tile/${dark ? 'dark-matter' : 'osm-bright'}/{z}/{x}/{y}{r}.png?apiKey=$apiKey';

/// Address suggestions for [text], ranked by closeness to [lat], [lon].
Uri autocompleteUri(String text, {required double lat, required double lon, String apiKey = geoapifyApiKey}) =>
    Uri.parse('$_geocodeBase/autocomplete').replace(queryParameters: {
      'text': text,
      'bias': 'proximity:${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)}',
      'limit': '5',
      'format': 'json',
      'apiKey': apiKey,
    });

/// The address at a point.
Uri reverseGeocodeUri({required double lat, required double lon, String apiKey = geoapifyApiKey}) =>
    Uri.parse('$_geocodeBase/reverse').replace(queryParameters: {
      'lat': lat.toStringAsFixed(6),
      'lon': lon.toStringAsFixed(6),
      'format': 'json',
      'apiKey': apiKey,
    });

/// One geocoding result: [title] is the main line (place name or street and number),
/// [name] is set only for named places (shops, landmarks).
typedef GeocodeResult = ({String title, String? subtitle, String? name, double lat, double lon});

/// Results of an autocomplete or reverse geocoding call made with `format=json`.
List<GeocodeResult> parseGeocodeResults(Map<String, dynamic> json) => [
  for (final r in (json['results'] as List?) ?? const [])
    if (r is Map && r['lat'] is num && r['lon'] is num && (r['address_line1'] ?? r['formatted']) is String)
      (
        title: (r['address_line1'] ?? r['formatted']) as String,
        subtitle: r['address_line2'] as String?,
        name: r['name'] as String?,
        lat: (r['lat'] as num).toDouble(),
        lon: (r['lon'] as num).toDouble(),
      ),
];
