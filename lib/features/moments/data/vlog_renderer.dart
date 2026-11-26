import 'dart:developer' as developer;
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../domain/moment.dart';
import 'moments_repository.dart';

/// A local media file feeding one half of a split-screen slot.
typedef VlogInput = ({String path, bool isVideo});

/// Output is 720x1280 portrait: each spouse gets a 720x640 half.
const _w = 720, _half = 640, _fps = 30;

/// FFmpeg arguments for one split-screen segment (partner top, you bottom).
/// A missing half becomes a dark panel; photos are held for the whole slot.
/// Pure, so it is unit-tested.
List<String> slotArgs({
  required VlogInput? top,
  required VlogInput? bottom,
  required String out,
  required List<String> encoder,
  Duration length = maxMomentVideo,
}) {
  final secs = (length.inMilliseconds / 1000).toString();
  final args = <String>['-y'];
  for (final i in [top, bottom]) {
    if (i == null) {
      args.addAll([
        '-f', 'lavfi', '-t', secs, //
        '-i', 'color=c=0x151515:s=${_w}x$_half:r=$_fps',
      ]);
    } else if (i.isVideo) {
      args.addAll(['-t', secs, '-i', i.path]);
    } else {
      args.addAll(['-loop', '1', '-t', secs, '-i', i.path]);
    }
  }
  // Cover-crop each half, then pad short clips with their last frame so every
  // slot is exactly [length] long and the halves stay in sync.
  String fit(int n) =>
      '[$n:v]scale=$_w:$_half:force_original_aspect_ratio=increase,'
      'crop=$_w:$_half,setsar=1,fps=$_fps,'
      'tpad=stop_mode=clone:stop_duration=$secs,trim=duration=$secs,'
      'setpts=PTS-STARTPTS[v$n]';
  args.addAll([
    '-filter_complex',
    '${fit(0)};${fit(1)};[v0][v1]vstack=inputs=2,format=yuv420p[v]',
    '-map', '[v]',
    // shortcut: vlog is silent; mixing clip audio needs per-clip probing (photos/no-mic clips have no track). Add when users ask for sound.
    '-an',
    ...encoder,
    '-r', '$_fps',
    out,
  ]);
  return args;
}

/// Concat-demuxer list for the rendered segments.
String concatList(List<String> segments) =>
    segments.map((p) => "file '${p.replaceAll("'", r"'\''")}'").join('\n');

/// Hardware H.264 first (small, plays everywhere); FFmpeg's built-in MPEG-4
/// if the device's encoder refuses. The min build has no GPL x264.
List<List<String>> _encoders() => [
  if (Platform.isIOS) ['-c:v', 'h264_videotoolbox', '-b:v', '3M'],
  if (Platform.isAndroid) ['-c:v', 'h264_mediacodec', '-b:v', '3M'],
  ['-c:v', 'mpeg4', '-q:v', '3'],
];

class VlogRenderFailed implements Exception {
  const VlogRenderFailed(this.message);
  final String message;
  @override
  String toString() => 'VlogRenderFailed: $message';
}

/// Turns a day's moments into one MP4 on the device: download each clip,
/// render one 3 s split-screen segment per slot, then join them losslessly.
class VlogRenderer {
  VlogRenderer(this._repo, {http.Client? client})
    : _client = client ?? http.Client();

  final MomentsRepository _repo;
  final http.Client _client;

  /// Returns the path of the finished MP4. [onProgress] goes 0 → 1.
  Future<String> render(
    List<VlogSlot> slots,
    String day, {
    void Function(double)? onProgress,
  }) async {
    if (slots.isEmpty) throw const VlogRenderFailed('no moments');
    final dir = Directory('${(await getTemporaryDirectory()).path}/vlog_$day');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);

    List<String>? encoder;
    final segments = <String>[];
    for (var i = 0; i < slots.length; i++) {
      final s = slots[i];
      final top = await _fetch(s.partner, dir);
      final bottom = await _fetch(s.mine, dir);
      final out = '${dir.path}/seg_$i.mp4';
      // Pick the encoder on the first slot; reuse it so segments join without re-encoding.
      List<String>? used;
      for (final e in encoder == null ? _encoders() : [encoder]) {
        if (await _run(
          slotArgs(top: top, bottom: bottom, out: out, encoder: e),
        )) {
          used = e;
          break;
        }
      }
      if (used == null) throw VlogRenderFailed('segment $i');
      encoder = used;
      segments.add(out);
      onProgress?.call((i + 1) / (slots.length + 1));
    }

    final list = File('${dir.path}/list.txt')
      ..writeAsStringSync(concatList(segments));
    final result = '${dir.path}/lovinity_vlog_$day.mp4';
    final ok = await _run([
      '-y', '-f', 'concat', '-safe', '0', '-i', list.path, //
      '-c', 'copy', '-movflags', '+faststart', result,
    ]);
    if (!ok) throw const VlogRenderFailed('join');
    onProgress?.call(1);
    return result;
  }

  Future<VlogInput?> _fetch(Moment? m, Directory dir) async {
    if (m == null) return null;
    final file = File('${dir.path}/${m.id}.${m.isVideo ? 'mp4' : 'jpg'}');
    if (!file.existsSync()) {
      final url = await _repo.signedUrl(m.mediaPath);
      final res = await _client.get(Uri.parse(url));
      if (res.statusCode != 200) {
        throw VlogRenderFailed('download ${res.statusCode}');
      }
      await file.writeAsBytes(res.bodyBytes);
    }
    return (path: file.path, isVideo: m.isVideo);
  }

  Future<bool> _run(List<String> args) async {
    final session = await FFmpegKit.executeWithArguments(args);
    if (ReturnCode.isSuccess(await session.getReturnCode())) return true;
    developer.log(
      'ffmpeg failed: ${await session.getLogsAsString()}',
      name: 'VlogRenderer',
    );
    return false;
  }
}
