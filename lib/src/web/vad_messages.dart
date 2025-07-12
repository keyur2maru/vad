// vad_messages.dart
// Message types for VAD events - ported from messages.ts

enum VadMessage {
  audioFrame,
  speechStart,
  vadMisfire,
  speechEnd,
  speechStop,
  speechRealStart,
  frameProcessed,
}

extension VadMessageExtension on VadMessage {
  String get value {
    switch (this) {
      case VadMessage.audioFrame:
        return "AUDIO_FRAME";
      case VadMessage.speechStart:
        return "SPEECH_START";
      case VadMessage.vadMisfire:
        return "VAD_MISFIRE";
      case VadMessage.speechEnd:
        return "SPEECH_END";
      case VadMessage.speechStop:
        return "SPEECH_STOP";
      case VadMessage.speechRealStart:
        return "SPEECH_REAL_START";
      case VadMessage.frameProcessed:
        return "FRAME_PROCESSED";
    }
  }
}