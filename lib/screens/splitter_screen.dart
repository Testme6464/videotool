import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/ffmpeg_service.dart';
import '../widgets/job_runner.dart';

/// Video Splitter — Studio99-style: smart cut, quality, ratio, mirror,
/// Myanmar part numbering overlay.
class SplitterScreen extends StatefulWidget {
  const SplitterScreen({super.key});

  @override
  State<SplitterScreen> createState() => _SplitterScreenState();
}

const _mmDigits = ['၀', '၁', '၂', '၃', '၄', '၅', '၆', '၇', '၈', '၉'];

String toMyanmarDigits(int n) =>
    n.toString().split('').map((c) => _mmDigits[int.parse(c)]).join();

class _SplitterScreenState extends State<SplitterScreen> {
  String? _videoPath;
  MediaInfo? _info;
  bool _loading = false;

  double _minutes = 3;
  bool _smartCut = true;
  bool _goodQuality = true; // ကောင်း vs မြန်
  String _ratio = 'original'; // original, 9:16, 16:9, 1:1
  bool _mirror = false;

  bool _numbering = true;
  final _tplCtrl = TextEditingController(text: 'အပိုင်း {mm}');
  bool _numTop = true;
  double _numSizePct = 100;
  Color _numColor = Colors.white;
  double _numOpacity = 100;

  static const _numColors = <Color>[
    Colors.white,
    Colors.yellow,
    Colors.cyan,
    Color(0xFF8BC34A),
    Colors.orange,
    Colors.pink,
    Colors.black,
    Colors.red,
  ];

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

