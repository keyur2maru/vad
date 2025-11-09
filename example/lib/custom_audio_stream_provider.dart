// lib/custom_audio_stream_provider.dart

// Dart imports:
import 'dart:typed_data';

// Package imports:
import 'package:record/record.dart';

/// Custom audio stream provider using the record library
///
/// This demonstrates how to use a custom audio recording solution
/// with the VAD package by providing a Stream<Uint8List>.
/// Uses the same record library as VadHandler to ensure compatibility.
class CustomAudioStreamProvider {
  AudioRecorder? _audioRecorder;
  Stream<Uint8List>? _audioStream;
  bool _isRecording = false;

  /// Get the audio stream that can be passed to VadHandler
  Stream<Uint8List>? get audioStream => _audioStream;

  /// Check if the provider is currently recording
  bool get isRecording => _isRecording;

  /// Initialize the recorder
  Future<void> initialize() async {
    _audioRecorder = AudioRecorder();
  }

  /// Start recording audio
  Future<void> startRecording() async {
    if (_audioRecorder == null || _isRecording) return;

    // Check microphone permission
    final hasPermission = await _audioRecorder!.hasPermission();
    if (!hasPermission) {
      throw Exception('Microphone permission not granted');
    }

    // Configure recording with same settings as VadHandler
    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      bitRate: 16,
      numChannels: 1,
      echoCancel: true,
      autoGain: true,
      noiseSuppress: true,
      androidConfig: AndroidRecordConfig(
        audioSource: AndroidAudioSource.voiceCommunication,
        audioManagerMode: AudioManagerMode.modeInCommunication,
        speakerphone: true,
        manageBluetooth: true,
        useLegacy: false,
      ),
    );

    await _audioRecorder?.ios?.manageAudioSession(true);

    // Start recording and get the stream
    _audioStream = await _audioRecorder!.startStream(config);
    _isRecording = true;
  }

  /// Stop recording audio
  Future<void> stopRecording() async {
    if (_audioRecorder == null || !_isRecording) return;

    await _audioRecorder!.stop();
    _isRecording = false;
  }

  /// Dispose and clean up resources
  Future<void> dispose() async {
    if (_isRecording) {
      await stopRecording();
    }
    await _audioRecorder?.dispose();
    _audioRecorder = null;
    _audioStream = null;
  }
}
