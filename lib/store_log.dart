// A small event log for store detection, shown on the "Where am I?" debug screen.
//
// Store detection runs in several places: the background service (refreshing stores
// and geofences), the geofence plugin's worker (ENTER / DWELL / EXIT, GPS checks) and
// Kotlin (vehicle transitions, ActivityTransitionReceiver.kt). They all append lines to
// one file in the app's files directory, which the debug screen reads.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Also written by ActivityTransitionReceiver.kt (context.filesDir, the same directory).
const storeLogFileName = 'store_log.txt';

const _maxBytes = 256 * 1024;

Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/$storeLogFileName');

String _time(DateTime t) =>
    '${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

/// Prints [message] and appends it to the store log. Never throws.
Future<void> storeLog(String message) async {
  debugPrint('[store] $message');
  try {
    final file = await _file();
    // One write per line, opened for append: lines from different isolates don't mix.
    await file.writeAsString('${_time(DateTime.now())}  $message\n', mode: FileMode.append, flush: true);
    if (await file.length() > _maxBytes) {
      // Keep the newer half.
      final text = await file.readAsString();
      final cut = text.indexOf('\n', text.length ~/ 2);
      await file.writeAsString(cut < 0 ? '' : text.substring(cut + 1));
    }
  } catch (e) {
    debugPrint('Store log write failed: $e');
  }
}

/// The log's lines, oldest first.
Future<List<String>> readStoreLog() async {
  try {
    final file = await _file();
    if (!await file.exists()) return const [];
    return (await file.readAsLines()).where((l) => l.isNotEmpty).toList();
  } catch (e) {
    debugPrint('Store log read failed: $e');
    return const [];
  }
}

Future<void> clearStoreLog() async {
  try {
    final file = await _file();
    if (await file.exists()) await file.writeAsString('');
  } catch (e) {
    debugPrint('Store log clear failed: $e');
  }
}