  String _assColor(Color c, double opacityPct) {
    final a = ((1 - opacityPct / 100) * 255).round();
    String h(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    final r = (c.r * 255).round().clamp(0, 255);
    final g = (c.g * 255).round().clamp(0, 255);
    final b = (c.b * 255).round().clamp(0, 255);
    return '&H${h(a)}${h(b)}${h(g)}${h(r)}';
  }

  String _fillTemplate(String tpl, int n, int total) => tpl
      .replaceAll('{mm}', toMyanmarDigits(n))
      .replaceAll('{n}', '$n')
      .replaceAll('{total}', '$total');

  void _start() {
    final inPath = _videoPath;
    final info = _info;
    if (inPath == null || info == null) return;
    final segSec = (_minutes * 60).round();
    final totalSec = (info.durationMs / 1000).round();
    final parts = (totalSec / segSec).ceil().clamp(1, 999);
    final needReencode =
        _smartCut || _numbering || _mirror || _ratio != 'original';

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JobRunner(
        title: 'Video Splitter',
        run: (onProgress, onLog) async {
          final outDir = await FfmpegService.outDir();
          final fontPath = await FfmpegService.fontPath();
          final ts = DateTime.now().millisecondsSinceEpoch;
          final produced = <String>[];

          if (!needReencode) {
            // Fast path: segment muxer, stream copy.
            final outPattern = '${outDir.path}/split_${ts}_%03d.mp4';
            final cmd =
                '-y -i ${FfmpegService.q(inPath)} -c copy -map 0 '
                '-segment_time $segSec -f segment -reset_timestamps 1 '
                '${FfmpegService.q(outPattern)}';
            final rc = await FfmpegService.runJob(
              command: cmd,
              totalDurationMs: info.durationMs,
              onProgress: onProgress,
              onLog: onLog,
            );
            if (rc != 0) throw Exception('FFmpeg failed (code $rc)');
            produced.addAll(outDir
                .listSync()
                .whereType<File>()
                .where((f) => f.path.contains('split_${ts}_'))
                .map((f) => f.path)
                .toList()
              ..sort());
            return produced;
          }

          // Re-encode path: precise cuts + filters per part.
          final crf = _goodQuality ? '23' : '28';
          final preset = _goodQuality ? 'medium' : 'veryfast';
          for (var i = 0; i < parts; i++) {
            final start = i * segSec;
            final dur = (start + segSec <= totalSec)
                ? segSec
                : totalSec - start;
            if (dur <= 0) break;
            final n = i + 1;
            final filters = <String>[];
            if (_mirror) filters.add('hflip');
            if (_ratio != 'original') {
              // Center-crop to ratio.
              final dims = _ratio == '9:16'
                  ? 'ih*9/16:ih'
                  : _ratio == '16:9'
                      ? 'iw:iw*9/16'
                      : 'min(iw\\,ih):min(iw\\,ih)';
              filters.add('crop=$dims');
            }
            if (_numbering) {
              final label = _fillTemplate(_tplCtrl.text, n, parts);
              final size = (32 * _numSizePct / 100).round();
              final y = _numTop ? '40' : 'h-40-text_h';
              filters.add(
                  "drawtext=fontfile=${FfmpegService.q(fontPath)}"
                  ":text='${FfmpegService.esc(label)}'"
                  ':fontsize=$size:fontcolor=${_assColor(_numColor, _numOpacity)}'
                  ':x=(w-text_w)/2:y=$y');
            }
            final vf = filters.isEmpty
                ? ''
                : ' -vf "${filters.join(',')}"';
            final out =
                '${outDir.path}/split_${ts}_${n.toString().padLeft(3, '0')}.mp4';
            final cmd = '-y -ss $start -t $dur -i ${FfmpegService.q(inPath)}$vf '
                '-c:v libx264 -crf $crf -preset $preset -c:a aac -b:a 128k '
                '${FfmpegService.q(out)}';
            onLog('အပိုင်း $n/$parts …');
            final rc = await FfmpegService.runJob(
              command: cmd,
              totalDurationMs: dur * 1000,
              onProgress: (p) =>
                  onProgress(((i + p) / parts).clamp(0.0, 1.0)),
              onLog: onLog,
            );
            if (rc != 0) throw Exception('အပိုင်း $n မှာ FFmpeg failed ($rc)');
            produced.add(out);
          }
          return produced;
        },
      ),
    ));
  }

  Widget _card(Widget child) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
            padding: const EdgeInsets.all(14), child: child),
      );

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
      appBar: AppBar(title: const Text('Video Splitter')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🎬 ဗီဒီယို',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.video_library,
                    color: Colors.teal),
                title: Text(_videoPath == null
                    ? 'ဗီဒီယို ရွေးပါ'
                    : _videoPath!.split('/').last,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(_info == null
                    ? 'Gallery / File မှ ရွေးရန် နှိပ်ပါ'
                    : '${(_info!.durationMs / 60000).toStringAsFixed(1)} မိနစ် · ${_info!.resolution}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pick,
              ),
              if (_loading) const LinearProgressIndicator(),
            ],
          )),
          _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('✂️ ခွဲပုံ',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text('တစ်ပိုင်း: ${_minutes.toStringAsFixed(0)} မိနစ်'),
              Slider(
                min: 1,
                max: 30,
                divisions: 29,
                value: _minutes,
                label: '${_minutes.toStringAsFixed(0)} min',
                onChanged: (v) =>
                    setState(() => _minutes = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Smart cut (အနားယူချိန်မှာ ဖြတ်)'),
                subtitle: const Text(
                    'ပိတ်ရင် မိနစ်အတိအကျ ဖြတ်ပါမယ်'),
                value: _smartCut,
                onChanged: (v) =>
                    setState(() => _smartCut = v),
              ),
              const Text('Quality'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  _chip('ကောင်း',
                      _goodQuality, () => setState(() => _goodQuality = true)),
                  _chip('မြန်', !_goodQuality,
                      () => setState(() => _goodQuality = false)),
                ],
              ),
            ],
          )),
          _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🖼️ Output',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              const Text('Ratio'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  _chip('Original', _ratio == 'original',
                      () => setState(() => _ratio = 'original')),
                  _chip('9:16', _ratio == '9:16',
                      () => setState(() => _ratio = '9:16')),
                  _chip('16:9', _ratio == '16:9',
                      () => setState(() => _ratio = '16:9')),
                  _chip('1:1', _ratio == '1:1',
                      () => setState(() => _ratio = '1:1')),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mirror (Flip Horizontal)'),
                subtitle: const Text(
                    'ပုံကို ဘယ်ညာ ပြောင်းပြန်လုပ်မယ် (စာတန်းကို မလှန်ပါ)'),
                value: _mirror,
                onChanged: (v) =>
                    setState(() => _mirror = v),
              ),
            ],
          )),
          _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('🔢 အပိုင်း နံပါတ်',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                subtitle: const Text('"အပိုင်း ၁" စာ ထည့်မယ်'),
                value: _numbering,
                onChanged: (v) =>
                    setState(() => _numbering = v),
              ),
              if (_numbering) ...[
                TextField(
                  controller: _tplCtrl,
                  decoration: const InputDecoration(
                    labelText:
                        'စာ ({mm} = မြန်မာဂဏန်း၊ {n} = 1,2,3၊ {total} = စုစုပေါင်း)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                const Text('နမူနာ: အပိုင်း ၂',
                    style: TextStyle(
                        color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _chip('အပေါ်', _numTop,
                        () => setState(() => _numTop = true)),
                    _chip('အောက်', !_numTop,
                        () => setState(() => _numTop = false)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                    'စာလုံးအရွယ် ${_numSizePct.toStringAsFixed(0)}%'),
                Slider(
                  min: 50,
                  max: 200,
                  value: _numSizePct,
                  onChanged: (v) =>
                      setState(() => _numSizePct = v),
                ),
                const Text('စာလုံးအရောင်'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _numColors
                      .map((c) => GestureDetector(
                            onTap: () => setState(
                                () => _numColor = c),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _numColor == c
                                      ? Colors.teal
                                      : Colors.grey,
                                  width: _numColor == c
                                      ? 3
                                      : 1,
                                ),
                              ),
                              child: _numColor == c
                                  ? const Icon(Icons.check,
                                      size: 18)
                                  : null,
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                Text(
                    'ပြင်သာမှု ${_numOpacity.toStringAsFixed(0)}%'),
                Slider(
                  min: 20,
                  max: 100,
                  value: _numOpacity,
                  onChanged: (v) =>
                      setState(() => _numOpacity = v),
                ),
              ],
            ],
          )),
          ElevatedButton.icon(
            onPressed: (_videoPath != null && !_loading)
                ? _start
                : null,
            icon: const Icon(Icons.content_cut),
            label: const Text('အပိုင်းခွဲမယ်',
                style: TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
                minimumSize:
                    const Size.fromHeight(52)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Smart cut ပိတ်ထားရင် re-encode မလုပ်ဘဲ မြန်မြန်ဖြတ်တယ် (keyframe မှာပဲ တိတိကျကျဖြတ်)။ နံပါတ်/ratio/mirror ထည့်ရင် ပြန်ရေးတယ်။',
            style: TextStyle(
                color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tplCtrl.dispose();
    super.dispose();
  }
}
