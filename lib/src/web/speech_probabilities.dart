// speech_probabilities.dart
// Speech probability model for VAD

class SpeechProbabilities {
  final double isSpeech;
  final double notSpeech;

  const SpeechProbabilities({
    required this.isSpeech,
    required this.notSpeech,
  });

  @override
  String toString() {
    return 'SpeechProbabilities(isSpeech: $isSpeech, notSpeech: $notSpeech)';
  }
}