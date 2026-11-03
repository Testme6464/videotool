import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/ffmpeg_service.dart';
import '../widgets/job_runner.dart';

/// Dhamma Studio — background image/GIF + Dhamma audio + title text
/// → long-form video.
class DhammaScreen extends StatefulWidget {
  const DhammaScreen({super.key});

  @override
  State<DhammaScreen> createState() => _DhammaScreenState();
}

class _DhammaScreenState extends State<DhammaScreen> {
  String? _audioPath;
  String? _imagePath;
  final _titleCtrl = TextEditingController();
  double _audioLenSec = 0;
  bool _loading = false;

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

  Future<void> _pickImage() async {
    final f =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f == null) return;
    setState(() => _imagePath = f.path);
  }

  void _start() {
    final audio = _audioPath;
    final image = _imagePath;
    if (audio == null || image == null) return;
    final title = _titleCtrl.text.trim();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JobRunner(
        title: 'Dhamma Studio',
        run: (onProgress, onLog) async {
          final outDir = await FfmpegService.outDir();
          final font = await FfmpegService.fontPath();
          final ts = DateTime.now().millisecondsSinceEpoch;
          final out = '${outDir.path}/dhamma_$ts.mp4';

          // Escape text for drawtext.
          String esc(String s) => s
              .replaceAll('\\', '\\\\')
              .replaceAll(':', '\\:')
              .replaceAll("'", "\\'")
              .replaceAll('\n', ' ');
          final vf = title.isEmpty
              ? 'scale=1280:720:force_original_aspect_ratio=decrease,'
                  'pad=1280:720:(ow-iw)/2:(oh-ih)/2,format=yuv420p'
              : 'scale=1280:720:force_original_aspect_ratio=decrease,'
                  'pad=1280:720:(ow-iw)/2:(oh-ih)/2,format=yuv420p,'
                  "drawtext=fontfile=${esc(font)}:text='${esc(title)}':"
                  'fontsize=44:fontcolor=white:borderw=2:bordercolor=black:'
                  'x=(w-text_w)/2:y=64';

          final cmd =
              '-y -loop 1 -i ${FfmpegService.q(image)} '
              '-i ${FfmpegService.q(audio)} '
              '-vf "$vf" -c:v libx264 -crf 23 -preset veryfast '
              '-c:a aac -b:a 128k -shortest -movflags +faststart '
              '${FfmpegService.q(out)}';
          final rc = await FfmpegService.runJob(
            command: cmd,
            totalDurationMs: _audioLenSec * 1000,
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
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🙏 Dhamma Studio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ElevatedButton.icon(
            onPressed: _pickAudio,
            icon: const Icon(Icons.audio_file),
            label: const Text('တရားအသံ (audio) ရွေးပါ'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.image),
            label: const Text('Background ပုံ ရွေးပါ'),
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (_audioPath != null)
            Card(
                child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.audiotrack),
                    title: Text(_audioPath!.split('/').last,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${(_audioLenSec / 60).toStringAsFixed(1)} မိနစ်'))),
          if (_imagePath != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Image.file(File(_imagePath!),
                    height: 140, fit: BoxFit.cover),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'ခေါင်းစဉ် (ဥပမာ: တရားတော်)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: (_audioPath != null && _imagePath != null && !_loading)
                ? _start
                : null,
            icon: const Icon(Icons.movie),
            label: const Text('Video ဖန်တီးမယ်'),
          ),
          const SizedBox(height: 8),
          const Text(
            'အသံအရှည်အတိုင်း video ထွက်မယ် (720p)။ ပုံကို loop လုပ်ထားတယ်။',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
