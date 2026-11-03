import 'dart:io';

import 'package:edge_tts/edge_tts.dart';
import 'package:path_provider/path_provider.dart';

/// Microsoft Edge neural TTS — FREE, no API key, needs internet.
/// Has good Myanmar voices (Thiha = male, Nilar = female).
class EdgeTtsService {
  static const voices = [
    EdgeVoice('my-MM-ThihaNeural', 'Thiha (ကျား)'),
    EdgeVoice('my-MM-NilarNeural', 'Nilar (မ)'),
  ];

  /// Synthesizes [text] to an MP3 file. Returns the file path.
  Future<String> synthesize({
    required String text,
    required String voiceId,
    String rate = '+0%',
    String pitch = '+0Hz',
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final out = File(
        '${dir.path}/edge_tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
    final comm = Communicate(
      text: text,
      voice: voiceId,
      rate: rate,
      pitch: pitch,
    );
    await comm.save(out.path);
    if (!await out.exists()) {
      throw Exception('Edge TTS failed — internet လိုပါတယ်');
    }
    return out.path;
  }

  /// Short sample for voice preview.
  Future<String> sample(String voiceId) => synthesize(
        text: 'မင်္ဂလာပါ။ ဒါက အသံနမူနာပါ။',
        voiceId: voiceId,
      );

  /// Probes the media duration of an audio file via FFprobe-free method:
  /// reads MP3 header is unreliable, so caller should use FFmpegService.
  static String formatRate(double percent) {
    final v = percent.round();
    return v >= 0 ? '+$v%' : '$v%';
  }

  static String formatPitch(double hz) {
    final v = hz.round();
    return v >= 0 ? '+${v}Hz' : '${v}Hz';
  }
}

class EdgeVoice {
  final String id;
  final String label;
  const EdgeVoice(this.id, this.label);
}
