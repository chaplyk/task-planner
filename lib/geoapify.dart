// Geoapify: nearby store lookups (store_detection.dart) and place minimaps
// (settings/place_details.dart).

/// Set in dart_defines.json (see the Makefile): {"GEOAPIFY_API_KEY": "..."}.
const geoapifyApiKey = String.fromEnvironment('GEOAPIFY_API_KEY');

const geoapifyApiBase = 'https://api.geoapify.com/v2';
const geoapifyMapsBase = 'https://maps.geoapify.com/v1';

bool get geoapifyConfigured => geoapifyApiKey.isNotEmpty;
