import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/ffmpeg_service.dart';
import '../widgets/job_runner.dart';

/// Fruit Story — images + Ken Burns motion + optional audio/narration
/// → animated story video.
class FruitStoryScreen extends StatefulWidget {
  const FruitStoryScreen({super.key});

  @override
  State<FruitStoryScreen> createState() => _FruitStoryScreenState();
}

class _FruitStoryScreenState extends State<FruitStoryScreen> {
  final List<String> _images = [];
  String? _audioPath;
  double _secPerImage = 4;
  final _captionCtrl = TextEditingController();

  Future<void> _pickImages() async {
    final files = await ImagePicker().pickMultiImage();
    if (files.isEmpty) return;
    setState(() => _images.addAll(files.map((f) => f.path)));
  }

  Future<void> _pickAudio() async {
    final files =
        await FilePicker.pickFiles(type: FileType.audio);
    if (files.isEmpty || files.single.path == null) return;
    setState(() => _audioPath = files.single.path);
  }

  void _start() {
    if (_images.isEmpty) return;
    final caption = _captionCtrl.text.trim();
    final audio = _audioPath;
    final per = _secPerImage;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JobRunner(
        title: 'Fruit Story',
        run: (onProgress, onLog) async {
          final outDir = await FfmpegService.outDir();
          final ts = DateTime.now().millisecondsSinceEpoch;
          final font = await FfmpegService.fontPath();
          final clips = <String>[];

          // One zoompan clip per image (alternate zoom in/out).
          for (var i = 0; i < _images.length; i++) {
            final clip = '${outDir.path}/fruit_${ts}_$i.mp4';
            final frames = (per * 30).round();
            final zoom = i.isEven
                ? 'zoom+0.0015'
                : 'max(zoom-0.0015,1.0)';
            String esc(String s) => s
                .replaceAll('\\', '\\\\')
                .replaceAll(':', '\\:')
                .replaceAll("'", "\\'");
            var vf =
                'scale=1280:720:force_original_aspect_ratio=increase,'
                'crop=1280:720,'
                'zoompan=z=$zoom:d=$frames:s=1280x720:fps=30,'
                'format=yuv420p';
            if (caption.isNotEmpty) {
              vf += ",drawtext=fontfile=${esc(font)}:text='${esc(caption)}':"
                  'fontsize=40:fontcolor=white:borderw=2:bordercolor=black:'
                  'x=(w-text_w)/2:y=h-90';
            }
            final rc = await FfmpegService.runJob(
              command: '-y -loop 1 -i ${FfmpegService.q(_images[i])} '
                  '-vf "$vf" -t ${per.toStringAsFixed(1)} -c:v libx264 '
                  '-crf 23 -preset veryfast ${FfmpegService.q(clip)}',
              totalDurationMs: per * 1000,
              onProgress: (p) => onProgress((i + p) / _images.length / 2),
              onLog: onLog,
            );
            if (rc != 0) throw Exception('Image ${i + 1} failed');
            clips.add(clip);
          }

          // Concat clips.
          final listFile = File('${outDir.path}/fruit_list_$ts.txt');
          await listFile.writeAsString(
              clips.map((c) => "file '$c'").join('\n'));
          final silent = '${outDir.path}/fruit_silent_$ts.mp4';
          var rc = await FfmpegService.runJob(
            command:
                '-y -f concat -safe 0 -i ${FfmpegService.q(listFile.path)} '
                '-c copy ${FfmpegService.q(silent)}',
            totalDurationMs: _images.length * per * 1000,
            onProgress: (p) => onProgress(0.5 + p / 4),
            onLog: onLog,
          );
          if (rc != 0) throw Exception('Concat failed');

          final out = '${outDir.path}/fruit_story_$ts.mp4';
          if (audio != null) {
            rc = await FfmpegService.runJob(
              command: '-y -i ${FfmpegService.q(silent)} '
                  '-i ${FfmpegService.q(audio)} -c:v copy -c:a aac -b:a 128k '
                  '-shortest -movflags +faststart ${FfmpegService.q(out)}',
              totalDurationMs: _images.length * per * 1000,
              onProgress: (p) => onProgress(0.75 + p / 4),
              onLog: onLog,
            );
          } else {
            rc = await FfmpegService.runJob(
              command: '-y -i ${FfmpegService.q(silent)} -c copy '
                  '${FfmpegService.q(out)}',
              totalDurationMs: _images.length * per * 1000,
              onProgress: (p) => onProgress(0.75 + p / 4),
              onLog: onLog,
            );
          }
          if (rc != 0) throw Exception('Mux failed');
          return [out];
        },
      ),
    ));
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🍓 Fruit Story')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ElevatedButton.icon(
            onPressed: _pickImages,
            icon: const Icon(Icons.photo_library),
            label: const Text('ပုံတွေ ရွေးပါ (အများကြီး)'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _pickAudio,
            icon: const Icon(Icons.audio_file),
            label: const Text('နောက်ခံအသံ (optional)'),
          ),
          const SizedBox(height: 12),
          if (_images.isNotEmpty)
            SizedBox(
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length,
                itemBuilder: (_, i) => Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Image.file(File(_images[i]),
                          width: 90, height: 90, fit: BoxFit.cover),
                    ),
                    Positioned(
                      right: 4,
                      top: 0,
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _images.removeAt(i)),
                        child: const Icon(Icons.cancel,
                            color: Colors.red, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_audioPath != null)
            Card(
                child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.audiotrack),
                    title: Text(_audioPath!.split('/').last,
                        overflow: TextOverflow.ellipsis))),
          const SizedBox(height: 12),
          TextField(
            controller: _captionCtrl,
            decoration: const InputDecoration(
              labelText: 'စာသား (ပုံတိုင်းအောက်မှာ ပေါ်မယ်, optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text('တပုံ ${_secPerImage.round()} စက္ကန့်'),
          Slider(
              min: 2,
              max: 10,
              divisions: 8,
              value: _secPerImage,
              onChanged: (v) => setState(() => _secPerImage = v)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _images.isNotEmpty ? _start : null,
            icon: const Icon(Icons.movie),
            label: const Text('Story video ဖန်တီးမယ်'),
          ),
          const SizedBox(height: 8),
          const Text(
            'ပုံတွေကို zoom in/out motion နဲ့ video လုပ်တယ်။ Character animation အပြည့်အဝမဟုတ်ပါ။',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
