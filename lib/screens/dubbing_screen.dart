import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../services/ffmpeg_service.dart';
import '../widgets/job_runner.dart';

/// Dubbing Studio — record voiceover with mic, then mix/replace
/// the video's audio (volume + delay adjustable).
class DubbingScreen extends StatefulWidget {
  const DubbingScreen({super.key});

  @override
  State<DubbingScreen> createState() => _DubbingScreenState();
}

class _DubbingScreenState extends State<DubbingScreen> {
  String? _videoPath;
  MediaInfo? _info;
  final _rec = AudioRecorder();
  bool _recording = false;
  String? _voicePath;
  Duration _recDur = Duration.zero;
  Timer? _timer;
  double _voiceVol = 1.0;
  double _origVol = 0.25;
  double _delaySec = 0;
  bool _replace = false;

  Future<void> _pickVideo() async {
    final f =
        await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (f == null) return;
    final info = await FfmpegService.getMediaInfo(f.path);
    setState(() {
      _videoPath = f.path;
      _info = info;
    });
  }

  Future<void> _toggleRec() async {
    if (_recording) {
      final path = await _rec.stop();
      _timer?.cancel();
      setState(() {
        _recording = false;
        if (path != null) _voicePath = path;
      });
      return;
    }
    if (!await _rec.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Mic permission လိုပါတယ်')));
      }
      return;
    }
    final dir = await FfmpegService.outDir();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    setState(() {
      _recording = true;
      _recDur = Duration.zero;
      _voicePath = null;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _recDur += const Duration(seconds: 1));
    });
  }

  void _start() {
    final inPath = _videoPath;
    final voice = _voicePath;
    if (inPath == null || voice == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => JobRunner(
        title: 'Dubbing Studio',
        run: (onProgress, onLog) async {
          final outDir = await FfmpegService.outDir();
          final ts = DateTime.now().millisecondsSinceEpoch;
          final out = '${outDir.path}/dubbed_$ts.mp4';
          final delayMs = (_delaySec * 1000).round();
          final String filter;
          if (_replace) {
            filter =
                '[1:a]adelay=$delayMs|$delayMs,volume=${_voiceVol.toStringAsFixed(2)}[v]';
          } else {
            filter = '[0:a]volume=${_origVol.toStringAsFixed(2)}[a0];'
                '[1:a]adelay=$delayMs|$delayMs,'
                'volume=${_voiceVol.toStringAsFixed(2)}[a1];'
                '[a0][a1]amix=inputs=2:duration=longest[aout]';
          }
          final map = _replace ? '-map 0:v -map "[v]"' : '-map 0:v -map "[aout]"';
          final cmd =
              '-y -i ${FfmpegService.q(inPath)} -i ${FfmpegService.q(voice)} '
              '-filter_complex "$filter" $map '
              '-c:v copy -c:a aac -b:a 128k -shortest '
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

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _timer?.cancel();
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🎙️ Dubbing Studio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ElevatedButton.icon(
            onPressed: _pickVideo,
            icon: const Icon(Icons.video_library),
            label: const Text('Video ရွေးပါ'),
          ),
          if (_videoPath != null)
            Card(
                child: ListTile(
                    dense: true,
                    title: Text(_videoPath!.split('/').last,
                        overflow: TextOverflow.ellipsis))),
          const SizedBox(height: 16),
          const Text('အသံသွင်းရန်',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _toggleRec,
                icon: Icon(_recording ? Icons.stop : Icons.mic),
                label: Text(_recording ? 'ရပ်မယ်' : 'စသွင်းမယ်'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _recording ? Colors.red : null,
                ),
              ),
              const SizedBox(width: 12),
              if (_recording)
                Text(_fmt(_recDur),
                    style: const TextStyle(
                        fontSize: 20, color: Colors.red)),
              if (_voicePath != null && !_recording)
                const Text('✅ သွင်းပြီးပြီ',
                    style: TextStyle(color: Colors.green)),
            ],
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('မူရင်းအသံ အစားထိုးမယ်'),
            subtitle: const Text('ပိတ်ထားရင် မူရင်းအသံနဲ့ ရောမယ်'),
            value: _replace,
            onChanged: (v) => setState(() => _replace = v),
          ),
          if (!_replace) ...[
            Text('မူရင်းအသံ အသံကျယ်: ${(_origVol * 100).round()}%'),
            Slider(
                value: _origVol,
                min: 0,
                max: 1,
                onChanged: (v) => setState(() => _origVol = v)),
          ],
          Text('ကိုယ့်အသံ အသံကျယ်: ${(_voiceVol * 100).round()}%'),
          Slider(
              value: _voiceVol,
              min: 0,
              max: 2,
              onChanged: (v) => setState(() => _voiceVol = v)),
          Text('နောက်ကျ/စောချိန်: ${_delaySec.toStringAsFixed(1)} စက္ကန့်'),
          Slider(
              value: _delaySec,
              min: 0,
              max: 10,
              divisions: 100,
              onChanged: (v) => setState(() => _delaySec = v)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: (_videoPath != null && _voicePath != null && !_recording)
                ? _start
                : null,
            icon: const Icon(Icons.audiotrack),
            label: const Text('Dub လုပ်မယ်'),
          ),
        ],
      ),
    );
  }
}
