import 'dart:convert';

import 'package:http/http.dart' as http;

import 'key_store.dart';

/// Gemini API client (free tier) with automatic multi-key rotation.
/// When a key hits its limit (429/403/quota), the next usable key is tried.
class GeminiService {
  static const _base = 'https://generativelanguage.googleapis.com/v1beta';
  // Free-tier friendly default model.
  static const defaultModel = 'gemini-2.0-flash';

  final KeyStore keys;
  String model;

  GeminiService(this.keys, {this.model = defaultModel});

  /// Generate text from a prompt, optionally with base64 media attachments.
  /// Returns the text, or throws [GeminiException] if all keys are exhausted.
  Future<String> generate(
    String prompt, {
    List<GeminiMedia> media = const [],
    double temperature = 0.7,
    int maxOutputTokens = 8192,
  }) async {
    await keys.load();
    final tried = <String>[];
    final attempted = keys.keys.length;

    for (var attempt = 0; attempt < attempted; attempt++) {
      final k = keys.pickKey();
      if (k == null) break;
      tried.add(k.label);
      try {
        final text = await _callOnce(k.key, prompt,
            media: media, temperature: temperature, maxTokens: maxOutputTokens);
        await keys.reportSuccess(k.id);
        return text;
      } on _QuotaHit catch (e) {
        await keys.reportFailure(k.id, e.message, isQuota: true);
        continue; // try next key
      } on _BadKey catch (e) {
        await keys.reportFailure(k.id, e.message, isQuota: false);
        continue;
      }
    }

    if (!keys.hasKeys) {
      throw GeminiException(
          'API key မရှိသေးပါ။ Keys tab မှာ Google AI Studio (aistudio.google.com) က အခမဲ့ key ထည့်ပါ။');
    }
    throw GeminiException(
        'Key အားလုံး limit ထိသွားပါပြီ (${tried.join(', ')})။ ခဏစောင့်ပြီး ပြန်လုပ်ပါ၊ ဒါမှမဟုတ် key အသစ်ထပ်ထည့်ပါ။');
  }

  /// Quick key validity check — tiny prompt, no rotation.
  Future<bool> testKey(String rawKey) async {
    try {
      await _callOnce(rawKey, 'Reply with exactly: ok',
          media: const [], temperature: 0, maxTokens: 8);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> _callOnce(
    String apiKey,
    String prompt, {
    required List<GeminiMedia> media,
    required double temperature,
    required int maxTokens,
  }) async {
    final parts = <Map<String, dynamic>>[
      {'text': prompt},
      for (final m in media)
        {
          'inline_data': {'mime_type': m.mimeType, 'data': m.base64}
        },
    ];
    final body = jsonEncode({
      'contents': [
        {
          'parts': parts,
        }
      ],
      'generationConfig': {
        'temperature': temperature,
        'maxOutputTokens': maxTokens,
      },
    });

    final uri = Uri.parse('$_base/models/$model:generateContent?key=$apiKey');
    http.Response res;
    try {
      res = await http
          .post(uri,
              headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(minutes: 3));
    } catch (e) {
      throw _QuotaHit('Network error: $e');
    }

    if (res.statusCode == 200) {
      try {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final cands = (j['candidates'] as List?) ?? [];
        if (cands.isEmpty) throw _QuotaHit('Empty response from Gemini');
        final content =
            (cands.first as Map<String, dynamic>)['content'] as Map?;
        final ps = (content?['parts'] as List?) ?? [];
        final text = ps
            .map((p) => (p as Map<String, dynamic>)['text'] as String? ?? '')
            .join();
        if (text.trim().isEmpty) throw _QuotaHit('Empty text from Gemini');
        return text;
      } catch (e) {
        if (e is _QuotaHit) rethrow;
        throw _QuotaHit('Bad response: $e');
      }
    }

    final msg = _errorMessage(res);
    if (res.statusCode == 429) throw _QuotaHit('Rate limit (429): $msg');
    if (res.statusCode == 403 || res.statusCode == 400) {
      final lower = msg.toLowerCase();
      if (lower.contains('quota') ||
          lower.contains('rate') ||
          lower.contains('limit') ||
          lower.contains('exhausted')) {
        throw _QuotaHit('Quota: $msg');
      }
      throw _BadKey('Key error (${res.statusCode}): $msg');
    }
    if (res.statusCode == 404) throw _BadKey('Model not found: $model');
    throw _QuotaHit('HTTP ${res.statusCode}: $msg');
  }

  String _errorMessage(http.Response res) {
    try {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final err = j['error'] as Map?;
      return (err?['message'] as String?) ?? res.body.substring(0, 200);
    } catch (_) {
      return res.body.length > 200 ? res.body.substring(0, 200) : res.body;
    }
  }
}

class GeminiMedia {
  final String mimeType;
  final String base64;
  GeminiMedia({required this.mimeType, required this.base64});
}

class GeminiException implements Exception {
  final String message;
  GeminiException(this.message);
  @override
  String toString() => message;
}

class _QuotaHit extends GeminiException {
  _QuotaHit(super.message);
}

class _BadKey extends GeminiException {
  _BadKey(super.message);
}
