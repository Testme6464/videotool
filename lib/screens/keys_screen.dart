import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/api_key.dart';
import '../services/gemini_service.dart';
import '../services/key_store.dart';

/// API Keys — free Gemini keys with auto-rotation.
/// Keys live in ENCRYPTED storage on this phone only; requests go
/// directly to Google over HTTPS (never through our server).
class KeysScreen extends StatefulWidget {
  const KeysScreen({super.key});

  @override
  State<KeysScreen> createState() => _KeysScreenState();
}

class _KeysScreenState extends State<KeysScreen> {
  final _store = KeyStore();
  bool _loaded = false;
  final _keyCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  bool _testing = false;
  String? _testResult;
  final _testingKeyId = <String>{};
  var _obscure = true;

  @override
  void initState() {
    super.initState();
    _store.load().then((_) => setState(() => _loaded = true));
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _openAiStudio() async {
    final uri = Uri.parse('https://aistudio.google.com/app/apikey');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('ဖွင့်မရပါ — browser မှာ aistudio.google.com ကို ကိုယ်တိုင်သွားပါ')));
      }
    }
  }

  Future<void> _add() async {
    final raw = _keyCtrl.text.trim();
    if (raw.isEmpty) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final ok = await GeminiService(_store).testKey(raw);
    if (!mounted) return;
    if (ok) {
      await _store.addKey(raw, label: _labelCtrl.text);
      _keyCtrl.clear();
      _labelCtrl.clear();
      setState(() {
        _testing = false;
        _testResult = '✅ Key အလုပ်လုပ်တယ်, ထည့်ပြီးပြီ';
      });
    } else {
      setState(() {
        _testing = false;
        _testResult = '❌ Key မမှန်ပါ / VPN လိုနိုင်တယ် / network ပြဿနာ';
      });
    }
  }

  Future<void> _testExisting(ApiKey k) async {
    setState(() => _testingKeyId.add(k.id));
    final ok = await GeminiService(_store).testKey(k.key);
    if (!mounted) return;
    if (ok) {
      await _store.reportSuccess(k.id);
    } else {
      await _store.reportFailure(k.id, 'Test failed', isQuota: false);
    }
    setState(() => _testingKeyId.remove(k.id));
  }

  String _cooldownText(ApiKey k) {
    if (!k.isCoolingDown) return '';
    final left = k.cooldownUntil!.difference(DateTime.now());
    if (left.inHours >= 1) return '⏳ ${left.inHours}နာရီနား';
    if (left.inMinutes >= 1) return '⏳ ${left.inMinutes}မိနစ်နား';
    return '⏳ ${left.inSeconds}စက္ကန့်နား';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🔑 API Keys')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Security note (like Studio99).
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.shield_outlined,
                            color: Colors.teal),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'AI tool အားလုံးကို ကိုယ်ပိုင် API Key ဖြင့်သာ သုံးရပါမည်။ '
                            'Key ကို ဒီဖုန်းရဲ့ encrypted storage ထဲမှာပဲ သိမ်းပြီး '
                            'Google ကို ဖုန်းမှ တိုက်ရိုက် HTTPS ဖြင့် ပို့ပါတယ်။ '
                            'ကျွန်တော်တို့ server ကို လုံးဝမဖြတ်ပါ။',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Gemini section header.
                Row(
                  children: [
                    const Icon(Icons.key, color: Colors.amber),
                    const SizedBox(width: 8),
                    const Text('Gemini API Key',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _store.hasUsableKey
                            ? Colors.green.shade100
                            : Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _store.hasUsableKey
                            ? '${_store.usableKeys.length} ခု အသင့်'
                            : 'Not set',
                        style: TextStyle(
                          fontSize: 12,
                          color: _store.hasUsableKey
                              ? Colors.green.shade900
                              : Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'သုံးတဲ့နေရာ: Recap Translate, Original Recap (စာရေး)',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Key များများ ထည့်ထားရင် request တွေကို key တစ်ခုပြီးတစ်ခု အလှည့်ကျ ပို့ပြီး '
                  'quota ပြည့်/မမှန်တဲ့ key ကို ကျော်ကာ နောက် key နဲ့ ဆက်လုပ်ပါမယ် (auto rotate)။ '
                  'Google project မတူတဲ့ key တွေ ထည့်မှ quota ပိုရပါမယ်။',
                  style: TextStyle(color: Colors.teal, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _keyCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Gemini API Key',
                    hintText: 'AIza…',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () =>
                          setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'နာမည် (optional, ဥပမာ: Project-A)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _testing ? null : _add,
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _testing
                            ? null
                            : () async {
                                final raw = _keyCtrl.text.trim();
                                if (raw.isEmpty) return;
                                setState(() {
                                  _testing = true;
                                  _testResult = null;
                                });
                                final ok = await GeminiService(_store)
                                    .testKey(raw);
                                if (!mounted) return;
                                setState(() {
                                  _testing = false;
                                  _testResult = ok
                                      ? '✅ Key အလုပ်လုပ်တယ်'
                                      : '❌ မရပါ — key စစ် / VPN စမ်းပါ';
                                });
                              },
                        icon: const Icon(Icons.wifi_find),
                        label: const Text('Test'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _openAiStudio,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Key ယူရန်'),
                      ),
                    ),
                  ],
                ),
                if (_testing) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                ],
                if (_testResult != null) ...[
                  const SizedBox(height: 8),
                  Text(_testResult!),
                ],
                const SizedBox(height: 20),
                Text('ထည့်ထားတဲ့ keys (${_store.keys.length})',
                    style:
                        const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (_store.keys.isEmpty)
                  const Text('Key မရှိသေးပါ — အပေါ်က Add နဲ့ ထည့်ပါ',
                      style: TextStyle(color: Colors.grey)),
                for (final k in _store.keys)
                  Card(
                    child: ListTile(
                      leading: Icon(Icons.key,
                          color: k.isUsable
                              ? Colors.green
                              : Colors.orange),
                      title: Text(k.label),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(k.masked,
                              style: const TextStyle(
                                  fontFamily: 'monospace')),
                          Text(
                            '${k.isUsable ? "✅ သုံးလို့ရ" : _cooldownText(k)}'
                            ' · အောင် ${k.successCount} · လွဲ ${k.failCount}'
                            '${k.lastError != null ? "\n${k.lastError}" : ""}',
                            style:
                                const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_testingKeyId.contains(k.id))
                            const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                          else
                            IconButton(
                              icon:
                                  const Icon(Icons.wifi_find),
                              tooltip: 'စမ်းမယ်',
                              onPressed: () => _testExisting(k),
                            ),
                          if (!k.isUsable)
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              tooltip: 'နားချိန်ဖျက်',
                              onPressed: () async {
                                await _store.resetCooldown(k.id);
                                setState(() {});
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete,
                                color: Colors.red),
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: Text(
                                      '"${k.label}" ဖျက်မလား?'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(
                                                context, false),
                                        child: const Text(
                                            'မဖျက်ဘူး')),
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(
                                                context, true),
                                        child:
                                            const Text('ဖျက်မယ်')),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                await _store.removeKey(k.id);
                                setState(() {});
                              }
                            },
                          ),
                        ],
                      ),
                      onLongPress: () async {
                        await Clipboard.setData(
                            ClipboardData(text: k.key));
                        if (mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(
                                  content:
                                      Text('Key copy ကူးပြီးပြီ')));
                        }
                      },
                    ),
                  ),
                const SizedBox(height: 16),
                // VPN warning (like Studio99).
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.amber.shade200),
                  ),
                  child: const Text(
                    '⚠️ Gemini API မဖွင့်သေးတဲ့ နိုင်ငံ (ဥပမာ: မြန်မာ) က သုံးရင် '
                    '"User location is not supported" error ပေါ်နိုင်ပါတယ်။ '
                    'ထိုအခါ VPN ဖွင့်ပြီး သုံးပါ။',
                    style: TextStyle(
                        fontSize: 12, color: Colors.brown),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Long-press = key copy ကူးမယ်။ Key တွေက ဒီဖုန်းထဲမှာပဲ (encrypted) သိမ်းထားတယ်။',
                  style: TextStyle(
                      color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
    );
  }
}
