import 'dart:convert';

/// A single free API key with health tracking for auto-rotation.
class ApiKey {
  final String id;
  final String label;
  final String key;
  final String provider; // 'gemini'
  int failCount;
  int successCount;
  DateTime? cooldownUntil;
  String? lastError;

  ApiKey({
    required this.id,
    required this.label,
    required this.key,
    this.provider = 'gemini',
    this.failCount = 0,
    this.successCount = 0,
    this.cooldownUntil,
    this.lastError,
  });

  bool get isCoolingDown =>
      cooldownUntil != null && DateTime.now().isBefore(cooldownUntil!);

  bool get isUsable => !isCoolingDown;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'key': key,
        'provider': provider,
        'failCount': failCount,
        'successCount': successCount,
        'cooldownUntil': cooldownUntil?.toIso8601String(),
        'lastError': lastError,
      };

  factory ApiKey.fromJson(Map<String, dynamic> j) => ApiKey(
        id: j['id'] as String,
        label: j['label'] as String,
        key: j['key'] as String,
        provider: (j['provider'] as String?) ?? 'gemini',
        failCount: (j['failCount'] as num?)?.toInt() ?? 0,
        successCount: (j['successCount'] as num?)?.toInt() ?? 0,
        cooldownUntil: j['cooldownUntil'] != null
            ? DateTime.tryParse(j['cooldownUntil'] as String)
            : null,
        lastError: j['lastError'] as String?,
      );

  /// Masked for display, e.g. "AIza••••1234".
  String get masked {
    if (key.length <= 8) return '••••';
    return '${key.substring(0, 4)}••••${key.substring(key.length - 4)}';
  }

  static String newId() =>
      'key_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecond % 9000))}';

  static String encodeList(List<ApiKey> keys) =>
      jsonEncode(keys.map((k) => k.toJson()).toList());

  static List<ApiKey> decodeList(String raw) {
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => ApiKey.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }
}
