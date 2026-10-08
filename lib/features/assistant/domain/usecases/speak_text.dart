import '../repositories/tts_repository.dart';

class SpeakText {
  final TtsRepository ttsRepository;

  SpeakText(this.ttsRepository);

  Future<void> execute(
    String text,
    double rate,
    double volume, {
    SpeechPriority priority = SpeechPriority.normal,
  }) async {
    await ttsRepository.speak(text, rate, volume, priority: priority);
  }

  Future<void> stop() async {
    await ttsRepository.stop();
  }
}
