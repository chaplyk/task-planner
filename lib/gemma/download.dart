import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

const modelFile = 'gemma-4-E2B-it.litertlm';

const _modelUrl =
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/$modelFile';

/// Download progress of the local model in percent. Null when no download is running.
final localModelDownload = ValueNotifier<int?>(null);

Future<void>? _pendingDownload;

Future<bool> isLocalModelInstalled() => FlutterGemma.isModelInstalled(modelFile);

Future<void> downloadModel({void Function(int percent)? onProgress}) async {
  if (await isLocalModelInstalled()) {
    debugPrint('Model already installed');
    return;
  }

  await FlutterGemma.installModel(
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
  )
      .fromNetwork(_modelUrl, foreground: true)
      .withProgress((percent) {
        onProgress?.call(percent);
      })
      .install();
}

/// Downloads the local model if needed, publishing progress to [localModelDownload].
/// Repeated calls while a download is running return the same future.
Future<void> ensureLocalModel() {
  return _pendingDownload ??= () async {
    try {
      if (await isLocalModelInstalled()) return;
      localModelDownload.value = 0;
      await downloadModel(onProgress: (p) => localModelDownload.value = p);
    } finally {
      localModelDownload.value = null;
      _pendingDownload = null;
    }
  }();
}
