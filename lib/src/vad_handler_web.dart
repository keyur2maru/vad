// vad_handler_web.dart

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'vad_handler_base.dart';
import 'web/audio_node_vad.dart';
import 'web/frame_processor.dart';
import 'web/speech_probabilities.dart';

/// VadHandlerWeb class
class VadHandlerWeb implements VadHandlerBase {
  final StreamController<List<double>> _onSpeechEndController =
      StreamController<List<double>>.broadcast();
  final StreamController<
          ({double isSpeech, double notSpeech, List<double> frame})>
      _onFrameProcessedController = StreamController<
          ({
            double isSpeech,
            double notSpeech,
            List<double> frame
          })>.broadcast();
  final StreamController<void> _onSpeechStartController =
      StreamController<void>.broadcast();
  final StreamController<void> _onRealSpeechStartController =
      StreamController<void>.broadcast();
  final StreamController<void> _onVADMisfireController =
      StreamController<void>.broadcast();
  final StreamController<String> _onErrorController =
      StreamController<String>.broadcast();

  /// Whether to print debug messages
  bool isDebug = false;
  
  /// Current MicVAD instance
  MicVAD? _micVAD;

  /// Constructor
  VadHandlerWeb({required bool isDebug}) {
    this.isDebug = isDebug;
  }

  @override
  Stream<List<double>> get onSpeechEnd => _onSpeechEndController.stream;

  @override
  Stream<({double isSpeech, double notSpeech, List<double> frame})>
      get onFrameProcessed => _onFrameProcessedController.stream;

  @override
  Stream<void> get onSpeechStart => _onSpeechStartController.stream;

  @override
  Stream<void> get onRealSpeechStart => _onRealSpeechStartController.stream;

  @override
  Stream<void> get onVADMisfire => _onVADMisfireController.stream;

  @override
  Stream<String> get onError => _onErrorController.stream;

  @override
  Future<void> startListening(
      {double positiveSpeechThreshold = 0.5,
      double negativeSpeechThreshold = 0.35,
      int preSpeechPadFrames = 1,
      int redemptionFrames = 8,
      int frameSamples = 1536,
      int minSpeechFrames = 3,
      bool submitUserSpeechOnPause = false,
      String model = 'legacy',
      String baseAssetPath = 'assets/packages/vad/assets/',
      String onnxWASMBasePath = 'assets/packages/vad/assets/',
      RecordConfig? recordConfig}) async {
    
    if (isDebug) {
      debugPrint(
          'VadHandlerWeb: startListening: Creating VAD with parameters: '
          'positiveSpeechThreshold: $positiveSpeechThreshold, '
          'negativeSpeechThreshold: $negativeSpeechThreshold, '
          'preSpeechPadFrames: $preSpeechPadFrames, '
          'redemptionFrames: $redemptionFrames, '
          'frameSamples: $frameSamples, '
          'minSpeechFrames: $minSpeechFrames, '
          'submitUserSpeechOnPause: $submitUserSpeechOnPause, '
          'model: $model, '
          'baseAssetPath: $baseAssetPath, '
          'onnxWASMBasePath: $onnxWASMBasePath');
    }

    try {
      // Create frame processor options
      final frameProcessorOptions = FrameProcessorOptions(
        positiveSpeechThreshold: positiveSpeechThreshold,
        negativeSpeechThreshold: negativeSpeechThreshold,
        preSpeechPadFrames: preSpeechPadFrames,
        redemptionFrames: redemptionFrames,
        frameSamples: frameSamples,
        minSpeechFrames: minSpeechFrames,
        submitUserSpeechOnPause: submitUserSpeechOnPause,
      );

      // Create AudioNodeVadOptions
      final options = AudioNodeVadOptions(
        frameProcessorOptions: frameProcessorOptions,
        onFrameProcessed: _onFrameProcessed,
        onVADMisfire: _onVADMisfire,
        onSpeechStart: _onSpeechStart,
        onSpeechEnd: _onSpeechEnd,
        onSpeechRealStart: _onSpeechRealStart,
        model: model,
        baseAssetPath: baseAssetPath,
        onnxWASMBasePath: onnxWASMBasePath,
      );

      // Create and start MicVAD
      _micVAD = await MicVAD.create(options);
      _micVAD!.start();
      
      if (isDebug) {
        debugPrint('VadHandlerWeb: VAD started successfully');
      }
    } catch (error, stackTrace) {
      if (isDebug) {
        debugPrint('VadHandlerWeb: Error starting VAD: $error');
        debugPrint('Stack trace: $stackTrace');
      }
      _onErrorController.add(error.toString());
    }
  }

  /// Callback handlers for VAD events
  void _onFrameProcessed(SpeechProbabilities probs, Float32List frame) {
    if (isDebug) {
      debugPrint(
          'VadHandlerWeb: onFrameProcessed: isSpeech: ${probs.isSpeech}, notSpeech: ${probs.notSpeech}');
    }
    _onFrameProcessedController.add((
      isSpeech: probs.isSpeech,
      notSpeech: probs.notSpeech,
      frame: frame.toList(),
    ));
  }

  void _onVADMisfire() {
    if (isDebug) {
      debugPrint('VadHandlerWeb: onVADMisfire');
    }
    _onVADMisfireController.add(null);
  }

  void _onSpeechStart() {
    if (isDebug) {
      debugPrint('VadHandlerWeb: onSpeechStart');
    }
    _onSpeechStartController.add(null);
  }

  void _onSpeechEnd(Float32List audio) {
    if (isDebug) {
      debugPrint(
          'VadHandlerWeb: onSpeechEnd: audio length: ${audio.length}');
    }
    _onSpeechEndController.add(audio.toList());
  }

  void _onSpeechRealStart() {
    if (isDebug) {
      debugPrint('VadHandlerWeb: onSpeechRealStart');
    }
    _onRealSpeechStartController.add(null);
  }

  @override
  Future<void> dispose() async {
    if (isDebug) {
      debugPrint('VadHandlerWeb: dispose');
    }
    
    _micVAD?.destroy();
    _micVAD = null;
    
    _onSpeechEndController.close();
    _onFrameProcessedController.close();
    _onSpeechStartController.close();
    _onRealSpeechStartController.close();
    _onVADMisfireController.close();
    _onErrorController.close();
  }

  @override
  Future<void> stopListening() async {
    if (isDebug) {
      debugPrint('VadHandlerWeb: stopListening');
    }
    
    _micVAD?.destroy();
    _micVAD = null;
  }

  @override
  Future<void> pauseListening() async {
    if (isDebug) {
      debugPrint('VadHandlerWeb: pauseListening');
    }
    
    _micVAD?.pause();
  }
}

/// Create a VAD handler for the web
/// isDebug is used to print debug messages
/// modelPath is not used in the web implementation, adding it will not have any effect
VadHandlerBase createVadHandler({required isDebug, modelPath}) =>
    VadHandlerWeb(isDebug: isDebug);
