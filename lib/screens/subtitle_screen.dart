import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/ffmpeg_service.dart';
import '../widgets/job_runner.dart';

/// Myanmar Subtitle — burn an .srt file into a video with Myanmar font.
class SubtitleScreen extends StatefulWidget {
  const SubtitleScreen({super.key});

  @override
  State<SubtitleScreen> createState() => _SubtitleScreenState();
}

class _SubtitleScreenState extends State<SubtitleScreen> {
  String? _videoPath;
  String? _srtPath;
  MediaInfo? _info;
  bool _loading = false;
  double _fontSize = 22;

  Future<void> _pickVideo() async {
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

  Future<void> _pickSrt() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'vtt'],
    );
    if (files.isEmpty || files.single.path == null) return;
    var path = files.single.path!;
    // Convert vtt → srt if needed (strip header).
    if (path.toLowerCase().endsWith('.vtt')) {
      final content = await File(path).readAsString();
      final lines = content.split('\n');
      final srt = lines
          .where((l) => !l.trim().startsWith('WEBVTT') && !l.trim().startsWith('NOTE'))
          .join('\n')
          .replaceAllMapped(
              RegExp(r'(\d{2}:\d{2}:\d{2})\.(\d{3})'),
              (m) => '${m[1]},${m[2]}');
      path = await FfmpegService.writeSrt(srt);
    }
    setState(() => _srtPath = path);
  }

  void _start() {
    final inPath = _videoPath;
    final srt = _srtPath;
    if (inPath == null || srt == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JobRunner(
        title: 'Myanmar Subtitle',
        run: (onProgress, onLog) async {
          final outDir = await FfmpegService.outDir();
          final font = await FfmpegService.fontPath();
          final ts = DateTime.now().millisecondsSinceEpoch;
          final out = '${outDir.path}/subtitled_$ts.mp4';
          final style =
              "FontName=Noto Sans Myanmar,FontSize=${_fontSize.round()},"
              "PrimaryColour=&H00FFFFFF,OutlineColour=&H80000000,"
              "BorderStyle=1,Outline=1,Shadow=0,"
              "MarginV=28,Alignment=2";
          final vf =
              "subtitles=${FfmpegService.esc(srt)}:fontsdir=${FfmpegService.esc(font.replaceAll(RegExp(r'/[^/]+$'), ''))}:force_style='$style'";
          final cmd =
              '-y -i ${FfmpegService.q(inPath)} -vf "$vf" '
              '-c:v libx264 -crf 23 -preset veryfast -c:a copy '
              '${FfmpegService.q(out)}';
          final rc = await FfmpegService.runJob(
            command: cmd,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('💬 Myanmar Subtitle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ElevatedButton.icon(
            onPressed: _pickVideo,
            icon: const Icon(Icons.video_library),
            label: const Text('Video ရွေးပါ'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _pickSrt,
            icon: const Icon(Icons.closed_caption),
            label: const Text('SRT / VTT file ရွေးပါ'),
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (_videoPath != null)
            Card(
                child: ListTile(
                    dense: true,
                    title: Text(_videoPath!.split('/').last,
                        overflow: TextOverflow.ellipsis))),
          if (_srtPath != null)
            Card(
                child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.subtitles),
                    title: Text(_srtPath!.split('/').last,
                        overflow: TextOverflow.ellipsis))),
          const SizedBox(height: 16),
          Text('စာလုံးအရွယ်: ${_fontSize.round()}'),
          Slider(
            min: 14,
            max: 40,
            value: _fontSize,
            onChanged: (v) => setState(() => _fontSize = v),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: (_videoPath != null && _srtPath != null && !_loading)
                ? _start
                : null,
            icon: const Icon(Icons.subtitles),
            label: const Text('စာတန်းထိုးမယ်'),
          ),
          const SizedBox(height: 8),
          const Text(
            'မြန်မာဖောင့် (Noto Sans Myanmar) အထဲမှာ ပါပြီးသား။ SRT မရှိရင် Recap Translate နဲ့ ထုတ်လို့ရတယ်။',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
