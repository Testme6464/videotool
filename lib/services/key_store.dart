import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_key.dart';

/// Stores many free API keys in ENCRYPTED secure storage and auto-rotates
/// to the next usable one when a key hits its limit (429 / quota / 403).
/// Keys never leave the phone — requests go directly to Google over HTTPS.
///
/// SINGLETON: all screens share one instance, so a key added in the Keys
/// tab is immediately visible to Dubbing/Recap/etc.
class KeyStore {
  KeyStore._();
  static final KeyStore _instance = KeyStore._();
  factory KeyStore() => _instance;

  static const _secureKey = 'videotool_api_keys_v1';
  static const _secureIndex = 'videotool_api_key_index_v1';
  // Legacy (unencrypted) location — migrated once, then cleared.
  static const _legacyPrefsKey = 'videotool_api_keys_v1';
  static const _legacyIndexKey = 'videotool_api_key_index_v1';

  static const _storage = FlutterSecureStorage();

  List<ApiKey> _keys = [];
  int _cursor = 0;
  bool _loaded = false;

  List<ApiKey> get keys => List.unmodifiable(_keys);
  List<ApiKey> get usableKeys => _keys.where((k) => k.isUsable).toList();
  bool get hasKeys => _keys.isNotEmpty;
  bool get hasUsableKey => usableKeys.isNotEmpty;

  Future<void> load() async {
    if (_loaded) return;
    await _readFromStorage();
  }

  /// Force re-read from storage (picks up keys added elsewhere).
  Future<void> refresh() async {
    _loaded = false;
    await _readFromStorage();
  }

  Future<void> _readFromStorage() async {
    var raw = await _storage.read(key: _secureKey);
    if (raw == null) {
      // One-time migration from legacy SharedPreferences.
      try {
        final prefs = await SharedPreferences.getInstance();
        final legacy = prefs.getString(_legacyPrefsKey);
        if (legacy != null && legacy.isNotEmpty) {
          raw = legacy;
          await _storage.write(key: _secureKey, value: legacy);
          final idx = prefs.getInt(_legacyIndexKey) ?? 0;
          await _storage.write(
              key: _secureIndex, value: idx.toString());
          await prefs.remove(_legacyPrefsKey);
          await prefs.remove(_legacyIndexKey);
        }
      } catch (_) {}
    }
    _keys = ApiKey.decodeList(raw ?? '[]');
    _cursor =
        int.tryParse(await _storage.read(key: _secureIndex) ?? '0') ?? 0;
    _loaded = true;
  }

  Future<void> _save() async {
    await _storage.write(
        key: _secureKey, value: ApiKey.encodeList(_keys));
    await _storage.write(key: _secureIndex, value: _cursor.toString());
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

  /// Round-robin pick of the next usable key — requests rotate key by key,
  /// skipping quota-hit / invalid keys (they sit in cooldown).
  /// Tip: keys from DIFFERENT Google projects get separate quotas.
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
