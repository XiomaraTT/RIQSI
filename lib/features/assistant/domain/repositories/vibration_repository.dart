abstract class VibrationRepository {
  Future<void> vibrate(int durationMs);
  void triggerProximityFeedback(String distancia);
  void stop();
}