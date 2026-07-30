import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

const modelFile = 'gemma-4-E2B-it.litertlm';

const _modelUrl =
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/'
    'resolve/main/$modelFile';

Future<void> downloadModel({void Function(int percent)? onProgress}) async {
  if (await FlutterGemma.isModelInstalled(modelFile)) {
    debugPrint('Model already installed');
    return;
  }

  debugPrint('Downloading model...');
  await FlutterGemma.installModel(
    modelType: ModelType.gemma4,
    fileType: ModelFileType.litertlm,
  )
      .fromNetwork(_modelUrl, foreground: true)
      .withProgress((percent) {
        onProgress?.call(percent);
      })
      .install();
  debugPrint('Model downloaded');
}
