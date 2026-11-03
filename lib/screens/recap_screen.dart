import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'dart:convert';

import '../services/dub_renderer.dart';
import '../services/edge_tts_service.dart';
import '../services/ffmpeg_service.dart';
import '../services/gemini_service.dart';
import '../services/key_store.dart';
import '../widgets/job_runner.dart';

/// Full dubbing studio (Studio99 Recap-tab parity):
/// video preview, Gemini script, Edge TTS Myanmar voices, subtitle styling,
/// title/watermark, ratio+background, blur masks, smart sync, render.
class RecapScreen extends StatefulWidget {
  final int initialTab;
  const RecapScreen({super.key, this.initialTab = 0});

  @override
  State<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends State<RecapScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  // video
  String? _videoPath;
  MediaInfo? _info;
  VideoPlayerController? _player;

  // script
  final _textCtrl = TextEditingController();
  bool _busy = false;
  String _status = '';

  // voice (Edge TTS)
  String _voiceId = EdgeTtsService.voices[0].id;
  double _rate = 0; // -50..+50 %
  double _pitch = 0; // -20..+20 Hz
  String? _ttsPath;
  double _ttsSec = 0;

  // subtitle style
  bool _autoSub = true;
  Color _subColor = Colors.white;
  bool _subBg = true;
  Color _subBgColor = Colors.black;
  double _subBgOpacity = 0.6;
  double _subFontSize = 28;

  // title & watermark
  final _titleCtrl = TextEditingController();
  double _titleSize = 44;
  Color _titleColor = Colors.white;
  double _titleOpacity = 1.0;
  final _wmCtrl = TextEditingController(text: '@VideoTool');
  double _wmOpacity = 0.8;

  // ratio & bg
  String _ratio = '9:16';
  String _bgMode = 'blur'; // blur, pad
  final _masks = [BlurMask(), BlurMask()];

  // sync & fx
  bool _smartSync = true;
  bool _mirror = false;
  double _origVol = 0.3;
  bool _replaceAudio = false;

  // render
  String _resolution = '720p';

  final _keys = KeyStore();
  late GeminiService _gemini;
  final _edge = EdgeTtsService();

  static const _palette = [
    Colors.white,
    Colors.yellow,
    Colors.cyan,
    Colors.green,
    Colors.orange,
    Colors.pink,
    Colors.black,
    Colors.red,
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(
        length: 2, vsync: this, initialIndex: widget.initialTab);
    _gemini = GeminiService(_keys);
    _keys.load();
  }

  @override
  void dispose() {
    _tab.dispose();
    _textCtrl.dispose();
    _titleCtrl.dispose();
    _wmCtrl.dispose();
    _player?.dispose();
    super.dispose();
  }

  // ---------- video ----------

  Future<void> _pickVideo() async {
    final f =
        await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (f == null) return;
    await _player?.dispose();
    final ctrl = VideoPlayerController.file(File(f.path));
    await ctrl.initialize();
    final info = await FfmpegService.getMediaInfo(f.path);
    setState(() {
      _videoPath = f.path;
      _player = ctrl;
      _info = info;
    });
  }

  // ---------- script (Gemini) ----------

  Future<String?> _extractAudio() async {
    final inPath = _videoPath;
    if (inPath == null) return null;
    final outDir = await FfmpegService.outDir();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final out = '${outDir.path}/recap_audio_$ts.m4a';
    final rc = await FfmpegService.runJob(
      command:
          '-y -i ${FfmpegService.q(inPath)} -vn -c:a aac -b:a 64k -ac 1 ${FfmpegService.q(out)}',
      totalDurationMs: _info?.durationMs ?? 0,
      onProgress: (_) {},
      onLog: (_) {},
    );
    return rc == 0 ? out : null;
  }

