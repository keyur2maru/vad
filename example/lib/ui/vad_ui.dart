// lib/ui/vad_ui.dart

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:audioplayers/audioplayers.dart' as audioplayers;

// Project imports:
import 'package:vad_example/audio_utils.dart';
import 'package:vad_example/recording.dart';
import 'package:vad_example/vad_settings_dialog.dart';

class VadUIController {
  Function? scrollToBottom;

  void dispose() {
    scrollToBottom = null;
  }
}

class VadUI extends StatefulWidget {
  final List<Recording> recordings;
  final bool isListening;
  final bool isPaused;
  final VadSettings settings;
  final Function() onStartListening;
  final Function() onStopListening;
  final Function() onPauseListening;
  final Function() onRequestMicrophonePermission;
  final Function() onShowSettingsDialog;
  final VadUIController? controller;

  const VadUI({
    super.key,
    required this.recordings,
    required this.isListening,
    required this.isPaused,
    required this.settings,
    required this.onStartListening,
    required this.onStopListening,
    required this.onPauseListening,
    required this.onRequestMicrophonePermission,
    required this.onShowSettingsDialog,
    this.controller,
  });

  @override
  State<VadUI> createState() => _VadUIState();
}

class _VadUIState extends State<VadUI> {
  final audioplayers.AudioPlayer _audioPlayer = audioplayers.AudioPlayer();
  final ScrollController _scrollController = ScrollController();

  // Audio player state
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  int? _currentlyPlayingIndex;

  @override
  void initState() {
    super.initState();
    _initializeAudioPlayer();
    _setupAudioPlayerListeners();
    if (widget.controller != null) {
      widget.controller!.scrollToBottom = _scrollToBottom;
    }
  }

  Future<void> _initializeAudioPlayer() async {
    await _audioPlayer.setAudioContext(
      audioplayers.AudioContext(
        iOS: audioplayers.AudioContextIOS(
          options: const {audioplayers.AVAudioSessionOptions.mixWithOthers},
          category: audioplayers.AVAudioSessionCategory.playAndRecord,
        ),
        android: const audioplayers.AudioContextAndroid(
          contentType: audioplayers.AndroidContentType.speech,
          usageType: audioplayers.AndroidUsageType.media,
          audioFocus: audioplayers.AndroidAudioFocus.gainTransientMayDuck,
        ),
      ),
    );
  }

