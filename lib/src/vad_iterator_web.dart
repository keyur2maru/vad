import 'package:vad/src/vad_iterator_base.dart';

import 'package:vad/src/vad_iterator_base.dart';

/// VadIteratorWeb class
/// Updated to work with pure Dart implementation but currently not fully implemented
/// Web platform primarily uses the VadHandler approach through VadHandlerWeb
/// This is mainly for compatibility with non-web platforms
class VadIteratorWeb implements VadIteratorBase {
  @override
  void forceEndSpeech() {
    throw UnimplementedError('VadIteratorWeb: Use VadHandlerWeb instead for web platform');
  }

  @override
  Future<void> initModel(String modelPath) {
    throw UnimplementedError('VadIteratorWeb: Use VadHandlerWeb instead for web platform');
  }

  @override
  Future<void> processAudioData(List<int> data) {
    throw UnimplementedError('VadIteratorWeb: Use VadHandlerWeb instead for web platform');
  }

  @override
  void release() {
    throw UnimplementedError('VadIteratorWeb: Use VadHandlerWeb instead for web platform');
  }

  @override
  void reset() {
    throw UnimplementedError('VadIteratorWeb: Use VadHandlerWeb instead for web platform');
  }

  @override
  void setVadEventCallback(VadEventCallback callback) {
    throw UnimplementedError('VadIteratorWeb: Use VadHandlerWeb instead for web platform');
  }
}

/// Create VadHandlerNonWeb instance
VadIteratorBase createVadIterator(
    {required bool isDebug,
    required int sampleRate,
    required int frameSamples,
    required double positiveSpeechThreshold,
    required double negativeSpeechThreshold,
    required int redemptionFrames,
    required int preSpeechPadFrames,
    required int minSpeechFrames,
    required bool submitUserSpeechOnPause,
    required String model}) {
  return VadIteratorWeb();
}
