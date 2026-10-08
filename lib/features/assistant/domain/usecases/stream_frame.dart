import '../repositories/vision_repository.dart';

class StreamFrame {
  final VisionRepository visionRepository;

  StreamFrame(this.visionRepository);

  Future<bool> execute(List<int> frameBytes) {
    return visionRepository.sendFrame(frameBytes);
  }
}
