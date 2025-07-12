// frame_processor.dart
// Core VAD frame processing algorithm - ported from frame-processor.ts

import 'dart:typed_data';
import 'vad_messages.dart';
import 'speech_probabilities.dart';

const List<int> recommendedFrameSamples = [512, 1024, 1536];

class FrameProcessorOptions {
  /// Threshold over which values returned by the Silero VAD model will be considered as positively indicating speech.
  final double positiveSpeechThreshold;
  
  /// Threshold under which values returned by the Silero VAD model will be considered as indicating an absence of speech.
  final double negativeSpeechThreshold;
  
  /// Number of frames to prepend to the audio segment that will be passed to onSpeechEnd.
  final int preSpeechPadFrames;
  
  /// After a VAD value under the negativeSpeechThreshold is observed, the algorithm will wait redemptionFrames frames
  /// before running onSpeechEnd.
  final int redemptionFrames;
  
  /// Number of audio samples (under a sample rate of 16000) to comprise one "frame" to feed to the Silero VAD model.
  final int frameSamples;
  
  /// If an audio segment is detected as a speech segment according to initial algorithm but it has fewer than minSpeechFrames,
  /// it will be discarded and onVADMisfire will be run instead of onSpeechEnd.
  final int minSpeechFrames;
  
  /// If true, when the user pauses the VAD, it may trigger onSpeechEnd.
  final bool submitUserSpeechOnPause;

  const FrameProcessorOptions({
    required this.positiveSpeechThreshold,
    required this.negativeSpeechThreshold,
    required this.preSpeechPadFrames,
    required this.redemptionFrames,
    required this.frameSamples,
    required this.minSpeechFrames,
    required this.submitUserSpeechOnPause,
  });
}

class FrameProcessorDefaults {
  static const FrameProcessorOptions legacy = FrameProcessorOptions(
    positiveSpeechThreshold: 0.5,
    negativeSpeechThreshold: 0.35,
    preSpeechPadFrames: 1,
    redemptionFrames: 8,
    frameSamples: 1536,
    minSpeechFrames: 3,
    submitUserSpeechOnPause: false,
  );

  static const FrameProcessorOptions v5 = FrameProcessorOptions(
    positiveSpeechThreshold: 0.5,
    negativeSpeechThreshold: 0.35,
    preSpeechPadFrames: 3,
    redemptionFrames: 24,
    frameSamples: 512,
    minSpeechFrames: 9,
    submitUserSpeechOnPause: false,
  );
}

void validateOptions(FrameProcessorOptions options) {
  if (!recommendedFrameSamples.contains(options.frameSamples)) {
    print('Warning: You are using an unusual frame size');
  }
  if (options.positiveSpeechThreshold < 0 || options.positiveSpeechThreshold > 1) {
    throw ArgumentError('positiveSpeechThreshold should be a number between 0 and 1');
  }
  if (options.negativeSpeechThreshold < 0 || 
      options.negativeSpeechThreshold > options.positiveSpeechThreshold) {
    throw ArgumentError('negativeSpeechThreshold should be between 0 and positiveSpeechThreshold');
  }
  if (options.preSpeechPadFrames < 0) {
    throw ArgumentError('preSpeechPadFrames should be positive');
  }
  if (options.redemptionFrames < 0) {
    throw ArgumentError('redemptionFrames should be positive');
  }
}

abstract class FrameProcessorInterface {
  void resume();
  Future<void> process(Float32List frame, void Function(FrameProcessorEvent) handleEvent);
  void endSegment(void Function(FrameProcessorEvent) handleEvent);
}

class _AudioBufferItem {
  final Float32List frame;
  final bool isSpeech;

  _AudioBufferItem(this.frame, this.isSpeech);
}

Float32List _concatArrays(List<Float32List> arrays) {
  final totalLength = arrays.fold<int>(0, (sum, arr) => sum + arr.length);
  final result = Float32List(totalLength);
  
  int offset = 0;
  for (final arr in arrays) {
    result.setRange(offset, offset + arr.length, arr);
    offset += arr.length;
  }
  
  return result;
}

class FrameProcessor implements FrameProcessorInterface {
  final Future<SpeechProbabilities> Function(Float32List) modelProcessFunc;
  final void Function() modelResetFunc;
  final FrameProcessorOptions options;
  
