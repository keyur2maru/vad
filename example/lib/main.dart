// lib/main.dart

// Dart imports:
import 'dart:typed_data';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:permission_handler/permission_handler.dart';
import 'package:vad/vad.dart';

// Project imports:
import 'package:vad_example/custom_audio_stream_provider.dart';
import 'package:vad_example/recording.dart';
import 'package:vad_example/ui/app_theme.dart';
import 'package:vad_example/ui/vad_ui.dart';
import 'package:vad_example/vad_settings_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VAD Example',
      theme: AppTheme.getDarkTheme(),
      home: const VadManager(),
    );
  }
}

class VadManager extends StatefulWidget {
  const VadManager({super.key});

  @override
  State<VadManager> createState() => _VadManagerState();
}

class _VadManagerState extends State<VadManager> {
  List<Recording> recordings = [];
  late VadHandler _vadHandler;
  bool isListening = false;
  bool isPaused = false;
  late VadSettings settings;
  final VadUIController _uiController = VadUIController();
  int _chunkCounter = 0;

  // Custom audio stream provider
  CustomAudioStreamProvider? _customAudioProvider;

  @override
  void initState() {
    super.initState();
    settings = VadSettings();
    _initializeVad();
  }

  void _initializeVad() {
    _vadHandler = VadHandler.create(isDebug: true);
    _setupVadHandler();
  }

