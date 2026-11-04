import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/ffmpeg_service.dart';
import '../services/gemini_service.dart';
import '../services/key_store.dart';
import '../widgets/job_runner.dart';

/// Long to Short — Gemini AI finds the most engaging moments,
/// cuts them as 9:16 shorts.
class LongToShortScreen extends StatefulWidget {
  const LongToShortScreen({super.key});

  @override
  State<LongToShortScreen> createState() => _LongToShortScreenState();
}

class _Clip {
  final double start;
  final double end;
  final String title;
  _Clip(this.start, this.end, this.title);
}

class _LongToShortScreenState extends State<LongToShortScreen> {
  String? _videoPath;
  MediaInfo? _info;
  bool _loading = false;

  String _lang = 'Auto';
  String _category = 'အထွေထွေ';
  int _clipCount = 3;
  String _durRange = '70-150s'; // or '30-75s'

  final KeyStore _keys = KeyStore();
  late final GeminiService _gemini;

  static const _langs = [
    'Auto',
    'English',
    'Chinese',
    'Korean',
    'Japanese',
    'Thai',
    'Hindi',
    'Indonesian',
    'Spanish',
    'Myanmar',
  ];

  static const _cats = [
    'အထွေထွေ',
    'Motivation',
    'Psychology',
    'Horror',
    'Crime',
    'Knowledge',
    'Comedy',
    'Business',
    'Celebrity',
    'Tech/AI',
    'Sports',
  ];

  @override
  void initState() {
    super.initState();
    _gemini = GeminiService(_keys);
    _keys.load();
  }

  Future<void> _pick() async {
    final f =
        await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (f == null) return;
    setState(() {
      _loading = true;
      _videoPath = f.path;
    });
    final info = await FfmpegService.getMediaInfo(f.path);
    setState(() {
      _info = info;
      _loading = false;
    });
  }

  /// Ask Gemini to find the best moments from the audio track.
  Future<List<_Clip>> _findClips(
      String audioPath, double totalSec, void Function(String) onLog) async {
    final bytes = await File(audioPath).readAsBytes();
    // Cap ~15MB.
    if (bytes.length > 15 * 1024 * 1024) {
      throw GeminiException(
          'အသံဖိုင် ကြီးလွန်းပါတယ် (15MB ကျော်) — video တိုတာ စမ်းပါ။');
    }
    final targetLen =
        _durRange == '70-150s' ? 'about 90 seconds' : 'about 45 seconds';
    final prompt = '''
You are a viral shorts editor. Listen to this audio (spoken language: $_lang, content category: $_category).

Total audio duration: ${totalSec.toStringAsFixed(0)} seconds.

Find the $_clipCount MOST engaging, self-contained moments that would work as standalone vertical shorts. Each moment should be $targetLen long, with a hook in the first 3 seconds.

Return ONLY a JSON array, no other text:
[{"start": 12.5, "end": 102.5, "title": "short title"}, ...]

Rules:
- start/end are seconds (decimals ok), end - start matches the target length.
- end must be <= ${totalSec.toStringAsFixed(0)}.
- Moments must not overlap each other.
- Titles in the same language as the audio.
''';
    onLog('Gemini က အကောင်းဆုံး အပိုင်းတွေ ရှာနေတယ်…');
    final raw = await _gemini.generate(prompt,
        media: [
          GeminiMedia(mimeType: 'audio/mp4', base64: base64Encode(bytes))
        ],
        temperature: 0.4,
        maxOutputTokens: 2048);
    // Strip code fences if present.
    var clean = raw.trim();
    if (clean.startsWith('```')) {
      clean = clean.replaceAll(RegExp(r'^```\w*\n?'), '');
      clean = clean.replaceAll(RegExp(r'\n?```$'), '');
    }
    final arr = jsonDecode(clean) as List;
    final clips = <_Clip>[];
    for (final e in arr) {
      final m = e as Map<String, dynamic>;
      final s = (m['start'] as num).toDouble();
      final en = (m['end'] as num).toDouble();
      if (en > s && s >= 0 && en <= totalSec + 1) {
        clips.add(_Clip(s, en.clamp(0, totalSec),
            (m['title'] as String?) ?? 'clip'));
      }
      if (clips.length >= _clipCount) break;
    }
    if (clips.isEmpty) throw GeminiException('Gemini က clip ရှာမတွေ့ပါ။');
    return clips;
  }

  List<_Clip> _evenClips(double totalSec) {
    final len = _durRange == '70-150s' ? 90.0 : 45.0;
    return List.generate(_clipCount, (i) {
      final maxStart =
          (totalSec - len).clamp(0.0, totalSec).toDouble();
      final s = _clipCount == 1
          ? 0.0
          : (maxStart * i / (_clipCount - 1)).clamp(0.0, maxStart);
      return _Clip(s, (s + len).clamp(0, totalSec), 'clip ${i + 1}');
    });
  }

