import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/ffmpeg_service.dart';
import '../services/gemini_service.dart';
import '../services/key_store.dart';
import '../services/tts_service.dart';
import '../widgets/job_runner.dart';

/// Recap tools powered by free Gemini keys (multi-key auto-rotation).
/// - Recap Translate: foreign audio → Myanmar SRT + dubbing
/// - Original Recap: video → Myanmar storytelling script → voiceover
class RecapScreen extends StatefulWidget {
  const RecapScreen({super.key});

  @override
  State<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends State<RecapScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String? _videoPath;
  MediaInfo? _info;
  bool _busy = false;
  String _status = '';
  final _textCtrl = TextEditingController();

  final _keys = KeyStore();
  final _tts = TtsService();
  late GeminiService _gemini;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _gemini = GeminiService(_keys);
    _keys.load();
  }

  @override
  void dispose() {
    _tab.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final f =
        await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (f == null) return;
    setState(() {
      _busy = true;
      _videoPath = f.path;
      _status = 'Video info ဖတ်နေတယ်…';
    });
    final info = await FfmpegService.getMediaInfo(f.path);
    setState(() {
      _info = info;
      _busy = false;
      _status = '';
    });
  }

  Future<String?> _extractAudio() async {
    final inPath = _videoPath;
    if (inPath == null) return null;
    final outDir = await FfmpegService.outDir();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final out = '${outDir.path}/recap_audio_$ts.m4a';
    final cmd =
        '-y -i ${FfmpegService.q(inPath)} -vn -c:a aac -b:a 64k -ac 1 '
        '${FfmpegService.q(out)}';
    final rc = await FfmpegService.runJob(
      command: cmd,
      totalDurationMs: _info?.durationMs ?? 0,
      onProgress: (_) {},
      onLog: (_) {},
    );
    if (rc != 0) return null;
    return out;
  }

  Future<void> _runTranslate() async {
    if (_videoPath == null) return;
    if (!_keys.hasUsableKey) {
      _needKey();
      return;
    }
    setState(() {
      _busy = true;
      _status = 'အသံထုတ်နေတယ်…';
    });
    final audio = await _extractAudio();
    if (audio == null) {
      setState(() {
        _busy = false;
        _status = 'အသံထုတ်မရပါ';
      });
      return;
    }
    final bytes = await File(audio).readAsBytes();
    if (bytes.length > 18 * 1024 * 1024) {
      setState(() {
        _busy = false;
        _status = 'Audio ကြီးလွန်းတယ် (18MB ထက်)။ Video အတိုနဲ့ စမ်းပါ။';
      });
      return;
    }
    setState(() => _status = 'Gemini က စာတန်းထုတ်နေတယ်… (key လှည့်သုံးနေတယ်)');
    try {
      final srt = await _gemini.generate(
        'Transcribe this audio fully and translate it into Myanmar (Burmese). '
        'Output ONLY valid SRT subtitles — numbered entries with timestamps '
        'like 00:00:01,000 --> 00:00:04,000 followed by Myanmar text. '
        'No explanations, no markdown, just SRT.',
        media: [
          GeminiMedia(mimeType: 'audio/mp4', base64: base64Encode(bytes))
        ],
        maxOutputTokens: 8192,
      );
      setState(() {
        _textCtrl.text = _cleanSrt(srt);
        _busy = false;
        _status = 'ရပြီ! ပြင်ချင်ရင် ပြင်ပြီး အောက်က ခလုတ်နှိပ်ပါ။';
      });
    } on GeminiException catch (e) {
      setState(() {
        _busy = false;
        _status = e.message;
      });
    }
  }

  Future<void> _runOriginalRecap() async {
    if (_videoPath == null) return;
    if (!_keys.hasUsableKey) {
      _needKey();
      return;
    }
    setState(() {
      _busy = true;
      _status = 'အသံထုတ်နေတယ်…';
    });
    final audio = await _extractAudio();
    if (audio == null) {
      setState(() {
        _busy = false;
        _status = 'အသံထုတ်မရပါ';
      });
      return;
    }
    final bytes = await File(audio).readAsBytes();
    if (bytes.length > 18 * 1024 * 1024) {
      setState(() {
        _busy = false;
        _status = 'Audio ကြီးလွန်းတယ် (18MB ထက်)။ Video အတိုနဲ့ စမ်းပါ။';
      });
      return;
    }
    setState(() => _status = 'Gemini က recap ရေးနေတယ်…');
    try {
      final script = await _gemini.generate(
        'Listen to this audio from a video and write an engaging Myanmar '
        '(Burmese) storytelling recap script, as if narrating the story to '
        'a friend. Use natural spoken Myanmar. About 150-250 words. '
        'Output ONLY the script, no explanations.',
        media: [
          GeminiMedia(mimeType: 'audio/mp4', base64: base64Encode(bytes))
        ],
        maxOutputTokens: 4096,
      );
      setState(() {
        _textCtrl.text = script.trim();
        _busy = false;
        _status = 'ရပြီ! ပြင်ချင်ရင် ပြင်ပြီး အသံထွက်မယ် နှိပ်ပါ။';
      });
    } on GeminiException catch (e) {
      setState(() {
        _busy = false;
        _status = e.message;
      });
    }
  }

  void _needKey() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Keys tab မှာ အခမဲ့ Gemini key အရင်ထည့်ပါ')));
  }

  String _cleanSrt(String s) {
    var t = s.trim();
    // Strip markdown fences if present.
    t = t.replaceAll(RegExp(r'```\w*'), '').trim();
    return t;
  }

  void _burnSubtitles() {
    final inPath = _videoPath;
    final srtText = _textCtrl.text.trim();
    if (inPath == null || srtText.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JobRunner(
        title: 'စာတန်းထိုးနေတယ်',
        run: (onProgress, onLog) async {
          final srtPath = await FfmpegService.writeSrt(srtText);
          final outDir = await FfmpegService.outDir();
          final font = await FfmpegService.fontPath();
          final ts = DateTime.now().millisecondsSinceEpoch;
          final out = '${outDir.path}/recap_sub_$ts.mp4';
          String esc(String s) => s
              .replaceAll('\\', '\\\\')
              .replaceAll(':', '\\:')
              .replaceAll("'", "\\'");
          final fontsDir = font.replaceAll(RegExp(r'/[^/]+$'), '');
          final vf =
              "subtitles=${esc(srtPath)}:fontsdir=${esc(fontsDir)}:"
              "force_style='FontName=Noto Sans Myanmar,FontSize=22,"
              "PrimaryColour=&H00FFFFFF,OutlineColour=&H80000000,"
              "BorderStyle=1,Outline=1,MarginV=28,Alignment=2'";
          final rc = await FfmpegService.runJob(
            command:
                '-y -i ${FfmpegService.q(inPath)} -vf "$vf" -c:v libx264 '
                '-crf 23 -preset veryfast -c:a copy ${FfmpegService.q(out)}',
            totalDurationMs: _info?.durationMs ?? 0,
            onProgress: onProgress,
            onLog: onLog,
          );
          if (rc != 0) throw Exception('FFmpeg failed (code $rc)');
          return [out];
        },
      ),
    ));
  }

  void _makeVoiceover() {
    final script = _textCtrl.text.trim();
    if (script.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JobRunner(
        title: 'အသံထွက်နေတယ်',
        run: (onProgress, onLog) async {
          onLog('TTS: စက်အသံဖြင့် ဖတ်နေတယ်…');
          final wav = await _tts.synthesizeToFile(script, language: 'my-MM');
          if (wav == null) throw Exception('TTS မရပါ');
          onProgress(1.0);
          return [wav];
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isTranslate = _tab.index == 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('📝 Recap Tools'),
        bottom: TabBar(
          controller: _tab,
          onTap: (_) => setState(() {}),
          tabs: const [
            Tab(text: 'Recap Translate'),
            Tab(text: 'Original Recap'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ElevatedButton.icon(
            onPressed: _busy ? null : _pickVideo,
            icon: const Icon(Icons.video_library),
            label: const Text('Video ရွေးပါ'),
          ),
          if (_videoPath != null)
            Card(
                child: ListTile(
                    dense: true,
                    title: Text(_videoPath!.split('/').last,
                        overflow: TextOverflow.ellipsis))),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: (_busy || _videoPath == null)
                ? null
                : (isTranslate ? _runTranslate : _runOriginalRecap),
            icon: const Icon(Icons.auto_awesome),
            label: Text(isTranslate
                ? 'မြန်မာစာတန်း ထုတ်မယ် (Gemini)'
                : 'Recap script ရေးမယ် (Gemini)'),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(_status),
          ] else if (_status.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_status,
                style: const TextStyle(color: Colors.teal)),
          ],
          const SizedBox(height: 16),
          const Text('ရလဒ် (ပြင်လို့ရတယ်):',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _textCtrl,
            maxLines: 10,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Gemini ရလဒ် ဒီမှာ ပေါ်မယ်…',
            ),
          ),
          const SizedBox(height: 12),
          if (isTranslate)
            ElevatedButton.icon(
              onPressed: _textCtrl.text.trim().isEmpty ? null : _burnSubtitles,
              icon: const Icon(Icons.subtitles),
              label: const Text('Video ထဲ စာတန်းထိုးမယ်'),
            ),
          ElevatedButton.icon(
            onPressed: _textCtrl.text.trim().isEmpty ? null : _makeVoiceover,
            icon: const Icon(Icons.record_voice_over),
            label: const Text('အသံထွက်မယ် (စက်အသံ, အခမဲ့)'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Gemini free tier သုံးတယ်။ Key တစ်ခု limit ထိရင် နောက် key ကို auto ချိန်းတယ်။ Key တွေ Keys tab မှာ ထည့်ပါ (aistudio.google.com က အခမဲ့ရတယ်)။',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
