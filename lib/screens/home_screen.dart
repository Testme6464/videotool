import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/ffmpeg_service.dart';

enum JobKind { denoise, compress, extractAudio }

extension JobKindLabel on JobKind {
  String get label {
    switch (this) {
      case JobKind.denoise:
        return 'အသံဆူညံမှုဖယ်ရှားမယ်';
      case JobKind.compress:
        return 'ဗီဒီယိုချုံ့မယ်';
      case JobKind.extractAudio:
        return 'အသံပဲထုတ်မယ်';
    }
  }

  String get desc {
    switch (this) {
      case JobKind.denoise:
        return 'RNNoise နဲ့ နောက်ခံဆူညံသံဖယ်မယ် (ရုပ်ထွက်မပြောင်း)';
      case JobKind.compress:
        return 'H.264 CRF 28 နဲ့ ဖိုင်အရွယ်သေးအောင်ချုံ့မယ်';
      case JobKind.extractAudio:
        return 'အသံလမ်းကြောင်းပဲ m4a အဖြစ်ထုတ်မယ်';
    }
  }

  IconData get icon {
    switch (this) {
      case JobKind.denoise:
        return Icons.graphic_eq;
      case JobKind.compress:
        return Icons.compress;
      case JobKind.extractAudio:
        return Icons.audio_file;
    }
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _picker = ImagePicker();

  String? _videoPath;
  MediaInfo? _info;
  bool _busy = false;
  bool _running = false;
  double _progress = 0;
  String _status = 'ဗီဒီယိုရွေးပါ';
  String? _outputPath;
  final List<String> _logs = [];

  void _appendLog(String line) {
    if (!mounted || line.trim().isEmpty) return;
    setState(() {
      _logs.add(line);
      if (_logs.length > 80) {
        _logs.removeRange(0, _logs.length - 80);
      }
    });
  }

  Future<void> _pickVideo() async {
    if (_busy || _running) return;
    try {
      await Permission.videos.request();
    } catch (_) {
      // System picker grants one-time read access anyway.
    }
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() {
      _busy = true;
      _videoPath = picked.path;
      _info = null;
      _outputPath = null;
      _progress = 0;
      _logs.clear();
      _status = 'ဖတ်နေတယ်…';
    });

    final info = await FfmpegService.getMediaInfo(picked.path);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _info = info;
      _status = info == null
          ? 'ဗီဒီယိုဖတ်လို့မရဘူး'
          : 'အဆင်သင့် — လုပ်ဆောင်ချက်ရွေးပါ';
    });
  }

  String _outputName(JobKind kind) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return switch (kind) {
      JobKind.denoise => 'denoised_$ts.mp4',
      JobKind.compress => 'small_$ts.mp4',
      JobKind.extractAudio => 'audio_$ts.m4a',
    };
  }

  Future<String> _buildCommand(
      JobKind kind, String input, String output) async {
    switch (kind) {
      case JobKind.denoise:
        final model = await FfmpegService.modelPath();
        return '-y -i "$input" -af arnndn=m="$model" '
            '-c:v copy -c:a aac -b:a 128k "$output"';
      case JobKind.compress:
        return '-y -i "$input" -c:v libx264 -crf 28 -preset veryfast '
            '-c:a aac -b:a 128k "$output"';
      case JobKind.extractAudio:
        return '-y -i "$input" -vn -c:a aac -b:a 128k "$output"';
    }
  }

  Future<void> _runJob(JobKind kind) async {
    final input = _videoPath;
    final info = _info;
    if (input == null || info == null || _running || _busy) return;

    setState(() {
      _running = true;
      _progress = 0;
      _outputPath = null;
      _logs.clear();
      _status = 'လုပ်ဆောင်နေတယ်…';
    });
    await WakelockPlus.enable();

    try {
      final outDir = await FfmpegService.outDir();
      final output = '${outDir.path}/${_outputName(kind)}';
      final command = await _buildCommand(kind, input, output);
      _appendLog('\$ ffmpeg $command');

      final rc = await FfmpegService.runJob(
        command: command,
        totalDurationMs: info.durationMs,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onLog: _appendLog,
      );

      if (!mounted) return;
      if (rc == 0) {
        setState(() {
          _outputPath = output;
          _progress = 1;
          _status = 'ပြီးပါပြီ ✅';
        });
      } else if (rc == 255) {
        setState(() => _status = 'ရပ်လိုက်တယ်');
      } else {
        setState(() => _status = 'အမှားဖြစ်တယ် (code $rc) — log ကြည့်ပါ');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'အမှားဖြစ်တယ်: $e');
    } finally {
      await WakelockPlus.disable();
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _cancelJob() async {
    await FfmpegService.cancel();
  }

  Future<void> _shareOutput() async {
    final path = _outputPath;
    if (path == null) return;
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], text: 'VideoTool နဲ့လုပ်ထားတာ'),
    );
  }

  String _formatDuration(double ms) {
    final s = (ms / 1000).round();
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  String _formatSize(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    final ready = _videoPath != null && _info != null && !_busy;
    final fileName =
        _videoPath == null ? '' : _videoPath!.split('/').last;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ဗီဒီယိုတူးလ်'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: (_busy || _running) ? null : _pickVideo,
            icon: const Icon(Icons.video_library),
            label: const Text('ဗီဒီယိုရွေးမယ်'),
          ),
          const SizedBox(height: 12),
          if (_videoPath != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.movie),
                title: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: _busy
                    ? const Text('ဖတ်နေတယ်…')
                    : Text(
                        _info == null
                            ? 'ဖတ်လို့မရဘူး'
                            : '${_formatDuration(_info!.durationMs)} • ${_info!.resolution} • ${_formatSize(_info!.sizeBytes)}',
                      ),
              ),
            ),
          const SizedBox(height: 8),
          for (final kind in JobKind.values)
            Card(
              child: ListTile(
                leading: Icon(kind.icon),
                title: Text(kind.label),
                subtitle: Text(kind.desc),
                enabled: ready && !_running,
                onTap: () => _runJob(kind),
              ),
            ),
          const SizedBox(height: 8),
          if (_running) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${(_progress * 100).toStringAsFixed(0)}% — $_status',
                  ),
                ),
                TextButton.icon(
                  onPressed: _cancelJob,
                  icon: const Icon(Icons.stop),
                  label: const Text('ရပ်မယ်'),
                ),
              ],
            ),
          ] else
            Text(_status, style: Theme.of(context).textTheme.bodyMedium),
          if (_outputPath != null) ...[
            const SizedBox(height: 8),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.check_circle),
                title: Text(
                  _outputPath!.split('/').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: const Text('သိမ်းပြီးပြီ'),
                trailing: IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: _shareOutput,
                  tooltip: 'မျှဝေမယ်',
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text('Log', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Container(
            height: 170,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _logs.isEmpty
                ? const Text('—',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 11))
                : ListView.builder(
                    reverse: true,
                    itemCount: _logs.length,
                    itemBuilder: (c, i) => Text(
                      _logs[_logs.length - 1 - i],
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          const Text(
            'FFmpegKit (FFmpeg 6.0) + RNNoise မော်ဒယ်နဲ့ အလုပ်လုပ်တယ်။',
            style: TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
