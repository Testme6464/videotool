import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Google Translate TTS — FREE, no key, very reliable.
/// Robotic voice but works everywhere. Myanmar (my) supported.
/// Used as the last-resort fallback when Edge/Gemini TTS fail.
class GoogleTtsService {
  /// Synthesize [text] to MP3. Returns file path.
  /// Splits long text into ~180 char chunks (API limit).
  Future<String> synthesize(String text) async {
    final dir = await getApplicationDocumentsDirectory();
    final out = File(
        '${dir.path}/gtts_${DateTime.now().millisecondsSinceEpoch}.mp3');
    final chunks = _split(text);
    final sink = out.openWrite();
    for (final c in chunks) {
      final bytes = await _fetchChunk(c);
      sink.add(bytes);
    }
    await sink.close();
    if (!await out.exists() ||
        await out.length() < 100) {
      throw Exception('Google TTS failed — internet လိုပါတယ်');
    }
    return out.path;
  }

  List<String> _split(String text) {
    final words = text.split(RegExp(r'\s+'));
    final chunks = <String>[];
    var cur = StringBuffer();
    for (final w in words) {
      if (cur.length + w.length + 1 > 180) {
        chunks.add(cur.toString().trim());
        cur = StringBuffer();
      }
      cur.write('$w ');
    }
    if (cur.toString().trim().isNotEmpty) {
      chunks.add(cur.toString().trim());
    }
    return chunks.isEmpty ? [text] : chunks;
  }

  Future<List<int>> _fetchChunk(String chunk) async {
    final uri = Uri.parse(
        'https://translate.google.com/translate_tts').replace(
      queryParameters: {
        'ie': 'UTF-8',
        'q': chunk,
        'tl': 'my',
        'client': 'tw-ob',
      },
    );
    final res = await http.get(uri, headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36'
    }).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200 || res.bodyBytes.length < 100) {
      throw Exception(
          'Google TTS HTTP ${res.statusCode}');
    }
    return res.bodyBytes;
  }

  Future<String> sample() =>
      synthesize('မင်္ဂလာပါ။ ဒါက အသံနမူနာပါ။');
}
