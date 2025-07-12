// model_utils.dart
// Utility functions for VAD model handling

String getModelUrl(String baseAssetPath, String model) {
  final modelFile = model == 'v5' ? 'silero_vad_v5.onnx' : 'silero_vad_legacy.onnx';
  return '$baseAssetPath$modelFile';
}

Map<String, String> getModelInputNames(String model) {
  if (model == 'v5') {
    return {
      'input': 'input',
      'state_h': 'h0',
      'state_c': 'c0',
    };
  } else {
    return {
      'input': 'input',
      'state_h': 'h',
      'state_c': 'c',
    };
  }
}

Map<String, String> getModelOutputNames(String model) {
  if (model == 'v5') {
    return {
      'output': 'output',
      'state_h': 'hn',
      'state_c': 'cn',
    };
  } else {
    return {
      'output': 'output',
      'state_h': 'hn',
      'state_c': 'cn',
    };
  }
}