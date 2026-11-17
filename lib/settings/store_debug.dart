import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:native_geofence/native_geofence.dart';

import '../place_types.dart';
import '../store_detection.dart';
import '../store_log.dart';

/// Debug: shows how store detection sees the current spot (the same lookup and visit
/// check the background uses) and the live store log: refreshes, geofences, ENTER /
/// DWELL / EXIT, GPS checks, vehicle state and notifications.
class StoreDebugScreen extends StatefulWidget {
  const StoreDebugScreen({super.key});

  @override
  State<StoreDebugScreen> createState() => _StoreDebugScreenState();
}

class _StoreDebugScreenState extends State<StoreDebugScreen> {
  Position? _position;
  String? _positionError;
  List<StorePoi>? _stores;
  bool _looking = false;
  int? _storeGeofences;
  List<String> _log = const [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _lookAround();
    _reloadLog();
    // The background writes to the log while this screen is open.
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _reloadLog());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reloadLog() async {
    final lines = await readStoreLog();
    List<String> ids = const [];
    try {
      ids = await NativeGeofenceManager.instance.getRegisteredGeofenceIds();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _log = lines;
      _storeGeofences = ids.where((id) => id.startsWith(storeGeofencePrefix)).length;
    });
  }

  Future<void> _lookAround() async {
    setState(() {
      _looking = true;
      _positionError = null;
    });
    await storeLog('Debug: "Where am I?" lookup');
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );
      final stores = await fetchNearbyStores(position.latitude, position.longitude, storeTypes.keys.toSet());
      if (!mounted) return;
      setState(() {
        _position = position;
        _stores = stores;
      });
    } catch (e) {
      if (mounted) setState(() => _positionError = '$e');
    } finally {
      if (mounted) setState(() => _looking = false);
    }
    _reloadLog();
  }

  Future<void> _clearLog() async {
    await clearStoreLog();
    await _reloadLog();
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;
    final mono = Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Where am I?'),
        actions: [
          IconButton(
            tooltip: 'Look again',
            onPressed: _looking ? null : _lookAround,
            icon: const Icon(Icons.my_location),
          ),
          IconButton(tooltip: 'Clear log', onPressed: _clearLog, icon: const Icon(Icons.delete_sweep_outlined)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_looking) const LinearProgressIndicator(),
          if (_positionError != null) Text('No position: $_positionError'),
          if (position != null)
            Text(
              'Fix ±${position.accuracy.round()} m'
              '${fixUsable(position) ? '' : ' · too coarse to confirm a visit (needs ±${requiredFixAccuracy.round()} m)'}'
              ' · ${_storeGeofences ?? '?'} store geofences registered',
            ),
          const SizedBox(height: 8),
          if (!_looking && position != null && _stores == null)
            const Text('Lookup failed: see the log below.')
          else if (_stores?.isEmpty ?? false)
            Text('No matching stores within ${poiSearchRadius.round()} m.'),
          for (final s in (_stores ?? const <StorePoi>[]).take(15))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Text(s.storeKeys.map((k) => storeTypes[k]!.emoji).join(), style: const TextStyle(fontSize: 20)),
              title: Text(s.name),
              subtitle: Text(
                '${s.distanceTo(position!.latitude, position.longitude).round()} m'
                '${fixMatchesStore(position, s) ? ' · you are here' : ''}',
              ),
            ),
          const Divider(height: 32),
          Text('Log (newest first)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_log.isEmpty) const Text('Nothing logged yet.'),
          for (final line in _log.reversed.take(400))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: SelectableText(line, style: mono),
            ),
        ],
      ),
    );
  }
}
