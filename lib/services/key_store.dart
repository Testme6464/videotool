import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_key.dart';

/// Stores many free API keys and auto-rotates to the next usable one
/// when a key hits its limit (429 / quota / 403).
class KeyStore {
  static const _prefsKey = 'videotool_api_keys_v1';
  static const _indexKey = 'videotool_api_key_index_v1';

  List<ApiKey> _keys = [];
  int _cursor = 0;
  bool _loaded = false;

  List<ApiKey> get keys => List.unmodifiable(_keys);
  List<ApiKey> get usableKeys => _keys.where((k) => k.isUsable).toList();
  bool get hasKeys => _keys.isNotEmpty;
  bool get hasUsableKey => usableKeys.isNotEmpty;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _keys = ApiKey.decodeList(prefs.getString(_prefsKey) ?? '[]');
    _cursor = prefs.getInt(_indexKey) ?? 0;
    _loaded = true;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, ApiKey.encodeList(_keys));
    await prefs.setInt(_indexKey, _cursor);
  }

  Future<ApiKey> addKey(String key, {String? label}) async {
    await load();
    final k = ApiKey(
      id: ApiKey.newId(),
      label: label?.trim().isEmpty ?? true
          ? 'Key ${_keys.length + 1}'
          : label!.trim(),
      key: key.trim(),
    );
    _keys.add(k);
    await _save();
    return k;
  }

  Future<void> removeKey(String id) async {
    await load();
    _keys.removeWhere((k) => k.id == id);
    if (_cursor >= _keys.length) _cursor = 0;
    await _save();
  }

  Future<void> renameKey(String id, String label) async {
    await load();
    final i = _keys.indexWhere((k) => k.id == id);
    if (i >= 0) {
      final old = _keys[i];
      _keys[i] = ApiKey(
        id: old.id,
        label: label.trim().isEmpty ? old.label : label.trim(),
        key: old.key,
        provider: old.provider,
        failCount: old.failCount,
        successCount: old.successCount,
        cooldownUntil: old.cooldownUntil,
        lastError: old.lastError,
      );
      await _save();
    }
  }

  /// Round-robin pick of the next usable key.
  ApiKey? pickKey() {
    if (_keys.isEmpty) return null;
    for (var n = 0; n < _keys.length; n++) {
      final i = (_cursor + n) % _keys.length;
      if (_keys[i].isUsable) {
        _cursor = (i + 1) % _keys.length;
        return _keys[i];
      }
    }
    return null; // all cooling down
  }

  /// Called when a key succeeds — clears its error state.
  Future<void> reportSuccess(String id) async {
    await load();
    final i = _keys.indexWhere((k) => k.id == id);
    if (i >= 0) {
      _keys[i].successCount++;
      _keys[i].failCount = 0;
      _keys[i].lastError = null;
      _keys[i].cooldownUntil = null;
      await _save();
    }
  }

  /// Called when a key fails.
  /// [isQuota] = rate limit / quota exhausted → cooldown 65s then retryable.
  /// Permanent errors (bad key) → long cooldown (24h).
  Future<void> reportFailure(String id, String error,
      {bool isQuota = false}) async {
    await load();
    final i = _keys.indexWhere((k) => k.id == id);
    if (i >= 0) {
      _keys[i].failCount++;
      _keys[i].lastError = error;
      _keys[i].cooldownUntil = DateTime.now().add(
        isQuota ? const Duration(seconds: 65) : const Duration(hours: 24),
      );
      await _save();
    }
  }

  Future<void> resetCooldown(String id) async {
    await load();
    final i = _keys.indexWhere((k) => k.id == id);
    if (i >= 0) {
      _keys[i].cooldownUntil = null;
      _keys[i].failCount = 0;
      _keys[i].lastError = null;
      await _save();
    }
  }
}
