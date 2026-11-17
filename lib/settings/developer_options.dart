import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../activity_watch.dart';
import '../gemma/download.dart';
import '../llm/model_choice.dart';
import '../store_detection.dart';
import 'model.dart';
import 'store_debug.dart';

const _prefKey = 'developer_options';

/// Whether the hidden "Developer options" menu is shown in Settings. Turned on by
/// tapping the version three times, off again from the menu itself.
final developerOptionsNotifier = ValueNotifier<bool>(false);

Future<void> loadDeveloperOptions() async {
  final prefs = await SharedPreferences.getInstance();
  developerOptionsNotifier.value = prefs.getBool(_prefKey) ?? false;
}

Future<void> setDeveloperOptions(bool enabled) async {
  developerOptionsNotifier.value = enabled;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_prefKey, enabled);
}

class DeveloperOptionsScreen extends StatefulWidget {
  const DeveloperOptionsScreen({super.key});

  @override
  State<DeveloperOptionsScreen> createState() => _DeveloperOptionsScreenState();
}

class _DeveloperOptionsScreenState extends State<DeveloperOptionsScreen> {
  int? _refreshMinutes; // null until loaded

  @override
  void initState() {
    super.initState();
    storeRefreshPeriod().then((p) {
      if (mounted) setState(() => _refreshMinutes = p.inMinutes);
    });
  }

  Future<void> _saveRefreshMinutes(int minutes) async {
    await setStoreRefreshMinutes(minutes);
    await applyStoreRefreshPeriod();
  }

  Future<void> _hide() async {
    await setDeveloperOptions(false);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _refreshMinutes;
    return Scaffold(
      appBar: AppBar(title: const Text('Developer options')),
      body: ListView(
        children: [
          ValueListenableBuilder<LlmModel>(
            valueListenable: modelChoiceNotifier,
            builder: (context, model, _) => ListTile(
              title: const Text('Model'),
              subtitle: ValueListenableBuilder<int?>(
                valueListenable: localModelDownload,
                builder: (context, percent, _) => Text(
                  percent == null ? modelLabel(model) : 'Downloading on-device model... $percent%',
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ModelScreen())),
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Where am I? (debug)'),
            subtitle: const Text('Test store detection here and see its log'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const StoreDebugScreen())),
          ),
          const Divider(),
          ListTile(
            title: const Text('Geofence refresh'),
            subtitle: Text(
              minutes == null
                  ? ''
                  : 'Every $minutes min, nearby stores are checked and their geofences renewed. '
                      'Geofences expire after $minutes min.',
            ),
            trailing: Text(minutes == null ? '' : '$minutes min'),
          ),
          if (minutes != null)
            Slider(
              value: minutes.toDouble(),
              min: minStoreRefreshMinutes.toDouble(),
              max: maxStoreRefreshMinutes.toDouble(),
              divisions: maxStoreRefreshMinutes - minStoreRefreshMinutes,
              label: '$minutes min',
              onChanged: (v) => setState(() => _refreshMinutes = v.round()),
              onChangeEnd: (v) => _saveRefreshMinutes(v.round()),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.visibility_off_outlined),
            title: const Text('Hide developer options'),
            onTap: _hide,
          ),
        ],
      ),
    );
  }
}
