import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/ffmpeg_service.dart';
import '../widgets/job_runner.dart';

/// Video Splitter — split a video into N-minute parts.
class SplitterScreen extends StatefulWidget {
  const SplitterScreen({super.key});

  @override
  State<SplitterScreen> createState() => _SplitterScreenState();
}

class _SplitterScreenState extends State<SplitterScreen> {
  String? _videoPath;
  MediaInfo? _info;
  double _minutes = 5;
  bool _loading = false;

  Future<void> _pick() async {
    final f = await ImagePicker()
        .pickVideo(source: ImageSource.gallery);
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
    if (inPath == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JobRunner(
        title: 'Video Splitter',
        run: (onProgress, onLog) async {
          final outDir = await FfmpegService.outDir();
          final ts = DateTime.now().millisecondsSinceEpoch;
          final segSec = (_minutes * 60).round();
          final outPattern =
              '${outDir.path}/split_${ts}_%03d.mp4';
          final cmd =
              '-y -i ${FfmpegService.q(inPath)} -c copy -map 0 '
              '-segment_time $segSec -f segment -reset_timestamps 1 '
              '${FfmpegService.q(outPattern)}';
          final totalMs = _info?.durationMs ?? 0;
          final rc = await FfmpegService.runJob(
            command: cmd,
            totalDurationMs: totalMs,
            onProgress: onProgress,
            onLog: onLog,
          );
          if (rc != 0) throw Exception('FFmpeg failed (code $rc)');
          // Collect produced parts.
          final parts = outDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.contains('split_${ts}_'))
              .map((f) => f.path)
              .toList()
            ..sort();
          return parts;
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('✂️ Video Splitter')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ElevatedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.video_library),
            label: const Text('Video ရွေးပါ'),
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (_info != null)
            Card(
              child: ListTile(
                title: Text(_videoPath!.split('/').last,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${(_info!.durationMs / 60000).toStringAsFixed(1)} မိနစ် · ${_info!.resolution}'),
              ),
            ),
          const SizedBox(height: 16),
          Text('တပိုင်းကို ${_minutes.toStringAsFixed(0)} မိနစ်'),
          Slider(
            min: 1,
            max: 30,
            divisions: 29,
            value: _minutes,
            label: '${_minutes.toStringAsFixed(0)} min',
            onChanged: (v) => setState(() => _minutes = v),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: (_videoPath != null && !_loading) ? _start : null,
            icon: const Icon(Icons.content_cut),
            label: const Text('ဖြတ်မယ်'),
          ),
          const SizedBox(height: 8),
          const Text(
            'မှတ်ချက်: re-encode မလုပ်ဘဲ ဖြတ်တာမို့ မြန်တယ်။ keyframe နေရာတွေမှာပဲ တိတိကျကျ ဖြတ်နိုင်တယ်။',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
