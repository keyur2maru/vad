// audio_node_vad.dart
// Web Audio API integration for VAD - ported from real-time-vad.ts

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

import 'frame_processor.dart';
import 'resampler.dart';
import 'onnx_runtime_web.dart';
import 'speech_probabilities.dart';

class AudioNodeVadOptions {
  final FrameProcessorOptions frameProcessorOptions;
  final void Function(SpeechProbabilities, Float32List) onFrameProcessed;
  final void Function() onVADMisfire;
  final void Function() onSpeechStart;
  final void Function(Float32List) onSpeechEnd;
  final void Function() onSpeechRealStart;
  final String model;
  final String baseAssetPath;
  final String onnxWASMBasePath;

  const AudioNodeVadOptions({
    required this.frameProcessorOptions,
    required this.onFrameProcessed,
    required this.onVADMisfire,
    required this.onSpeechStart,
    required this.onSpeechEnd,
    required this.onSpeechRealStart,
    required this.model,
    required this.baseAssetPath,
    required this.onnxWASMBasePath,
  });
}

class AudioNodeVAD {
  final web.AudioContext _context;
  final AudioNodeVadOptions _options;
  late final FrameProcessor _frameProcessor;
  late final Resampler _resampler;
  
  web.AudioNode? _audioNode;
  web.GainNode? _gainNode;
  
  AudioNodeVAD._(this._context, this._options);

  static Future<AudioNodeVAD> create(
    web.AudioContext context,
    AudioNodeVadOptions options,
  ) async {
    final instance = AudioNodeVAD._(context, options);
    await instance._initialize();
    return instance;
  }

  Future<void> _initialize() async {
    // Load the appropriate model
    final modelFile = _options.model == 'v5' ? 'silero_vad_v5.onnx' : 'silero_vad_legacy.onnx';
    final modelUrl = '${_options.baseAssetPath}$modelFile';
    
    late VadModel model;
    if (_options.model == 'v5') {
      model = await SileroV5Model.create(modelUrl);
    } else {
      model = await SileroLegacyModel.create(modelUrl);
    }

    // Create frame processor
    _frameProcessor = FrameProcessor(
      modelProcessFunc: model.process,
      modelResetFunc: model.resetState,
      options: _options.frameProcessorOptions,
    );

    // Setup audio processing
    await _setupAudioNode();
  }

  Future<void> _setupAudioNode() async {
    // Create resampler for audio processing
    _resampler = Resampler(ResamplerOptions(
      nativeSampleRate: _context.sampleRate.toInt(),
      targetSampleRate: 16000, // VAD models expect 16kHz
      targetFrameSize: _options.frameProcessorOptions.frameSamples,
    ));

    // Create ScriptProcessor node for audio processing
    const bufferSize = 4096;
    _audioNode = _context.createScriptProcessor(bufferSize, 1, 1);
    
    // Create gain node with zero gain to handle the audio chain
    _gainNode = _context.createGain();
    _gainNode!.gain.value = 0.0;

    // Set up audio processing handler
    bool processingAudio = false;
    (_audioNode! as web.ScriptProcessorNode).onaudioprocess = (web.AudioProcessingEvent e) async {
      if (processingAudio) return;
      processingAudio = true;

      try {
        final input = e.inputBuffer.getChannelData(0);
        final output = e.outputBuffer.getChannelData(0);
        
        // Clear output
        for (int i = 0; i < output.length; i++) {
          output[i] = 0.0;
        }

        // Convert to Float32List
        final inputFrame = Float32List(input.length);
        for (int i = 0; i < input.length; i++) {
          inputFrame[i] = input[i];
        }

        // Process through resampler
        final frames = _resampler.process(inputFrame);
        for (final frame in frames) {
          await _processFrame(frame);
        }
      } catch (error) {
        print('Error processing audio: $error');
      } finally {
        processingAudio = false;
      }
    }.toJS;

    // Connect audio chain
    _audioNode!.connectNode(_gainNode!);
    _gainNode!.connectNode(_context.destination);
  }

  void pause() {
    _frameProcessor.pause(_handleFrameProcessorEvent);
  }

  void start() {
    _frameProcessor.resume();
  }

  void connect(web.AudioNode node) {
    node.connectNode(_audioNode!);
  }

  Future<void> _processFrame(Float32List frame) async {
    await _frameProcessor.process(frame, _handleFrameProcessorEvent);
  }

  void _handleFrameProcessorEvent(FrameProcessorEvent event) {
    switch (event.msg) {
      case VadMessage.frameProcessed:
        _options.onFrameProcessed(event.probs!, event.frame!);
        break;
      case VadMessage.speechStart:
        _options.onSpeechStart();
        break;
      case VadMessage.speechRealStart:
        _options.onSpeechRealStart();
        break;
      case VadMessage.vadMisfire:
        _options.onVADMisfire();
        break;
      case VadMessage.speechEnd:
        _options.onSpeechEnd(event.audio!);
        break;
      default:
        break;
    }
  }

  void destroy() {
    _audioNode?.disconnect();
    _gainNode?.disconnect();
  }

  void setFrameProcessorOptions(FrameProcessorOptions options) {
    // Update frame processor options - would need to recreate frame processor
    // For now, this is a placeholder
    print('setFrameProcessorOptions called - implementation needed');
  }
}

class MicVAD {
  final AudioNodeVadOptions _options;
  final web.AudioContext _audioContext;
  final web.MediaStream _stream;
  final AudioNodeVAD _audioNodeVAD;
  final web.MediaStreamAudioSourceNode _sourceNode;
  bool _listening = false;

  MicVAD._(
    this._options,
    this._audioContext,
    this._stream,
    this._audioNodeVAD,
    this._sourceNode,
  );

  static Future<MicVAD> create(AudioNodeVadOptions options) async {
    // Get microphone stream
    final stream = await web.window.navigator.mediaDevices.getUserMedia({
      'audio': {
        'channelCount': 1,
        'echoCancellation': true,
        'autoGainControl': true,
        'noiseSuppression': true,
      }.jsify()!,
    }.jsify()!).toDart;

    final audioContext = web.AudioContext();
    final sourceNode = web.MediaStreamAudioSourceNode(audioContext, {
      'mediaStream': stream,
    }.jsify()!);

    final audioNodeVAD = await AudioNodeVAD.create(audioContext, options);
    audioNodeVAD.connect(sourceNode);

    return MicVAD._(options, audioContext, stream, audioNodeVAD, sourceNode);
  }

  void pause() {
    _audioNodeVAD.pause();
    _listening = false;
  }

  void start() {
    _audioNodeVAD.start();
    _listening = true;
  }

  void destroy() {
    if (_listening) {
      pause();
    }
    
    // Stop all tracks
    final tracks = _stream.getAudioTracks();
    for (int i = 0; i < tracks.length; i++) {
      tracks[i].stop();
    }
    
    _sourceNode.disconnect();
    _audioNodeVAD.destroy();
    _audioContext.close();
  }

  void setOptions(FrameProcessorOptions options) {
    _audioNodeVAD.setFrameProcessorOptions(options);
  }
}