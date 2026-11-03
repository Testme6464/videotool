import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/material.dart' show Colors;

import 'ffmpeg_service.dart';

/// A rectangular blur mask (for hiding watermarks/logos in source video).
/// All values are fractions 0..1 of frame size.
class BlurMask {
  bool enabled;
  double x, y, w, h; // fractions
  BlurMask(
      {this.enabled = false,
      this.x = 0.0,
      this.y = 0.0,
      this.w = 0.25,
      this.h = 0.12});
}

class DubConfig {
  // inputs
  String videoPath;
  String ttsPath;
  String? srtPath;
  double videoSec;
  double ttsSec;
  // video fx
  bool mirror = false;
  String ratio = '9:16'; // 9:16, 16:9, 1:1, 4:3, original
  String bgMode = 'blur'; // blur, image, pad
  String? bgImagePath;
  final masks = [BlurMask(), BlurMask()];
  bool smartSync = true;
  double origVolume = 0.3; // 0..1 ; -1 = replace with TTS only
  String resolution = '720p'; // 720p, 1080p
  // text overlays
  String titleText = '';
  double titleSize = 44;
  Color titleColor = Colors.white;
  double titleOpacity = 1.0;
  String wmText = '';
  double wmOpacity = 0.8;
  // subtitles
  bool autoSubtitle = true;
  Color subColor = Colors.white;
  bool subBg = true;
  Color subBgColor = Colors.black;
  double subBgOpacity = 0.6;
  double subFontSize = 28;

  DubConfig({
    required this.videoPath,
    required this.ttsPath,
    required this.videoSec,
    required this.ttsSec,
  });
}

/// Builds and runs the full dubbing render in one FFmpeg pass.
class DubRenderer {
  /// Escape for FFmpeg filter arguments.
  static String esc(String s) =>
      s.replaceAll('\\', '\\\\').replaceAll(':', '\\:').replaceAll("'", "\\'");