  void _start() {
    final inPath = _videoPath;
    final info = _info;
    if (inPath == null || info == null) return;
    final totalSec = info.durationMs / 1000;

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JobRunner(
        title: 'Long to Short',
        run: (onProgress, onLog) async {
          final outDir = await FfmpegService.outDir();
          final ts = DateTime.now().millisecondsSinceEpoch;

          // 1. Extract audio for Gemini analysis.
          final audioPath = '${outDir.path}/l2s_${ts}_audio.m4a';
          onLog('အသံထုတ်နေတယ်…');
          var rc = await FfmpegService.runJob(
            command: '-y -i ${FfmpegService.q(inPath)} -vn '
                '-c:a aac -b:a 64k -ac 1 -ar 16000 '
                '${FfmpegService.q(audioPath)}',
            totalDurationMs: info.durationMs,
            onProgress: (p) => onProgress(p * 0.15),
            onLog: onLog,
          );
          if (rc != 0) throw Exception('အသံထုတ်တာ မအောင်မြင်ပါ ($rc)');

          // 2. Find clips (AI, fallback to even spacing).
          List<_Clip> clips;
          try {
            clips = await _findClips(audioPath, totalSec, onLog);
            onLog('Gemini က clip ${clips.length} ခု ရွေးပေးလိုက်တယ် ✅');
          } catch (e) {
            onLog('AI ရှာတာ မရလို့ အညီအမျှ ဖြတ်ပါမယ်: $e');
            clips = _evenClips(totalSec);
          }
          try {
            await File(audioPath).delete();
          } catch (_) {}

          // 3. Cut each clip as 9:16.
          final outs = <String>[];
          for (var i = 0; i < clips.length; i++) {
            final c = clips[i];
            final len = c.end - c.start;
            final out = '${outDir.path}/short_${ts}_${i + 1}.mp4';
            onLog('Clip ${i + 1}/${clips.length}: ${c.title}');
            const vf =
                'crop=ih*9/16:ih,scale=720:1280,format=yuv420p';
            final cmd =
                '-y -ss ${c.start.toStringAsFixed(1)} -t ${len.toStringAsFixed(1)} '
                '-i ${FfmpegService.q(inPath)} -vf "$vf" '
                '-c:v libx264 -crf 23 -preset veryfast -c:a aac -b:a 128k '
                '${FfmpegService.q(out)}';
            rc = await FfmpegService.runJob(
              command: cmd,
              totalDurationMs: len * 1000,
              onProgress: (p) =>
                  onProgress(0.15 + 0.85 * (i + p) / clips.length),
              onLog: onLog,
            );
            if (rc != 0) {
              throw Exception('Clip ${i + 1} မအောင်မြင်ပါ ($rc)');
            }
            outs.add(out);
          }
          return outs;
        },
      ),
    ));
  }

  Widget _chip(String label, bool sel, VoidCallback onTap) =>
      ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) => onTap(),
        showCheckmark: true,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Long to Short')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🎬 ၁။ ဗီဒီယို နှင့် clip ရွေးခြင်း',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                        Icons.video_library,
                        color: Colors.teal),
                    title: Text(_videoPath == null
                        ? 'ဗီဒီယို ရွေးပါ'
                        : _videoPath!
                            .split('/')
                            .last,
                        overflow:
                            TextOverflow.ellipsis),
                    subtitle: Text(_info == null
                        ? 'Gallery / File မှ ရွေးရန် နှိပ်ပါ'
                        : '${(_info!.durationMs / 60000).toStringAsFixed(1)} မိနစ်'),
                    trailing:
                        const Icon(Icons.chevron_right),
                    onTap: _pick,
                  ),
                  if (_loading)
                    const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _lang,
                    decoration: const InputDecoration(
                      labelText:
                          'မူရင်းဗီဒီယို ဘာသာစကား',
                      border: OutlineInputBorder(),
                    ),
                    items: _langs
                        .map((l) => DropdownMenuItem(
                            value: l,
                            child: Text(l)))
                        .toList(),
                    onChanged: (v) => setState(
                        () => _lang = v ?? 'Auto'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(
                      labelText:
                          'အကြောင်းအရာ အမျိုးအစား',
                      border: OutlineInputBorder(),
                    ),
                    items: _cats
                        .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() =>
                        _category =
                            v ?? 'အထွေထွေ'),
                  ),
                  const SizedBox(height: 12),
                  const Text('Clip အရေအတွက်'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [2, 3, 5]
                        .map((n) => _chip('$n',
                            _clipCount == n, () => setState(
                                () => _clipCount = n)))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  const Text('ကြာချိန်'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      _chip('70-150s',
                          _durRange == '70-150s',
                          () => setState(() =>
                              _durRange = '70-150s')),
                      _chip('30-75s',
                          _durRange == '30-75s',
                          () => setState(() =>
                              _durRange = '30-75s')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed:
                (_videoPath != null && !_loading)
                    ? _start
                    : null,
            icon: const Icon(Icons.search),
            label: const Text('🔍 Clip ရှာမယ်',
                style: TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
                minimumSize:
                    const Size.fromHeight(52)),
          ),
          const SizedBox(height: 8),
          const Text(
            'ဗီဒီယိုရှည်ထဲက သီးခြားကြည့်လို့ရတဲ့ အကောင်းဆုံး အပိုင်းတွေကို Gemini က ရွေးပြီး 9:16 shorts လုပ်ပေးပါမယ်။ (Gemini key လိုတယ် — Keys tab မှာ ထည့်ပါ)',
            style:
                TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
