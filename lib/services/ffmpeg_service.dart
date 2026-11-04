import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Summary of a picked video, read with FFprobe.
class MediaInfo {
  final double durationMs;
  final String resolution;
  final int sizeBytes;
  final bool hasAudio;

  MediaInfo({
    required this.durationMs,
    required this.resolution,
    required this.sizeBytes,
    this.hasAudio = false,
  });
}

/// Thin wrapper around FFmpegKit used by the UI.
class FfmpegService {
  static String? _modelPath;
  static Directory? _outDir;

  /// Copies the bundled RNNoise model into app storage on first use and
  /// returns its absolute path (for the arnndn audio filter).
  static Future<String> modelPath() async {
    if (_modelPath != null) return _modelPath!;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/cb.rnnn');
    if (!await file.exists()) {
      final data = await rootBundle.load('assets/models/cb.rnnn');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    _modelPath = file.path;
    return file.path;
  }

  /// Output folder for processed files.
  static Future<Directory> outDir() async {
    if (_outDir != null) return _outDir!;
    final dir = await getApplicationDocumentsDirectory();
    final out = Directory('${dir.path}/VideoTool');
    if (!await out.exists()) {
      await out.create(recursive: true);
    }
    _outDir = out;
    return out;
  }

  /// Reads duration / resolution / size of [path] with FFprobe.
  /// Returns null when the file cannot be probed.
  static Future<MediaInfo?> getMediaInfo(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = await session.getMediaInformation();
      if (info == null) return null;

      final props = info.getAllProperties();
      final durationSec =
          double.tryParse(props?['duration']?.toString() ?? '') ?? 0;

      String resolution = '';
      bool hasAudio = false;
      final streams = info.getStreams();
      for (final s in streams) {
        final p = s.getAllProperties();
        if (p?['codec_type'] == 'video' && resolution.isEmpty) {
          resolution = '${p?['width']}x${p?['height']}';
        }
        if (p?['codec_type'] == 'audio') hasAudio = true;
      }

      final size = await File(path).length();
      return MediaInfo(
        durationMs: durationSec * 1000,
        resolution: resolution,
        sizeBytes: size,
        hasAudio: hasAudio,
      );
    } catch (_) {
      return null;
    }
  }

  /// Runs an FFmpeg [command] asynchronously.
  ///
  /// [totalDurationMs] is used to turn statistics timestamps into a 0..1
  /// progress value. Returns the FFmpeg return code (0 = success,
  /// 255 = cancelled).
  static Future<int?> runJob({
    required String command,
    required double totalDurationMs,
    required void Function(double progress) onProgress,
    required void Function(String line) onLog,
  }) async {
    final done = Completer<int?>();
    try {
      await FFmpegKit.executeAsync(
        command,
        (session) async {
          final rc = await session.getReturnCode();
          if (!done.isCompleted) done.complete(rc?.getValue());
        },
        (log) => onLog(log.getMessage()),
        (Statistics stats) {
          if (totalDurationMs > 0) {
            final p = stats.getTime() / totalDurationMs;
            onProgress(p.clamp(0.0, 1.0));
          }
        },
      );
    } catch (e) {
      if (!done.isCompleted) done.completeError(e);
    }
    return done.future;
  }

  /// Copies the bundled Myanmar font into app storage for the
  /// subtitles/drawtext filters. Returns its absolute path.
  static String? _fontPath;

  static Future<String> fontPath() async {
    if (_fontPath != null) return _fontPath!;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/NotoSansMyanmar-Regular.ttf');
    if (!await file.exists()) {
      final data =
          await rootBundle.load('assets/fonts/NotoSansMyanmar-Regular.ttf');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    _fontPath = file.path;
    return file.path;
  }

  /// Copies an SRT file's content to a temp .srt path FFmpeg can read.
  static Future<String> writeSrt(String content) async {
    final dir = await outDir();
    final f = File(
        '${dir.path}/sub_${DateTime.now().millisecondsSinceEpoch}.srt');
    await f.writeAsString(content, flush: true);
    return f.path;
  }

  /// Shell-quotes a path for FFmpeg filter args (single-quote escaping).
  static String q(String p) => "'${p.replaceAll("'", r"'\''")}'";

  /// Escape for FFmpeg filter arguments (drawtext text, etc).
  static String esc(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(':', '\\:')
      .replaceAll("'", "\\'")
      .replaceAll(',', '\\,');

  /// Cancels all running FFmpeg sessions.
  static Future<void> cancel() => FFmpegKit.cancel();
}
