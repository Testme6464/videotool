import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/ffmpeg_service.dart';
import '../widgets/job_runner.dart';

/// Dhamma Studio — Studio99-style full studio:
/// source audio → smart/manual audio processing → monk photo →
/// background (auto-mix Ken Burns / single) → text overlays →
/// watermark → output.
class DhammaScreen extends StatefulWidget {
  const DhammaScreen({super.key});

  @override
  State<DhammaScreen> createState() => _DhammaScreenState();
}

class _DhammaScreenState extends State<DhammaScreen> {
  final _projectCtrl = TextEditingController(text: 'Dhamma Video');
  String? _audioPath;
  double _audioLenSec = 0;
  bool _loading = false;

  // 2. Audio processing
  String _audioMode = 'smart'; // original, smart, manual
  double _manualSpeed = 1.0;
  double _manualPitch = 0.0; // semitones

  // 3. Monk
  String? _monkPath;

  // 4. Background
  String _bgMode = 'automix'; // automix, single
  final List<String> _bgImages = [];

  // 5. Text overlay
  final _titleCtrl = TextEditingController();
  final _speakerCtrl = TextEditingController();
  final _quoteCtrl = TextEditingController();
  final _wmCtrl = TextEditingController(text: 'Studio99');
  double _titleSize = 42;
  double _speakerSize = 27;
  double _quoteSize = 32;
  double _wmSize = 22;

  // 7. Output
  String _ratio = '16:9';

  Future<void> _pickAudio() async {
    final files =
        await FilePicker.pickFiles(type: FileType.audio);
    if (files.isEmpty || files.single.path == null) return;
    final path = files.single.path!;
    setState(() => _loading = true);
    final info = await FfmpegService.getMediaInfo(path);
    setState(() {
      _audioPath = path;
      _audioLenSec = (info?.durationMs ?? 0) / 1000;
      _loading = false;
    });
  }