  Future<void> _genScript() async {
    final isTranslate = _tab.index == 0;
    if (_videoPath == null) return;
    if (!_keys.hasUsableKey) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Keys tab မှာ Gemini key အရင်ထည့်ပါ')));
      return;
    }
    setState(() {
      _busy = true;
      _status = 'အသံထုတ်နေတယ်…';
    });
    final audio = await _extractAudio();
    if (audio == null || !mounted) {
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
        _status = 'Audio ကြီးလွန်းတယ် (18MB>)။ Video အတိုနဲ့ စမ်းပါ။';
      });
      return;
    }
    setState(() => _status = 'Gemini ရေးနေတယ်…');
    try {
      final prompt = isTranslate
          ? 'Transcribe this audio fully and translate it into Myanmar (Burmese). '
              'Output ONLY valid SRT subtitles — numbered entries with timestamps '
              'like 00:00:01,000 --> 00:00:04,000 followed by Myanmar text. '
              'No explanations, no markdown, just SRT.'
          : 'Listen to this audio from a video and write an engaging Myanmar '
              '(Burmese) storytelling recap script, as if narrating to a friend. '
              'Natural spoken Myanmar, 150-250 words. Output ONLY the script.';
      final text = await _gemini.generate(
        prompt,
        media: [
          GeminiMedia(mimeType: 'audio/mp4', base64: base64Encode(bytes))
        ],
        maxOutputTokens: 8192,
      );
      if (!mounted) return;
      setState(() {
        _textCtrl.text =
            text.replaceAll(RegExp(r'```\w*'), '').trim();
        _busy = false;
        _status = isTranslate
            ? 'စာတန်းရပြီ! အောက်မှာ style ချိန်ပြီး START နှိပ်ပါ။'
            : 'Script ရပြီ! အသံထွက်ပြီး START နှိပ်ပါ။';
      });
    } on GeminiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = e.message;
      });
    }
  }

  // ---------- voice (Edge TTS) ----------

  Future<void> _makeTts({bool sample = false}) async {
    final text = sample ? 'မင်္ဂလာပါ။ ဒါက အသံနမူနာပါ။' : _textCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _busy = true;
      _status = 'Edge TTS အသံထွက်နေတယ်… (internet လို)';
    });
    try {
      final path = await _edge.synthesize(
        text: text,
        voiceId: _voiceId,
        rate: EdgeTtsService.formatRate(_rate),
        pitch: EdgeTtsService.formatPitch(_pitch),
      );
      final info = await FfmpegService.getMediaInfo(path);
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (!sample) {
          _ttsPath = path;
          _ttsSec = (info?.durationMs ?? 0) / 1000;
          _status =
              'အသံရပြီ! (${_ttsSec.toStringAsFixed(1)} စက္ကန့်) START DUBBING နှိပ်ပါ။';
        } else {
          _status = 'နမူနာ ပြီးပြီ ✅';
        }
      });
      if (sample) {
        // play sample via video player hack: use a temp audio-only route
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('နမူနာ file ရပြီ — file manager မှာ ဖွင့်နားထောင်ပါ')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'TTS မရပါ: $e';
      });
    }
  }

  // ---------- render ----------

  void _startDubbing() {
    final inPath = _videoPath;
    final tts = _ttsPath;
    final info = _info;
    if (inPath == null || tts == null || info == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Video ရွေး → Script → TTS အသံထွက်ပြီးမှ START')));
      return;
    }
    final isTranslate = _tab.index == 0;
    final cfg = DubConfig(
      videoPath: inPath,
      ttsPath: tts,
      videoSec: info.durationMs / 1000,
      ttsSec: _ttsSec,
    )
      ..mirror = _mirror
      ..ratio = _ratio
      ..bgMode = _bgMode
      ..smartSync = _smartSync
      ..origVolume = _replaceAudio ? -1 : _origVol
      ..resolution = _resolution
      ..titleText = _titleCtrl.text
      ..titleSize = _titleSize
      ..titleColor = _titleColor
      ..titleOpacity = _titleOpacity
      ..wmText = _wmCtrl.text
      ..wmOpacity = _wmOpacity
      ..autoSubtitle = _autoSub && isTranslate
      ..subColor = _subColor
      ..subBg = _subBg
      ..subBgColor = _subBgColor
      ..subBgOpacity = _subBgOpacity
      ..subFontSize = _subFontSize;
    cfg.masks[0]
      ..enabled = _masks[0].enabled
      ..x = _masks[0].x
      ..y = _masks[0].y
      ..w = _masks[0].w
      ..h = _masks[0].h;
    cfg.masks[1]
      ..enabled = _masks[1].enabled
      ..x = _masks[1].x
      ..y = _masks[1].y
      ..w = _masks[1].w
      ..h = _masks[1].h;

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JobRunner(
        title: 'Dubbing…',
        run: (onProgress, onLog) async {
          // Write SRT for translate mode.
          if (cfg.autoSubtitle) {
            cfg.srtPath =
                await FfmpegService.writeSrt(_textCtrl.text.trim());
          }
          final out = await DubRenderer.render(cfg,
              onProgress: onProgress, onLog: onLog);
          return [out];
        },
      ),
    ));
  }

  // ---------- widgets ----------

  Widget _colorRow(Color value, void Function(Color) onPick) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _palette
          .map((c) => GestureDetector(
                onTap: () => onPick(c),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: value == c
                            ? Colors.tealAccent
                            : Colors.grey.shade700,
                        width: value == c ? 3 : 1),
                  ),
                  child: value == c
                      ? const Icon(Icons.check,
                          color: Colors.black, size: 20)
                      : null,
                ),
              ))
          .toList(),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🎬 Dubbing Studio')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // 1. Video
          _section('📹 Video', [
            ElevatedButton.icon(
              onPressed: _busy ? null : _pickVideo,
              icon: const Icon(Icons.video_library),
              label: const Text('Gallery မှ ရွေးမယ်'),
            ),
            const SizedBox(height: 8),
            if (_player != null && _player!.value.isInitialized)
              AspectRatio(
                aspectRatio: _player!.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_player!),
                    IconButton(
                      icon: Icon(
                          _player!.value.isPlaying
                              ? Icons.pause_circle
                              : Icons.play_circle,
                          size: 56,
                          color: Colors.white70),
                      onPressed: () => setState(() =>
                          _player!.value.isPlaying
                              ? _player!.pause()
                              : _player!.play()),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(
                height: 160,
                child: Center(
                    child: Text('Preview ပြဖို့ ဗီဒီယိုရွေးပါ',
                        style: TextStyle(color: Colors.grey))),
              ),
            if (_info != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    '${(_info!.durationMs / 1000).toStringAsFixed(0)}s · ${_info!.resolution}',
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 12)),
              ),
          ]),

          // 2. Script
          _section('📝 Script (Gemini)', [
            TabBar(
              controller: _tab,
              tabs: const [
                Tab(text: 'Recap Translate'),
                Tab(text: 'Original Recap'),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: (_busy || _videoPath == null)
                  ? null
                  : _genScript,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Script Generate · My Gemini API'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple),
            ),
            if (_busy) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_status,
                  style: const TextStyle(
                      color: Colors.teal, fontSize: 13)),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _textCtrl,
              maxLines: 8,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Script / SRT ဒီမှာ…',
              ),
            ),
          ]),

          // 3. Voice
          _section('🔊 အသံ (Edge TTS · အခမဲ့)', [
            DropdownButtonFormField<String>(
              initialValue: _voiceId,
              decoration: const InputDecoration(
                  labelText: 'အသံ', border: OutlineInputBorder()),
              items: EdgeTtsService.voices
                  .map((v) => DropdownMenuItem(
                      value: v.id, child: Text('${v.label} · Edge')))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _voiceId = v ?? _voiceId),
            ),
            const SizedBox(height: 8),
            Text('Speed: ${_rate.round()}%'),
            Slider(
                min: -50,
                max: 50,
                divisions: 20,
                value: _rate,
                onChanged: (v) => setState(() => _rate = v)),
            Text('Pitch: ${_pitch.round()}Hz'),
            Slider(
                min: -20,
                max: 20,
                divisions: 20,
                value: _pitch,
                onChanged: (v) => setState(() => _pitch = v)),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _makeTts(sample: true),
                    icon: const Icon(Icons.hearing),
                    label: const Text('အသံနမူနာ'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_busy || _textCtrl.text.trim().isEmpty)
                        ? null
                        : () => _makeTts(),
                    icon: const Icon(Icons.mic),
                    label: const Text('TTS Audio ထုတ်မယ်'),
                  ),
                ),
              ],
            ),
            if (_ttsPath != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    '✅ အသံရပြီ (${_ttsSec.toStringAsFixed(1)}s)',
                    style:
                        const TextStyle(color: Colors.green)),
              ),
          ]),

          // 4. Subtitle style
          _section('💬 စာတန်း Style', [
            SwitchListTile(
              title: const Text('Auto Subtitle (စာတန်းထိုးထည့်မယ်)'),
              value: _autoSub,
              onChanged: (v) => setState(() => _autoSub = v),
            ),
            const Text('စာလုံးအရောင်'),
            const SizedBox(height: 8),
            _colorRow(_subColor, (c) => setState(() => _subColor = c)),
            SwitchListTile(
              title: const Text('နောက်ခံ box'),
              value: _subBg,
              onChanged: (v) => setState(() => _subBg = v),
            ),
            if (_subBg) ...[
              const Text('နောက်ခံအရောင်'),
              const SizedBox(height: 8),
              _colorRow(_subBgColor,
                  (c) => setState(() => _subBgColor = c)),
              Text(
                  'နောက်ခံအထူ ${( _subBgOpacity * 100).round()}%'),
              Slider(
                  value: _subBgOpacity,
                  min: 0.1,
                  max: 1.0,
                  onChanged: (v) =>
                      setState(() => _subBgOpacity = v)),
            ],
            Text('Font Size: ${_subFontSize.round()}'),
            Slider(
                min: 16,
                max: 48,
                value: _subFontSize,
                onChanged: (v) =>
                    setState(() => _subFontSize = v)),
          ]),

          // 5. Title & watermark
          _section('🔤 Title & Watermark', [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Title Text (မြန်မာ)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text('Title size: ${_titleSize.round()}'),
            Slider(
                min: 24,
                max: 80,
                value: _titleSize,
                onChanged: (v) => setState(() => _titleSize = v)),
            const Text('Title အရောင်'),
            const SizedBox(height: 8),
            _colorRow(_titleColor,
                (c) => setState(() => _titleColor = c)),
            Text('Title opacity ${(_titleOpacity * 100).round()}%'),
            Slider(
                value: _titleOpacity,
                min: 0.2,
                max: 1.0,
                onChanged: (v) =>
                    setState(() => _titleOpacity = v)),
            const Divider(),
            TextField(
              controller: _wmCtrl,
              decoration: const InputDecoration(
                labelText: 'Watermark Text',
                border: OutlineInputBorder(),
              ),
            ),
            Text(
                'Watermark opacity ${(_wmOpacity * 100).round()}%'),
            Slider(
                value: _wmOpacity,
                min: 0.1,
                max: 1.0,
                onChanged: (v) =>
                    setState(() => _wmOpacity = v)),
          ]),

          // 6. Ratio & background + blur masks
          _section('🖼️ Ratio & Background', [
            const Text('Video Ratio'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['9:16', '16:9', '1:1', '4:3', 'original']
                  .map((r) => ChoiceChip(
                        label: Text(r),
                        selected: _ratio == r,
                        onSelected: (_) =>
                            setState(() => _ratio = r),
                      ))
                  .toList(),
            ),
            if (_ratio != 'original') ...[
              const SizedBox(height: 12),
              const Text('နောက်ခံ'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                      label: const Text('Blur နောက်ခံ'),
                      selected: _bgMode == 'blur',
                      onSelected: (_) =>
                          setState(() => _bgMode = 'blur')),
                  ChoiceChip(
                      label: const Text('အနက်နောက်ခံ'),
                      selected: _bgMode == 'pad',
                      onSelected: (_) =>
                          setState(() => _bgMode = 'pad')),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Text('Blur Mask (watermark ဖျက်ဖို့)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            for (var i = 0; i < 2; i++) ...[
              SwitchListTile(
                title: Text('Blur ${i + 1}'),
                value: _masks[i].enabled,
                onChanged: (v) =>
                    setState(() => _masks[i].enabled = v),
              ),
              if (_masks[i].enabled) ...[
                Text('အလျားလိုက်: ${(_masks[i].x * 100).round()}%'),
                Slider(
                    value: _masks[i].x,
                    min: 0,
                    max: 0.9,
                    onChanged: (v) =>
                        setState(() => _masks[i].x = v)),
                Text('အနံလိုက်: ${(_masks[i].y * 100).round()}%'),
                Slider(
                    value: _masks[i].y,
                    min: 0,
                    max: 0.9,
                    onChanged: (v) =>
                        setState(() => _masks[i].y = v)),
                Text('အရွယ်: ${(_masks[i].w * 100).round()}%'),
                Slider(
                    value: _masks[i].w,
                    min: 0.05,
                    max: 0.6,
                    onChanged: (v) => setState(() {
                          _masks[i].w = v;
                          _masks[i].h = v * 0.5;
                        })),
              ],
            ],
          ]),

          // 7. Sync & fx
          _section('⚙️ Sync & Effects', [
            SwitchListTile(
              title: const Text('AI Smart Sync (Auto)'),
              subtitle: const Text(
                  'အသံရှည်ရင် video ကို 1.25x ထိ မြန်ပြီး frame lock နဲ့ ချိန်မယ်',
                  style: TextStyle(fontSize: 12)),
              value: _smartSync,
              onChanged: (v) => setState(() => _smartSync = v),
            ),
            SwitchListTile(
              title: const Text('Mirror (Flip Horizontal)'),
              value: _mirror,
              onChanged: (v) => setState(() => _mirror = v),
            ),
            SwitchListTile(
              title: const Text('မူရင်းအသံ အစားထိုးမယ်'),
              value: _replaceAudio,
              onChanged: (v) =>
                  setState(() => _replaceAudio = v),
            ),
            if (!_replaceAudio) ...[
              Text(
                  'မူရင်းအသံ ကျယ်/တိုး: ${(_origVol * 100).round()}%'),
              Slider(
                  value: _origVol,
                  min: 0,
                  max: 1,
                  onChanged: (v) =>
                      setState(() => _origVol = v)),
            ],
          ]),

          // 8. Render
          Card(
            color: Colors.purple.shade50,
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('🎬 Render (ဖုန်းပေါ်တွင်)',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text('Output Resolution'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['720p', '1080p']
                        .map((r) => ChoiceChip(
                              label: Text(r == '720p'
                                  ? '720p HD'
                                  : '1080p FHD'),
                              selected: _resolution == r,
                              onSelected: (_) => setState(
                                  () => _resolution = r),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Resolution မြင့်လေ render ကြာနိုင်၊ ဖုန်းပူမယ်။',
                    style:
                        TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: (_busy ||
                            _videoPath == null ||
                            _ttsPath == null)
                        ? null
                        : _startDubbing,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pinkAccent,
                      padding:
                          const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('START DUBBING',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
