import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/api_key.dart';
import '../services/gemini_service.dart';
import '../services/key_store.dart';

/// API key management — add many free Gemini keys; auto-rotation
/// switches to the next key when one hits its limit.
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
        _testResult = '❌ Key မမှန်ပါ (သို့) network ပြဿနာ';
      });
    }
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
                Card(
                  color: Colors.teal.shade50,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Google AI Studio (aistudio.google.com) → Get API Key — '
                      'အခမဲ့, card မလို။ Key အများကြီးထည့်ထားလို့ရတယ်။ '
                      'တစ်ခု limit ထိရင် နောက် key ကို auto ချိန်းပေးတယ်။',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Key အသစ်ထည့်ရန်',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _keyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Gemini API Key',
                    border: OutlineInputBorder(),
                    hintText: 'AIza…',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'နာမည် (optional, ဥပမာ: Key-A)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _testing ? null : _add,
                  icon: const Icon(Icons.add),
                  label: const Text('စစ်ပြီး ထည့်မယ်'),
                ),
                if (_testing) const LinearProgressIndicator(),
                if (_testResult != null) ...[
                  const SizedBox(height: 8),
                  Text(_testResult!),
                ],
                const SizedBox(height: 20),
                Text(
                    'ထည့်ထားတဲ့ keys (${_store.keys.length})',
                    style:
                        const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (_store.keys.isEmpty)
                  const Text('Key မရှိသေးပါ',
                      style: TextStyle(color: Colors.grey)),
                for (final k in _store.keys)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.key,
                        color: k.isUsable ? Colors.green : Colors.orange,
                      ),
                      title: Text(k.label),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(k.masked,
                              style:
                                  const TextStyle(fontFamily: 'monospace')),
                          Text(
                            '${k.isUsable ? "✅ သုံးလို့ရ" : _cooldownText(k)}'
                            ' · အောင် ${k.successCount} · လွဲ ${k.failCount}'
                            '${k.lastError != null ? "\n${k.lastError}" : ""}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                                  title:
                                      Text('"${k.label}" ဖျက်မလား?'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('မဖျက်ဘူး')),
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('ဖျက်မယ်')),
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
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Key copy ကူးပြီးပြီ')));
                        }
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Long-press = key copy ကူးမယ်။ Key တွေက ဒီဖုန်းထဲမှာပဲ သိမ်းထားတယ်။',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
    );
  }
}