  Future<void> _pickMonk() async {
    final f =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f == null) return;
    setState(() => _monkPath = f.path);
  }

  Future<void> _pickBg() async {
    final files = await FilePicker.pickFiles(
      type: FileType.image,
    );
    if (files.isEmpty) return;
    setState(() {
      _bgImages.addAll(files
          .where((f) => f.path != null)
          .map((f) => f.path!));
    });
  }

  String _audioFilter() {
    if (_audioMode == 'original') return 'anull';
    final speed = _audioMode == 'smart' ? 1.06 : _manualSpeed;
    final pitch = _audioMode == 'smart' ? 1.0 : _manualPitch;
    // Pitch shift via asetrate, then speed via atempo.
    final rate = (44100 * pow(2, pitch / 12)).round();
    return 'asetrate=$rate,aresample=44100,atempo=$speed';
  }

  void _start() {
    final audio = _audioPath;
    if (audio == null || _bgImages.isEmpty) return;
    final title = _titleCtrl.text.trim();
    final speaker = _speakerCtrl.text.trim();
    final quote = _quoteCtrl.text.trim();
    final wm = _wmCtrl.text.trim();
    final monk = _monkPath;

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JobRunner(
        title: 'Dhamma Studio',
        run: (onProgress, onLog) async {
          final outDir = await FfmpegService.outDir();
          final font = await FfmpegService.fontPath();
          final ts = DateTime.now().millisecondsSinceEpoch;

          // Target resolution.
          final (tw, th) = _ratio == '9:16'
              ? (720, 1280)
              : _ratio == '1:1'
                  ? (1080, 1080)
                  : (1280, 720);

          String esc(String s) => FfmpegService.esc(s);

          // ---- Step 1: build silent visual (slideshow or loop) ----
          final visual = '${outDir.path}/dhamma_vis_$ts.mp4';
          final per = _audioLenSec / _bgImages.length;
          if (_bgImages.length == 1) {
            onLog('Background ပုံ loop လုပ်နေတယ်…');
            final vf =
                'scale=${tw}:${th}:force_original_aspect_ratio=increase,'
                'crop=$tw:$th,format=yuv420p';
            final rc = await FfmpegService.runJob(
              command: '-y -loop 1 -i ${FfmpegService.q(_bgImages.first)} '
                  '-vf "$vf" -t ${_audioLenSec.toStringAsFixed(1)} '
                  '-c:v libx264 -crf 23 -preset veryfast -an '
                  '${FfmpegService.q(visual)}',
              totalDurationMs: _audioLenSec * 1000,
              onProgress: (p) => onProgress(p * 0.5),
              onLog: onLog,
            );
            if (rc != 0) throw Exception('Background failed ($rc)');
          } else {
            onLog('Auto Mix: ပုံ ${_bgImages.length} ပုံ Ken Burns…');
            final clips = <String>[];
            final rnd = Random(ts);
            for (var i = 0; i < _bgImages.length; i++) {
              final clip = '${outDir.path}/dhamma_c${ts}_$i.mp4';
              final zoomIn = rnd.nextBool();
              final zoom =
                  zoomIn ? '1+0.08*on/$per/30' : '1.08-0.08*on/$per/30';
              final frames = (per * 30).round();
              final vf =
                  'scale=${tw * 2}:${th * 2}:force_original_aspect_ratio=increase,'
                  'crop=${tw * 2}:${th * 2},'
                  'zoompan=z=$zoom:d=$frames:s=${tw}x$th:fps=30,'
                  'format=yuv420p';
              final rc = await FfmpegService.runJob(
                command: '-y -loop 1 -i ${FfmpegService.q(_bgImages[i])} '
                    '-vf "$vf" -t ${per.toStringAsFixed(1)} -an '
                    '-c:v libx264 -crf 23 -preset veryfast '
                    '${FfmpegService.q(clip)}',
                totalDurationMs: per * 1000,
                onProgress: (p) =>
                    onProgress((i + p) / _bgImages.length * 0.4),
                onLog: onLog,
              );
              if (rc != 0) throw Exception('Clip ${i + 1} failed ($rc)');
              clips.add(clip);
            }
            final listFile =
                File('${outDir.path}/dhamma_list_$ts.txt');
            await listFile.writeAsString(
                clips.map((c) => "file '$c'").join('\n'));
            final rc = await FfmpegService.runJob(
              command: '-y -f concat -safe 0 '
                  '-i ${FfmpegService.q(listFile.path)} -c copy '
                  '${FfmpegService.q(visual)}',
              totalDurationMs: _audioLenSec * 1000,
              onProgress: (p) => onProgress(0.4 + p * 0.1),
              onLog: onLog,
            );
            if (rc != 0) throw Exception('Concat failed ($rc)');
          }

          // ---- Step 2: process audio ----
          final procAudio = '${outDir.path}/dhamma_aud_$ts.m4a';
          onLog('အသံ processing (${_audioMode})…');
          var rc = await FfmpegService.runJob(
            command: '-y -i ${FfmpegService.q(audio)} '
                '-af "${_audioFilter()}" -c:a aac -b:a 128k '
                '${FfmpegService.q(procAudio)}',
            totalDurationMs: _audioLenSec * 1000,
            onProgress: (p) => onProgress(0.5 + p * 0.1),
            onLog: onLog,
          );
          if (rc != 0) throw Exception('Audio failed ($rc)');

          // ---- Step 3: overlays + mux ----
          onLog('စာသား + ဆရာတော်ပုံ ထည့်နေတယ်…');
          final filters = <String>[];
          var vLabel = '[0:v]';
          var nextInput = 2; // 0=visual, 1=audio, 2+=monk
          if (monk != null) {
            final mw = (tw * 0.22).round();
            filters.add(
                '[2:v]scale=$mw:-1,format=yuva420p[monk];'
                '$vLabel[monk]overlay=W-w-24:24[v1]');
            vLabel = '[v1]';
            nextInput = 3;
          }
          String dt(String text, double size, String pos) =>
              "drawtext=fontfile=${FfmpegService.q(font)}"
              ":text='${esc(text)}'"
              ':fontsize=${size.round()}:fontcolor=white'
              ':borderw=2:bordercolor=black:$pos';
          if (title.isNotEmpty) {
            filters.add('$vLabel${dt(title, _titleSize, "x=(w-text_w)/2:y=48")}[v2]');
            vLabel = '[v2]';
          }
          if (speaker.isNotEmpty) {
            final y = title.isNotEmpty
                ? 48 + _titleSize.round() + 16
                : 48;
            filters.add(
                '$vLabel${dt(speaker, _speakerSize, "x=(w-text_w)/2:y=$y")}[v3]');
            vLabel = '[v3]';
          }
          if (quote.isNotEmpty) {
            filters.add(
                '$vLabel${dt(quote, _quoteSize, "x=(w-text_w)/2:y=h-text_h-120")}[v4]');
            vLabel = '[v4]';
          }
          if (wm.isNotEmpty) {
            filters.add(
                '$vLabel${dt(wm, _wmSize, "x=w-text_w-24:y=h-text_h-24")}[v5]');
            vLabel = '[v5]';
          }
          final fc = filters.isEmpty
              ? ''
              : ' -filter_complex "${filters.join(';')}" -map "$vLabel" -map 1:a';

          final out = '${outDir.path}/dhamma_$ts.mp4';
          var cmd = '-y -i ${FfmpegService.q(visual)} '
              '-i ${FfmpegService.q(procAudio)}';
          if (monk != null) {
            cmd += ' -i ${FfmpegService.q(monk)}';
          }
          cmd += '$fc -c:v libx264 -crf 23 -preset veryfast '
              '-c:a copy -shortest -movflags +faststart '
              '${FfmpegService.q(out)}';
          // Silence unused variable warning.
          nextInput.toString();
          rc = await FfmpegService.runJob(
            command: cmd,
            totalDurationMs: _audioLenSec * 1000,
            onProgress: (p) => onProgress(0.6 + p * 0.4),
            onLog: onLog,
          );
          if (rc != 0) throw Exception('Final render failed ($rc)');
          return [out];
        },
      ),
    ));
  }

  Widget _card(Widget child, {String? title, String? icon}) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${icon ?? ''} $title',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
              child,
            ],
          ),
        ),
      );

  Widget _chip(String label, bool sel, VoidCallback onTap) =>
      ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) => onTap(),
        showCheckmark: true,
      );

  Widget _textField(TextEditingController c, String label) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Widget _styleRow(String label, double size, ValueChanged<double> onSize,
          TextEditingController previewCtrl) =>
      Card(
        color: Colors.black26,
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Text('Size', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      min: 16,
                      max: 72,
                      value: size,
                      onChanged: onSize,
                    ),
                  ),
                  Text('${size.round()}',
                      style: const TextStyle(
                          color: Colors.teal, fontSize: 12)),
                ],
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  previewCtrl.text.isEmpty
                      ? 'ဓမ္မစာသား နမူနာ'
                      : previewCtrl.text,
                  style: TextStyle(fontSize: size * 0.55),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dhamma Studio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            TextField(
              controller: _projectCtrl,
              decoration: const InputDecoration(
                labelText: 'Project',
                border: OutlineInputBorder(),
              ),
            ),
            title: 'Project', icon: '📝'),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    _chip('🎵 My Audio', true, () {}),
                    _chip('📚 Dhamma Library', false,
                        () {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(
                              content: Text(
                                  'Library နောက်ဗားရှင်းမှာ ထည့်ပေးမယ်')));
                    }),
                  ],
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.audiotrack,
                      color: Colors.teal),
                  title: Text(_audioPath == null
                      ? 'Audio / Video File ရွေးပါ'
                      : _audioPath!.split('/').last,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(_audioPath == null
                      ? 'MP3, WAV, M4A, AAC, FLAC, MP4, MKV, WEBM…'
                      : '${(_audioLenSec / 60).toStringAsFixed(1)} မိနစ်'),
                  trailing:
                      const Icon(Icons.chevron_right),
                  onTap: _pickAudio,
                ),
                if (_loading)
                  const LinearProgressIndicator(),
              ],
            ),
            title: '1. Dhamma Source', icon: '🎵'),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    _chip('Original', _audioMode == 'original',
                        () => setState(() => _audioMode = 'original')),
                    _chip('✨ Smart Audio',
                        _audioMode == 'smart',
                        () => setState(() => _audioMode = 'smart')),
                    _chip('Manual', _audioMode == 'manual',
                        () => setState(() => _audioMode = 'manual')),
                  ],
                ),
                if (_audioMode == 'smart')
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Card(
                      color: Colors.tealAccent,
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Icon(Icons.auto_awesome,
                                color: Colors.black87),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Studio99 Smart · Speed 1.06x · Pitch +1.0 semitone',
                                style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_audioMode == 'manual') ...[
                  const SizedBox(height: 8),
                  Text(
                      'Speed: ${_manualSpeed.toStringAsFixed(2)}x'),
                  Slider(
                    min: 0.8,
                    max: 1.3,
                    value: _manualSpeed,
                    onChanged: (v) => setState(
                        () => _manualSpeed = v),
                  ),
                  Text(
                      'Pitch: ${_manualPitch.toStringAsFixed(1)} semitone'),
                  Slider(
                    min: -2,
                    max: 2,
                    divisions: 8,
                    value: _manualPitch,
                    onChanged: (v) => setState(
                        () => _manualPitch = v),
                  ),
                ],
              ],
            ),
            title: '2. Audio Processing', icon: '🎚️'),
          _card(
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading:
                  const Icon(Icons.person, color: Colors.teal),
              title: Text(_monkPath == null
                  ? 'Monk Photo ရွေးပါ'
                  : _monkPath!.split('/').last,
                  overflow: TextOverflow.ellipsis),
              subtitle:
                  const Text('JPG, PNG, WEBP (မရွေးလဲ ရတယ်)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickMonk,
            ),
            title: '3. Monk', icon: '🧘'),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    _chip('🔀 Auto Mix', _bgMode == 'automix',
                        () => setState(() => _bgMode = 'automix')),
                    _chip('🖼️ ပုံတစ်ပုံ', _bgMode == 'single',
                        () => setState(() => _bgMode = 'single')),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickBg,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: Text(_bgImages.isEmpty
                      ? 'Background ပုံတွေ ရွေးပါ'
                      : 'နောက်ထပ် ထည့်မယ် (${_bgImages.length})'),
                ),
                if (_bgImages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _bgImages
                          .asMap()
                          .entries
                          .map((e) => Stack(
                                children: [
                                  Image.file(
                                      File(e.value),
                                      width: 72,
                                      height: 72,
                                      fit: BoxFit.cover),
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: GestureDetector(
                                      onTap: () => setState(() =>
                                          _bgImages.removeAt(
                                              e.key)),
                                      child: Container(
                                        color: Colors.black54,
                                        child: const Icon(
                                            Icons.close,
                                            size: 16,
                                            color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ))
                          .toList(),
                    ),
                  ),
                if (_bgMode == 'automix' &&
                    _bgImages.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${_bgImages.length} ပုံ auto mix · Ken Burns effect နဲ့ လှည့်ပြမယ်',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12),
                    ),
                  ),
              ],
            ),
            title: '4. Background', icon: '🖼️'),
          _card(
            Column(
              children: [
                _textField(_titleCtrl,
                    'Title — ဥပမာ မေတ္တာတရား၏ အကျိုး'),
                _textField(
                    _speakerCtrl, 'Speaker / ဆရာတော်အမည်'),
                _textField(_quoteCtrl, 'Quote / စာတန်း'),
                _textField(_wmCtrl, 'Watermark'),
                const SizedBox(height: 4),
                _styleRow('Title', _titleSize,
                    (v) => setState(() => _titleSize = v),
                    _titleCtrl),
                _styleRow('Speaker', _speakerSize,
                    (v) =>
                        setState(() => _speakerSize = v),
                    _speakerCtrl),
                _styleRow('Quote', _quoteSize,
                    (v) => setState(() => _quoteSize = v),
                    _quoteCtrl),
                _styleRow('Watermark', _wmSize,
                    (v) => setState(() => _wmSize = v),
                    _wmCtrl),
                const Text(
                  'Recap screen က Myanmar font ကို ပြန်သုံးထားပါတယ်။ Title box ပြတ်နေတာကို render အချိန်မှာ auto-fit လုပ်ပေးထားပါတယ်။',
                  style:
                      TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
            title: '5. Text Overlay', icon: '🔤'),
          _card(
            Wrap(
              spacing: 8,
              children: [
                _chip('16:9', _ratio == '16:9',
                    () => setState(() => _ratio = '16:9')),
                _chip('9:16', _ratio == '9:16',
                    () => setState(() => _ratio = '9:16')),
                _chip('1:1', _ratio == '1:1',
                    () => setState(() => _ratio = '1:1')),
              ],
            ),
            title: '6. Output', icon: '🖼️'),
          ElevatedButton.icon(
            onPressed: (_audioPath != null &&
                    _bgImages.isNotEmpty &&
                    !_loading)
                ? _start
                : null,
            icon: const Icon(Icons.movie),
            label: const Text('🎬 Create Dhamma Video · Local',
                style: TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
                minimumSize:
                    const Size.fromHeight(52)),
          ),
          const SizedBox(height: 8),
          const Text(
            'အသံအရှည်အတိုင်း video ထွက်မယ်။ ပုံအများကြီးဆို Ken Burns နဲ့ လှည့်ပြမယ်။',
            style:
                TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _projectCtrl.dispose();
    _titleCtrl.dispose();
    _speakerCtrl.dispose();
    _quoteCtrl.dispose();
    _wmCtrl.dispose();
    super.dispose();
  }
}