  /// Flutter Color → ASS &HAABBGGRR (with opacity 0..1).
  static String ass(Color c, [double opacity = 1.0]) {
    final a = (255 * (1 - opacity)).round().clamp(0, 255);
    String hx(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    // ignore: deprecated_member_use
    return '&H${hx(a)}${hx(c.blue)}${hx(c.green)}${hx(c.red)}';
  }

  /// Runs the render. Returns output path.
  static Future<String> render(
    DubConfig c, {
    required void Function(double) onProgress,
    required void Function(String) onLog,
  }) async {
    final outDir = await FfmpegService.outDir();
    final font = await FfmpegService.fontPath();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final out = '${outDir.path}/dubbed_$ts.mp4';

    final longEdge = c.resolution == '1080p' ? 1920 : 1280;
    // Target canvas per ratio.
    int cw, ch;
    switch (c.ratio) {
      case '9:16':
        cw = c.resolution == '1080p' ? 1080 : 720;
        ch = c.resolution == '1080p' ? 1920 : 1280;
        break;
      case '1:1':
        cw = ch = c.resolution == '1080p' ? 1080 : 720;
        break;
      case '4:3':
        cw = c.resolution == '1080p' ? 1440 : 960;
        ch = c.resolution == '1080p' ? 1080 : 720;
        break;
      case '16:9':
        cw = c.resolution == '1080p' ? 1920 : 1280;
        ch = c.resolution == '1080p' ? 1080 : 720;
        break;
      default: // original
        cw = 0;
        ch = 0;
    }

    final filters = <String>[];
    var label = '0:v';
    var n = 0;
    String next() => 'v${n++}';

    // 1. Blur masks.
    for (final m in c.masks) {
      if (!m.enabled) continue;
      final bm = 'bm$n';
      final v = next();
      filters.add(
          '[$label]crop=w=iw*${m.w}:h=ih*${m.h}:x=iw*${m.x}:y=ih*${m.y},boxblur=18[$bm]');
      filters.add('[$label][$bm]overlay=x=W*${m.x}:y=H*${m.y}[$v]');
      label = v;
    }

    // 2. Mirror.
    if (c.mirror) {
      final v = next();
      filters.add('[$label]hflip[$v]');
      label = v;
    }

    // 3. Smart-sync speed factor (video sped up to catch TTS, max 1.25x).
    double speed = 1.0;
    if (c.smartSync && c.ttsSec > c.videoSec && c.videoSec > 0) {
      speed = (c.ttsSec / c.videoSec).clamp(1.0, 1.25);
    }
    if (speed > 1.0) {
      final v = next();
      filters.add(
          '[$label]setpts=PTS/${speed.toStringAsFixed(3)}[$v]');
      label = v;
    }

    // 4. Scale long edge + ratio canvas.
    if (cw > 0) {
      final v = next();
      // Fit inside canvas first.
      filters.add(
          '[$label]scale=w=\'if(gt(iw,ih),$cw,-2)\':h=\'if(gt(iw,ih),-2,$ch)\'[$v]');
      label = v;
      final v2 = next();
      if (c.bgMode == 'blur') {
        filters.add(
            '[$label]split[a][b];[a]scale=$cw:$ch:force_original_aspect_ratio=increase,crop=$cw:$ch,boxblur=22[bg];[b][bg]overlay=(W-w)/2:(H-h)/2,format=yuv420p[$v2]');
      } else {
        // pad (image bg would need extra input; pad is the safe default)
        filters.add(
            '[$label]pad=$cw:$ch:(ow-iw)/2:(oh-ih)/2:color=black,format=yuv420p[$v2]');
      }
      label = v2;
    } else {
      final v = next();
      filters.add(
          '[$label]scale=w=\'if(gt(iw,ih),$longEdge,-2)\':h=\'if(gt(iw,ih),-2,$longEdge)\',format=yuv420p[$v]');
      label = v;
    }

    // 5. Pad video tail if TTS is longer (clone last frame).
    final vidOutSec = c.videoSec / speed;
    if (c.ttsSec > vidOutSec) {
      final v = next();
      final pad = (c.ttsSec - vidOutSec).toStringAsFixed(2);
      filters.add('[$label]tpad=stop_mode=clone:stop_duration=$pad[$v]');
      label = v;
    }

    // 6. Subtitles.
    if (c.autoSubtitle && c.srtPath != null) {
      final v = next();
      final fontsDir = font.replaceAll(RegExp(r'/[^/]+$'), '');
      final style = 'FontName=Noto Sans Myanmar,'
          'FontSize=${c.subFontSize.round()},'
          'PrimaryColour=${ass(c.subColor)},'
          '${c.subBg ? 'BackColour=${ass(c.subBgColor, c.subBgOpacity)},BorderStyle=3,' : 'BorderStyle=1,Outline=1,'}'
          'Shadow=0,MarginV=30,Alignment=2';
      filters.add(
          '[$label]subtitles=${esc(c.srtPath!)}:fontsdir=${esc(fontsDir)}:force_style=\'$style\'[$v]');
      label = v;
    }

    // 7. Title.
    if (c.titleText.trim().isNotEmpty) {
      final v = next();
      filters.add(
          '[$label]drawtext=fontfile=${esc(font)}:text=${esc(c.titleText.trim())}:'
          'fontsize=${c.titleSize.round()}:fontcolor=${ass(c.titleColor, c.titleOpacity)}:'
          'borderw=2:bordercolor=${ass(const Color(0xFF000000), 0.8)}:'
          'x=(w-text_w)/2:y=70[$v]');
      label = v;
    }

    // 8. Watermark.
    if (c.wmText.trim().isNotEmpty) {
      final v = next();
      filters.add(
          '[$label]drawtext=fontfile=${esc(font)}:text=${esc(c.wmText.trim())}:'
          'fontsize=26:fontcolor=${ass(const Color(0xFFFFFFFF), c.wmOpacity)}:'
          'x=w-text_w-24:y=h-text_h-24[$v]');
      label = v;
    }

    final vf = filters.join(';');

    // Audio: TTS (+ original mixed at volume, or replace).
    final String af;
    final String maps;
    if (c.origVolume < 0) {
      af = '[1:a]aresample=44100,volume=1.0[aout]';
      maps = '-map "[${label.isEmpty ? 'v' : label}]" -map "[aout]"';
    } else {
      af = '[0:a]volume=${c.origVolume.toStringAsFixed(2)},aresample=44100[a0];'
          '[1:a]aresample=44100,volume=1.0[a1];'
          '[a0][a1]amix=inputs=2:duration=longest:dropout_transition=0[aout]';
      maps = '-map "[$label]" -map "[aout]"';
    }

    final totalMs = (c.ttsSec > vidOutSec ? c.ttsSec : vidOutSec) * 1000;
    final cmd = '-y -i ${FfmpegService.q(c.videoPath)} '
        '-i ${FfmpegService.q(c.ttsPath)} '
        '-filter_complex "$vf;$af" $maps '
        '-c:v libx264 -crf 23 -preset veryfast -c:a aac -b:a 128k '
        '-movflags +faststart ${FfmpegService.q(out)}';

    onLog('Render start…');
    final rc = await FfmpegService.runJob(
      command: cmd,
      totalDurationMs: totalMs,
      onProgress: onProgress,
      onLog: onLog,
    );
    if (rc != 0) throw Exception('Render failed (code $rc)');
    if (!await File(out).exists()) throw Exception('Output not created');
    return out;
  }
}