  bool _speaking = false;
  final List<_AudioBufferItem> _audioBuffer = [];
  int _redemptionCounter = 0;
  int _speechFrameCount = 0;
  bool _active = false;
  bool _speechRealStartFired = false;

  FrameProcessor({
    required this.modelProcessFunc,
    required this.modelResetFunc,
    required this.options,
  }) {
    reset();
  }

  void reset() {
    _speaking = false;
    _speechRealStartFired = false;
    _audioBuffer.clear();
    modelResetFunc();
    _redemptionCounter = 0;
    _speechFrameCount = 0;
  }

  void pause(void Function(FrameProcessorEvent) handleEvent) {
    _active = false;
    if (options.submitUserSpeechOnPause) {
      endSegment(handleEvent);
    } else {
      reset();
    }
  }

  @override
  void resume() {
    _active = true;
  }

  @override
  void endSegment(void Function(FrameProcessorEvent) handleEvent) {
    final audioBuffer = List<_AudioBufferItem>.from(_audioBuffer);
    _audioBuffer.clear();
    final speaking = _speaking;
    reset();

    if (speaking) {
      final speechFrameCount = audioBuffer.where((item) => item.isSpeech).length;
      if (speechFrameCount >= options.minSpeechFrames) {
        final audio = _concatArrays(audioBuffer.map((item) => item.frame).toList());
        handleEvent(FrameProcessorEvent.speechEnd(audio));
      } else {
        handleEvent(const FrameProcessorEvent.vadMisfire());
      }
    }
  }

  @override
  Future<void> process(Float32List frame, void Function(FrameProcessorEvent) handleEvent) async {
    if (!_active) {
      return;
    }

    final probs = await modelProcessFunc(frame);
    final isSpeech = probs.isSpeech >= options.positiveSpeechThreshold;

    handleEvent(FrameProcessorEvent.frameProcessed(probs, frame));

    _audioBuffer.add(_AudioBufferItem(frame, isSpeech));

    if (isSpeech) {
      _speechFrameCount++;
      _redemptionCounter = 0;
    }

    if (isSpeech && !_speaking) {
      _speaking = true;
      handleEvent(const FrameProcessorEvent.speechStart());
    }

    if (_speaking &&
        _speechFrameCount == options.minSpeechFrames &&
        !_speechRealStartFired) {
      _speechRealStartFired = true;
      handleEvent(const FrameProcessorEvent.speechRealStart());
    }

    if (probs.isSpeech < options.negativeSpeechThreshold &&
        _speaking &&
        ++_redemptionCounter >= options.redemptionFrames) {
      _redemptionCounter = 0;
      _speechFrameCount = 0;
      _speaking = false;
      _speechRealStartFired = false;
      final audioBuffer = List<_AudioBufferItem>.from(_audioBuffer);
      _audioBuffer.clear();

      final speechFrameCount = audioBuffer.where((item) => item.isSpeech).length;

      if (speechFrameCount >= options.minSpeechFrames) {
        final audio = _concatArrays(audioBuffer.map((item) => item.frame).toList());
        handleEvent(FrameProcessorEvent.speechEnd(audio));
      } else {
        handleEvent(const FrameProcessorEvent.vadMisfire());
      }
    }

    if (!_speaking) {
      while (_audioBuffer.length > options.preSpeechPadFrames) {
        _audioBuffer.removeAt(0);
      }
      _speechFrameCount = 0;
    }
  }
}

class FrameProcessorEvent {
  final VadMessage msg;
  final Float32List? audio;
  final SpeechProbabilities? probs;
  final Float32List? frame;

  const FrameProcessorEvent._({
    required this.msg,
    this.audio,
    this.probs,
    this.frame,
  });

  const FrameProcessorEvent.vadMisfire() : this._(msg: VadMessage.vadMisfire);
  const FrameProcessorEvent.speechStart() : this._(msg: VadMessage.speechStart);
  const FrameProcessorEvent.speechRealStart() : this._(msg: VadMessage.speechRealStart);
  FrameProcessorEvent.speechEnd(Float32List audio) : this._(msg: VadMessage.speechEnd, audio: audio);
  FrameProcessorEvent.frameProcessed(SpeechProbabilities probs, Float32List frame) 
    : this._(msg: VadMessage.frameProcessed, probs: probs, frame: frame);
}