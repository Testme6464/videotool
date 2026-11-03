import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

/// On-device text-to-speech (free, offline). Used for Myanmar dubbing /
/// recap voiceover. Quality depends on the device's TTS engine.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    await _tts.setSharedInstance(true);
    // Try Myanmar first, fall back to device default.
    try {
      await _tts.setLanguage('my-MM');
    } catch (_) {}
    await _tts.setSpeechRate(0.95);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _ready = true;
  }

  Future<List<String>> availableLanguages() async {
    try {
      final langs = await _tts.getLanguages;
      if (langs is List) return langs.map((e) => e.toString()).toList();
    } catch (_) {}
    return [];
  }

  /// Synthesizes [text] to a wav file. Returns the file path, or null.
  /// Splits long text into chunks (engine limits) and concatenates via list.
  Future<String?> synthesizeToFile(String text, {String? language}) async {
    await init();
    if (language != null && language.isNotEmpty) {
      try {
        await _tts.setLanguage(language);
      } catch (_) {}
    }
    final dir = await getApplicationDocumentsDirectory();
    final out = File(
        '${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.wav');

    // Chunk by sentences to stay under engine limits (~4000 chars).
    final chunks = _chunkText(text, 3500);
    if (chunks.isEmpty) return null;

    if (chunks.length == 1) {
      final ok = await _tts.synthesizeToFile(chunks.first, out.path);
      if (ok == 1 && await out.exists()) return out.path;
      return null;
    }

    // Multiple chunks → synthesize each, then concat with ffmpeg later.
    // Here we just synthesize sequentially into separate files and return
    // a concat-list path; caller merges with FFmpeg.
    final parts = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      final p = File('${dir.path}/tts_part_$i.wav');
      final ok = await _tts.synthesizeToFile(chunks[i], p.path);
      if (ok == 1 && await p.exists()) parts.add(p.path);
    }
    if (parts.isEmpty) return null;
    if (parts.length == 1) {
      await parts.first;
      final single = File(parts.first);
      await single.copy(out.path);
      return out.path;
    }
    final listFile =
        File('${dir.path}/tts_list_${DateTime.now().millisecondsSinceEpoch}.txt');
    await listFile
        .writeAsString(parts.map((p) => "file '$p'").join('\n'));
    // Caller runs: ffmpeg -f concat -safe 0 -i list -c copy out.wav
    // We store the list path alongside for convenience.
    await File('${out.path}.list').writeAsString(listFile.path);
    // Return the first part; the UI merges via FfmpegService if .list exists.
    return out.path;
  }

  List<String> _chunkText(String text, int maxLen) {
    final chunks = <String>[];
    final sentences = text.split(RegExp(r'(?<=[။.!?])\s+'));
    final buf = StringBuffer();
    for (final s in sentences) {
      if (buf.length + s.length + 1 > maxLen && buf.isNotEmpty) {
        chunks.add(buf.toString().trim());
        buf.clear();
      }
      buf.write(s);
      buf.write(' ');
    }
    if (buf.toString().trim().isNotEmpty) chunks.add(buf.toString().trim());
    return chunks;
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