  void _startListening() async {
    _chunkCounter = 0; // Reset chunk counter for new session

    // Initialize and start custom audio provider if needed
    Stream<Uint8List>? customAudioStream;
    if (settings.useCustomAudioStream) {
      try {
        _customAudioProvider = CustomAudioStreamProvider();
        await _customAudioProvider!.initialize();
        await _customAudioProvider!.startRecording();
        customAudioStream = _customAudioProvider!.audioStream;
      } catch (e) {
        // Fall back to built-in recorder
        customAudioStream = null;
      }
    }

    await _vadHandler.startListening(
      frameSamples: settings.frameSamples,
      minSpeechFrames: settings.minSpeechFrames,
      preSpeechPadFrames: settings.preSpeechPadFrames,
      redemptionFrames: settings.redemptionFrames,
      endSpeechPadFrames: settings.endSpeechPadFrames,
      positiveSpeechThreshold: settings.positiveSpeechThreshold,
      negativeSpeechThreshold: settings.negativeSpeechThreshold,
      submitUserSpeechOnPause: settings.submitUserSpeechOnPause,
      model: settings.modelString,
      numFramesToEmit:
          settings.enableChunkEmission ? settings.numFramesToEmit : 0,
      audioStream: customAudioStream, // Pass custom stream if available
      recordConfig: RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        bitRate: 16,
        numChannels: 1,
        echoCancel: true,
        autoGain: true,
        noiseSuppress: true,
        androidConfig: const AndroidRecordConfig(
          speakerphone: true,
          audioSource: AndroidAudioSource.voiceCommunication,
          audioManagerMode: AudioManagerMode.modeInCommunication,
        ),
        iosConfig: IosRecordConfig(
          categoryOptions: const [
            IosAudioCategoryOption.defaultToSpeaker,
            IosAudioCategoryOption.allowBluetooth,
            IosAudioCategoryOption.allowBluetoothA2DP,
          ],
          // When using custom audio stream, that provider manages the session
          manageAudioSession: customAudioStream == null,
        ),
      ),
      // baseAssetPath: '/assets/', // Alternative to using the CDN (see README.md)
      // onnxWASMBasePath: '/assets/', // Alternative to using the CDN (see README.md)
    );
    setState(() {
      isListening = true;
      isPaused = false;
    });
  }

  Future<void> _stopListening() async {
    await _vadHandler.stopListening();

    // Clean up custom audio provider if it was used
    if (_customAudioProvider != null) {
      await _customAudioProvider!.dispose();
      _customAudioProvider = null;
    }

    setState(() {
      isListening = false;
      isPaused = false;
    });
  }

  void _pauseListening() async {
    await _vadHandler.pauseListening();
    setState(() {
      isPaused = true;
    });
  }

  void _setupVadHandler() {
    _vadHandler.onSpeechStart.listen((_) {
      setState(() {
        recordings.add(Recording(
          samples: [],
          type: RecordingType.speechStart,
        ));
      });
      _uiController.scrollToBottom?.call();
      debugPrint('Speech detected.');
    });

    _vadHandler.onRealSpeechStart.listen((_) {
      setState(() {
        recordings.add(Recording(
          samples: [],
          type: RecordingType.realSpeechStart,
        ));
      });
      _uiController.scrollToBottom?.call();
      debugPrint('Real speech start detected.');
    });

    _vadHandler.onSpeechEnd.listen((List<double> samples) {
      setState(() {
        recordings.add(Recording(
          samples: samples,
          type: RecordingType.speechEnd,
        ));
      });
      _uiController.scrollToBottom?.call();
      debugPrint('Speech ended, recording added. ${samples.length} samples');
    });

    _vadHandler.onFrameProcessed.listen((frameData) {
      // final isSpeech = frameData.isSpeech;
      // final notSpeech = frameData.notSpeech;
      // final firstFiveSamples = frameData.frame.length >= 5
      //     ? frameData.frame.sublist(0, 5)
      //     : frameData.frame;

      // debugPrint(
      //     'Frame processed - isSpeech: $isSpeech, notSpeech: $notSpeech');
      // debugPrint('First few audio samples: $firstFiveSamples');
    });

    _vadHandler.onVADMisfire.listen((_) {
      setState(() {
        recordings.add(Recording(type: RecordingType.misfire));
      });
      _uiController.scrollToBottom?.call();
      debugPrint('VAD misfire detected.');
    });

    _vadHandler.onError.listen((String message) {
      setState(() {
        recordings.add(Recording(type: RecordingType.error));
      });
      _uiController.scrollToBottom?.call();
      debugPrint('Error: $message');
    });

    _vadHandler.onEmitChunk.listen((chunkData) {
      if (settings.enableChunkEmission) {
        setState(() {
          recordings.add(Recording(
            samples: chunkData.samples,
            type: RecordingType.chunk,
            chunkIndex: _chunkCounter++,
            isFinal: chunkData.isFinal,
          ));
        });
        _uiController.scrollToBottom?.call();
        debugPrint(
            'Audio chunk emitted #$_chunkCounter (${chunkData.samples.length} samples)${chunkData.isFinal ? ' [FINAL]' : ''}');
      }
    });
  }

  void _applySettings(VadSettings newSettings) async {
    bool wasListening = isListening;

    // If we're currently listening, stop first
    if (isListening) {
      await _stopListening(); // Use _stopListening to properly clean up custom audio provider
    }

    // Update settings
    setState(() {
      settings = newSettings;
    });

    // Dispose and recreate VAD handler
    await _vadHandler.dispose();
    _initializeVad();

    // Restart listening if it was previously active
    if (wasListening) {
      _startListening();
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return VadSettingsDialog(
          settings: settings,
          onSettingsChanged: _applySettings,
        );
      },
    );
  }

  Future<void> _requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    debugPrint("Microphone permission status: $status");
  }

  @override
  Widget build(BuildContext context) {
    return VadUI(
      recordings: recordings,
      isListening: isListening,
      isPaused: isPaused,
      settings: settings,
      onStartListening: _startListening,
      onStopListening: _stopListening,
      onPauseListening: _pauseListening,
      onRequestMicrophonePermission: _requestMicrophonePermission,
      onShowSettingsDialog: _showSettingsDialog,
      controller: _uiController,
    );
  }

  @override
  void dispose() {
    if (isListening) {
      _vadHandler.stopListening();
    }
    _vadHandler.dispose();
    _customAudioProvider?.dispose();
    _uiController.dispose();
    super.dispose();
  }
}
