import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/ffmpeg_service.dart';

/// Shared running UI: progress bar, cancel, log view, share outputs.
class JobRunner extends StatefulWidget {
  final String title;
  final Future<List<String>> Function(
    void Function(double) onProgress,
    void Function(String) onLog,
  ) run;

  const JobRunner({super.key, required this.title, required this.run});

  @override
  State<JobRunner> createState() => _JobRunnerState();
}

class _JobRunnerState extends State<JobRunner> {
  double _progress = 0;
  final List<String> _logs = [];
  bool _running = true;
  bool _done = false;
  List<String> _outputs = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final outs = await widget.run(
        (p) => mounted ? setState(() => _progress = p) : null,
        (line) {
          _logs.add(line);
          if (_logs.length > 400) _logs.removeAt(0);
          if (mounted) setState(() {});
        },
      );
      if (!mounted) return;
      setState(() {
        _running = false;
        _done = true;
        _outputs = outs;
        _progress = 1.0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _cancel() async {
    await FfmpegService.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_running) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text('${(_progress * 100).toStringAsFixed(1)}%'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _cancel,
                icon: const Icon(Icons.stop),
                label: const Text('ရပ်မယ်'),
              ),
            ],
            if (_done) ...[
              const Icon(Icons.check_circle,
                  color: Colors.green, size: 48),
              const SizedBox(height: 8),
              const Text('ပြီးပါပြီ ✅',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18)),
              const SizedBox(height: 12),
              for (final o in _outputs)
                Card(
                  child: ListTile(
                    dense: true,
                    title: Text(o.split('/').last,
                        overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.share),
                      onPressed: () => SharePlus.instance.share(
                        ShareParams(files: [XFile(o)]),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('ပြန်မယ်'),
              ),
            ],
            if (_error != null) ...[
              const Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('ပြန်မယ်'),
              ),
            ],
            const SizedBox(height: 12),
            const Text('Log',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (_, i) => Text(
                    _logs[i],
                    style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 11,
                        fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
