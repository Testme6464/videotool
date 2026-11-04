import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'gemini_service.dart';
import 'key_store.dart';

/// Gemini native TTS — high quality, uses the user's Gemini API key.
/// Model: gemini-3.8-flash-tts (verified 2026-11-04).
/// Returns 24kHz 16-bit mono PCM → converted to MP3 via FFmpeg-free WAV.
class GeminiTtsService {
  static const _model = 'gemini-3.8-flash-tts';
  static const _base = 'https://generativelanguage.googleapis.com/v1beta';

  final KeyStore keys;
  GeminiTtsService(this.keys);

  static const voices = [
    GeminiVoice('Charon', 'Charon (ကျား)'),
    GeminiVoice('Kore', 'Kore (မ)'),
    GeminiVoice('Fenrir', 'Fenrir (ကျား ၂)'),
    GeminiVoice('Aoede', 'Aoede (မ ၂)'),
  ];

  /// Synthesize [text] to MP3. Returns file path. Rotates keys on quota.
  Future<String> synthesize({
    required String text,
    required String voiceName,
  }) async {
    await keys.load();
    final tried = <String>[];
    final attempted = keys.keys.length;

    for (var attempt = 0; attempt < attempted; attempt++) {
      final k = keys.pickKey();
      if (k == null) break;
      tried.add(k.label);
      try {
        final path = await _callOnce(k.key, text, voiceName);
        await keys.reportSuccess(k.id);
        return path;
      } on _QuotaHit catch (e) {
        await keys.reportFailure(k.id, e.message, isQuota: true);
        continue;
      } on _LocationBlocked {
        rethrow;
      } on GeminiException {
        // Other errors (bad key etc.) — try next key without long penalty.
        await keys.reportFailure(k.id, 'TTS failed', isQuota: false);
        continue;
      }
    }
    if (!keys.hasKeys) {
      throw GeminiException(
          'Gemini key မရှိသေးပါ — Keys tab မှာ ထည့်ပါ။');
    }
    throw GeminiException(
        'Gemini TTS မရပါ (${tried.join(', ')}) — quota ပြည့်နေနိုင်တယ်။');
  }

  Future<String> _callOnce(
      String apiKey, String text, String voiceName) async {
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': 'Read aloud in Burmese (Myanmar language): $text'}
          ]
        }
      ],
      'generationConfig': {
        'responseModalities': ['AUDIO'],
        'speechConfig': {
          'voiceConfig': {
            'prebuiltVoiceConfig': {'voiceName': voiceName}
          }
        },
      },
    });
    final uri =
        Uri.parse('$_base/models/$_model:generateContent?key=$apiKey');
    http.Response res;
    try {
      res = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: body)
          .timeout(const Duration(minutes: 3));
    } catch (e) {
      throw _QuotaHit('Network error: $e');
    }
    if (res.statusCode != 200) {
      final msg = _errMsg(res);
      final lower = msg.toLowerCase();
      if (lower.contains('user location is not supported')) {
        throw _LocationBlocked(
            'Gemini API က ဒီနိုင်ငံမှာ မဖွင့်သေးပါ — VPN ဖွင့်ပြီး ပြန်လုပ်ပါ။');
      }
      if (res.statusCode == 429) throw _QuotaHit('Rate limit: $msg');
      throw GeminiException('Gemini TTS HTTP ${res.statusCode}: $msg');
    }
    try {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final parts = ((j['candidates'] as List).first
              as Map<String, dynamic>)['content']
          ['parts'] as List;
      for (final p in parts) {
        final inline = (p as Map<String, dynamic>)['inlineData'];
        if (inline != null) {
          final pcm = base64Decode(inline['data'] as String);
          return await _pcmToMp3(pcm);
        }
      }
      throw GeminiException('Gemini TTS: audio ပြန်မလာပါ');
    } catch (e) {
      if (e is GeminiException) rethrow;
      throw GeminiException('Gemini TTS parse error: $e');
    }
  }

  /// Wrap 24kHz 16-bit mono PCM in a WAV header → save as .wav
  /// (FFmpeg reads WAV fine for the dub render).
  Future<String> _pcmToMp3(Uint8List pcm) async {
    final dir = await getApplicationDocumentsDirectory();
    final out = File(
        '${dir.path}/gemini_tts_${DateTime.now().millisecondsSinceEpoch}.wav');
    final wav = _wavHeader(pcm.length, 24000) + pcm;
    await out.writeAsBytes(wav);
    return out.path;
  }

  Uint8List _wavHeader(int dataLen, int sampleRate) {
    final h = ByteData(44);
    void str(int off, String s) {
      for (var i = 0; i < s.length; i++) {
        h.setUint8(off + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    h.setUint32(4, 36 + dataLen, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    h.setUint32(16, 16, Endian.little);
    h.setUint16(20, 1, Endian.little); // PCM
    h.setUint16(22, 1, Endian.little); // mono
    h.setUint32(24, sampleRate, Endian.little);
    h.setUint32(28, sampleRate * 2, Endian.little);
    h.setUint16(32, 2, Endian.little);
    h.setUint16(34, 16, Endian.little);
    str(36, 'data');
    h.setUint32(40, dataLen, Endian.little);
    return h.buffer.asUint8List();
  }

  String _errMsg(http.Response res) {
    try {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return (j['error']?['message'] as String?) ?? res.body;
    } catch (_) {
      return res.body.length > 200
          ? res.body.substring(0, 200)
          : res.body;
    }
  }

  Future<String> sample(String voiceName) => synthesize(
        text: 'မင်္ဂလာပါ။ ဒါက အသံနမူနာပါ။',
        voiceName: voiceName,
      );
}

class GeminiVoice {
  final String id;
  final String label;
  const GeminiVoice(this.id, this.label);
}

class _QuotaHit extends GeminiException {
  _QuotaHit(super.message);
}

class _LocationBlocked extends GeminiException {
  _LocationBlocked(super.message);
}