  void _setupAudioPlayerListeners() {
    _audioPlayer.onDurationChanged.listen((Duration duration) {
      setState(() => _duration = duration);
    });

    _audioPlayer.onPositionChanged.listen((Duration position) {
      setState(() => _position = position);
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
        _currentlyPlayingIndex = null;
      });
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() {
        _isPlaying = state == audioplayers.PlayerState.playing;
      });
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _playRecording(Recording recording, int index) async {
    if (recording.type == RecordingType.misfire) return;

    try {
      if (_currentlyPlayingIndex == index && _isPlaying) {
        await _audioPlayer.pause();
        setState(() {
          _isPlaying = false;
        });
      } else {
        if (_currentlyPlayingIndex != index) {
          String uri = AudioUtils.createWavUrl(recording.samples!);
          await _audioPlayer.play(audioplayers.UrlSource(uri));
          setState(() {
            _currentlyPlayingIndex = index;
            _isPlaying = true;
          });
        } else {
          await _audioPlayer.resume();
          setState(() {
            _isPlaying = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
    }
  }

  Future<void> _seekTo(Duration position) async {
    await _audioPlayer.seek(position);
    setState(() {
      _position = position;
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
  }

  Widget _buildRecordingItem(Recording recording, int index) {
    final bool isCurrentlyPlaying = _currentlyPlayingIndex == index;
    final bool hasAudio = (recording.type == RecordingType.speechEnd ||
            recording.type == RecordingType.chunk) &&
        recording.samples != null;

    // Icon and color based on recording type
    IconData typeIcon;
    Color iconColor;
    Color backgroundColor;
    String typeTitle;

    switch (recording.type) {
      case RecordingType.speechStart:
        typeIcon = Icons.mic;
        iconColor = Colors.white;
        backgroundColor = Colors.orange;
        typeTitle = 'Speech Detected';
        break;
      case RecordingType.realSpeechStart:
        typeIcon = Icons.record_voice_over;
        iconColor = Colors.white;
        backgroundColor = Colors.green;
        typeTitle = 'Real Speech Started';
        break;
      case RecordingType.speechEnd:
        typeIcon =
            isCurrentlyPlaying && _isPlaying ? Icons.pause : Icons.play_arrow;
        iconColor = Colors.blue[100]!;
        backgroundColor = Colors.blue[900]!;
        typeTitle = 'Recorded Speech';
        break;
      case RecordingType.misfire:
        typeIcon = Icons.warning_amber_rounded;
        iconColor = Colors.white;
        backgroundColor = Colors.red;
        typeTitle = 'VAD Misfire';
        break;
      case RecordingType.error:
        typeIcon = Icons.error_outline;
        iconColor = Colors.white;
        backgroundColor = Colors.deepPurple;
        typeTitle = 'Error Event';
        break;
      case RecordingType.chunk:
        typeIcon = hasAudio
            ? (isCurrentlyPlaying && _isPlaying
                ? Icons.pause
                : Icons.play_arrow)
            : Icons.graphic_eq;
        iconColor = hasAudio ? Colors.teal[100]! : Colors.white;
        backgroundColor = hasAudio ? Colors.teal[900]! : Colors.teal;
        typeTitle =
            'Audio Chunk ${recording.chunkIndex != null ? '#${recording.chunkIndex}' : ''}${recording.isFinal == true ? ' [FINAL]' : ''}';
        break;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: backgroundColor,
              child: Icon(typeIcon, color: iconColor),
            ),
            title: Text(
              '$typeTitle ${index + 1}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: recording.type == RecordingType.error ||
                        recording.type == RecordingType.misfire
                    ? Colors.red[300]
                    : null,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatTimestamp(recording.timestamp)),
                if (hasAudio)
                  Text(
                    '${(recording.samples!.length / 16000).toStringAsFixed(1)} seconds',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
              ],
            ),
            onTap: hasAudio ? () => _playRecording(recording, index) : null,
          ),
          if (isCurrentlyPlaying && hasAudio) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: _position.inMilliseconds.toDouble(),
                      min: 0,
                      max: _duration.inMilliseconds.toDouble() + 1,
                      onChanged: (value) {
                        _seekTo(Duration(milliseconds: value.toInt()));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(_position)),
                        Text(_formatDuration(_duration)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("VAD Example"),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            padding: const EdgeInsets.symmetric(horizontal: 48.0),
            icon: const Icon(Icons.settings),
            onPressed: widget.onShowSettingsDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              itemCount: widget.recordings.length,
              itemBuilder: (context, index) {
                return _buildRecordingItem(widget.recordings[index], index);
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.black,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  spreadRadius: 1,
                  blurRadius: 10,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Center(
                      child: Text(
                        'Model: ${widget.settings.model == VadModel.v5 ? "v5" : "v4"}',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Center(
                      child: Text(
                        'Frame: ${widget.settings.calculateFrameTime()}',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: widget.isListening && !widget.isPaused
                          ? null
                          : widget.onStartListening,
                      icon: Icon(widget.isPaused
                          ? Icons.play_arrow
                          : widget.isListening
                              ? Icons.mic
                              : Icons.mic),
                      label: Text(widget.isPaused
                          ? "Resume"
                          : widget.isListening
                              ? "Listening..."
                              : "Start Listening"),
                    ),
                    if (widget.isListening && !widget.isPaused) ...[
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: widget.onPauseListening,
                        icon: const Icon(Icons.pause),
                        label: const Text("Pause"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                        ),
                      ),
                    ],
                    if (widget.isListening || widget.isPaused) ...[
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: widget.onStopListening,
                        icon: const Icon(Icons.stop),
                        label: const Text("Stop"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: widget.onRequestMicrophonePermission,
                  icon: const Icon(Icons.settings_voice),
                  label: const Text("Request Microphone Permission"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _scrollController.dispose();
    if (widget.controller != null) {
      widget.controller!.dispose();
    }
    super.dispose();
  }
}
