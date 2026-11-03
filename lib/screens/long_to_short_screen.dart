import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/ffmpeg_service.dart';
import '../widgets/job_runner.dart';

/// Long to Short — split a long video into N clips cropped to 9:16.
class LongToShortScreen extends StatefulWidget {
  const LongToShortScreen({super.key});

  @override
  State<LongToShortScreen> createState() => _LongToShortScreenState();
}

class _LongToShortScreenState extends State<LongToShortScreen> {
  String? _videoPath;
  MediaInfo? _info;
  bool _loading = false;
  double _clipCount = 3;
  double _clipLenSec = 45;

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

  void _start() {
    final inPath = _videoPath;
    final info = _info;
    if (inPath == null || info == null) return;
    final n = _clipCount.round();
    final len = _clipLenSec;
    final totalSec = info.durationMs / 1000;
    // Evenly spaced start times.
    final starts = List<double>.generate(n, (i) {
      if (n == 1) return 0.0;
      final maxStart = (totalSec - len).clamp(0.0, totalSec);
      return (maxStart * i / (n - 1)).clamp(0.0, maxStart);
    });

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JobRunner(
        title: 'Long to Short',
        run: (onProgress, onLog) async {
          final outDir = await FfmpegService.outDir();
          final ts = DateTime.now().millisecondsSinceEpoch;
          final outs = <String>[];
          for (var i = 0; i < starts.length; i++) {
            final out = '${outDir.path}/short_${ts}_${i + 1}.mp4';
            // Center-crop to 9:16, scale to 720x1280.
            const vf =
                'crop=ih*9/16:ih,scale=720:1280,format=yuv420p';
            final cmd =
                '-y -ss ${starts[i].toStringAsFixed(1)} -t ${len.toStringAsFixed(0)} '
                '-i ${FfmpegService.q(inPath)} -vf "$vf" '
                '-c:v libx264 -crf 23 -preset veryfast -c:a aac -b:a 128k '
                '${FfmpegService.q(out)}';
            final rc = await FfmpegService.runJob(
              command: cmd,
              totalDurationMs: len * 1000,
              onProgress: (p) => onProgress((i + p) / starts.length),
              onLog: onLog,
            );
            if (rc != 0) throw Exception('Clip ${i + 1} failed (code $rc)');
            outs.add(out);
          }
          return outs;
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📱 Long to Short')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ElevatedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.video_library),
            label: const Text('Video ရှည် ရွေးပါ'),
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (_info != null)
            Card(
              child: ListTile(
                title: Text(_videoPath!.split('/').last,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${(_info!.durationMs / 60000).toStringAsFixed(1)} မိနစ်'),
              ),
            ),
          const SizedBox(height: 16),
          Text('Clip အရေအတွက်: ${_clipCount.round()}'),
          Slider(
              min: 1,
              max: 10,
              divisions: 9,
              value: _clipCount,
              onChanged: (v) => setState(() => _clipCount = v)),
          Text('တပိုင်း ${_clipLenSec.round()} စက္ကန့်'),
          Slider(
              min: 15,
              max: 120,
              divisions: 21,
              value: _clipLenSec,
              onChanged: (v) => setState(() => _clipLenSec = v)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: (_videoPath != null && !_loading) ? _start : null,
            icon: const Icon(Icons.cut),
            label: const Text('Shorts တွေထုတ်မယ်'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Video ထဲက အညီအမျှဖြန့်ပြီး အပိုင်းတွေ ဖြတ်မယ်။ 9:16 (720x1280) အလယ် crop လုပ်တယ်။',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
