import 'package:audioplayers/audioplayers.dart';

/// Plays the short confirmation cue once when recommendations become visible.
class RecommendationSound {
  RecommendationSound._();

  static final AudioPlayer _player = AudioPlayer();

  static Future<void> play() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('audio/reco_found.mp3'), volume: 0.8);
    } catch (_) {
      // Audio feedback must never prevent recommendation results from showing.
    }
  }
}
