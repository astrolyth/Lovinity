import 'dart:io';

import 'package:camera/camera.dart' hide ImageFormat;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_thumbnail_video/index.dart' show ImageFormat;
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../domain/moment.dart';
import '../domain/moments_providers.dart';

/// Mirrors the 'moments' bucket file_size_limit.
const _maxBytes = 10 * 1024 * 1024;

/// Full-screen live camera. Tap = photo, hold = video (auto-stops at 3 s).
/// Deliberately no gallery: moments are only what's happening right now.
class MomentCameraScreen extends ConsumerStatefulWidget {
  const MomentCameraScreen({super.key});

  @override
  ConsumerState<MomentCameraScreen> createState() => _MomentCameraScreenState();
}

class _Captured {
  const _Captured(this.path, this.isVideo);
  final String path;
  final bool isVideo;
}

class _MomentCameraScreenState extends ConsumerState<MomentCameraScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  CameraController? _controller;
  String? _error;
  bool _recording = false;
  bool _busy = false;
  _Captured? _captured;
  VideoPlayerController? _preview;
  final _caption = TextEditingController();
  late final AnimationController _progress =
      AnimationController(vsync: this, duration: maxMomentVideo)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _stopRecording();
        });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _preview?.dispose();
    _progress.dispose();
    _caption.dispose();
    super.dispose();
  }

  // The camera plugin requires releasing the camera when backgrounded.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.inactive && c != null) {
      _controller = null;
      _recording = false;
      _progress.reset();
      c.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed &&
        c == null &&
        _cameras.isNotEmpty &&
        _captured == null) {
      _open(_cameras[_cameraIndex]);
    }
  }

  Future<void> _setup() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _error = 'No camera found on this device');
        return;
      }
      final back = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      _cameraIndex = back < 0 ? 0 : back;
      await _open(_cameras[_cameraIndex]);
    } on CameraException catch (e) {
      _fail(e);
    }
  }

  Future<void> _open(CameraDescription d) async {
    final old = _controller;
    final c = CameraController(d, ResolutionPreset.high);
    setState(() {
      _controller = null;
      _error = null;
    });
    await old?.dispose();
    try {
      await c.initialize();
      if (!mounted) return c.dispose();
      setState(() => _controller = c);
    } on CameraException catch (e) {
      await c.dispose();
      _fail(e);
    }
  }

  void _fail(CameraException e) {
    if (!mounted) return;
    final denied =
        e.code.contains('AccessDenied') || e.code.contains('Restricted');
    setState(
      () => _error = denied
          ? 'Allow camera and microphone access in Settings to send moments'
          : "Couldn't open the camera",
    );
  }

  void _flip() {
    if (_cameras.length < 2 || _recording) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    _open(_cameras[_cameraIndex]);
  }

  Future<void> _takePhoto() async {
    final c = _controller;
    if (c == null || _recording || c.value.isTakingPicture) return;
    HapticFeedback.lightImpact();
    try {
      final f = await c.takePicture();
      if (mounted) setState(() => _captured = _Captured(f.path, false));
    } on CameraException catch (e) {
      _fail(e);
    }
  }

  Future<void> _startRecording() async {
    final c = _controller;
    if (c == null || _recording) return;
    HapticFeedback.mediumImpact();
    try {
      await c.startVideoRecording();
      setState(() => _recording = true);
      _progress.forward(from: 0);
    } on CameraException catch (e) {
      _fail(e);
    }
  }

  /// Called on finger lift or when the 3 s ring completes, whichever is first.
  Future<void> _stopRecording() async {
    final c = _controller;
    if (c == null || !_recording) return;
    _recording = false;
    _progress.stop();
    try {
      final f = await c.stopVideoRecording();
      final p = VideoPlayerController.file(File(f.path));
      await p.initialize();
      await p.setLooping(true);
      await p.play();
      if (!mounted) return p.dispose();
      setState(() {
        _captured = _Captured(f.path, true);
        _preview = p;
      });
    } on CameraException catch (e) {
      _fail(e);
    } finally {
      _progress.reset();
    }
  }

  void _retake() {
    _preview?.dispose();
    setState(() {
      _preview = null;
      _captured = null;
    });
    if (_controller == null && _cameras.isNotEmpty) {
      _open(_cameras[_cameraIndex]);
    }
  }

  void _close() => context.canPop() ? context.pop() : context.go('/moments');

  Future<void> _send() async {
    final cap = _captured;
    final couple = ref.read(currentCoupleProvider).asData?.value;
    final user = ref.read(authSessionProvider).asData?.value?.user;
    if (cap == null || couple == null || user == null || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final Uint8List bytes;
      Uint8List? thumb;
      if (cap.isVideo) {
        bytes = await File(cap.path).readAsBytes();
        thumb = await VideoThumbnail.thumbnailData(
          video: cap.path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 480,
          quality: 70,
        );
      } else {
        final c = await FlutterImageCompress.compressWithFile(
          cap.path,
          minWidth: 1440,
          minHeight: 1440,
          quality: 80,
        );
        if (c == null) throw StateError('compress failed');
        bytes = c;
      }
      if (bytes.length > _maxBytes) {
        messenger.showSnackBar(
          const SnackBar(content: Text('That moment is too large to send')),
        );
        return;
      }
      await ref
          .read(momentsRepositoryProvider)
          .send(
            coupleId: couple.id,
            userId: user.id,
            bytes: bytes,
            mimeType: cap.isVideo ? 'video/mp4' : 'image/jpeg',
            thumbnailBytes: thumb,
            caption: _caption.text,
          );
      messenger.showSnackBar(const SnackBar(content: Text('Moment sent 💛')));
      if (mounted) _close();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't send — try again")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: _captured == null ? _buildCamera() : _buildReview(),
      ),
    );
  }

  Widget _buildCamera() {
    final c = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ),
          )
        else if (c == null || !c.value.isInitialized)
          const Center(child: CircularProgressIndicator(color: Colors.white))
        else
          ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                // previewSize is reported landscape; the app is portrait.
                width: c.value.previewSize?.height ?? 1,
                height: c.value.previewSize?.width ?? 1,
                child: CameraPreview(c),
              ),
            ),
          ),
        SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  _RoundIcon(
                    icon: Icons.close_rounded,
                    label: 'Close camera',
                    onTap: _close,
                  ),
                  const Spacer(),
                  if (_cameras.length > 1)
                    _RoundIcon(
                      icon: Icons.cameraswitch_rounded,
                      label: 'Switch camera',
                      onTap: _flip,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                _recording ? 'Recording…' : 'Tap for photo · Hold for 3s video',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 8)],
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                button: true,
                label: 'Shutter. Tap for photo, hold for video',
                child: GestureDetector(
                  onTap: _takePhoto,
                  onLongPressStart: (_) => _startRecording(),
                  onLongPressEnd: (_) => _stopRecording(),
                  child: AnimatedBuilder(
                    animation: _progress,
                    builder: (_, _) => SizedBox(
                      width: 88,
                      height: 88,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox.expand(
                            child: CircularProgressIndicator(
                              value: _recording ? _progress.value : 0,
                              strokeWidth: 5,
                              color: Colors.redAccent,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: _recording ? 40 : 70,
                            height: _recording ? 40 : 70,
                            decoration: BoxDecoration(
                              color: _recording
                                  ? Colors.redAccent
                                  : Colors.white24,
                              borderRadius: BorderRadius.circular(
                                _recording ? 10 : 35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReview() {
    final cap = _captured!;
    final p = _preview;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (cap.isVideo && p != null)
          ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: p.value.size.width,
                height: p.value.size.height,
                child: VideoPlayer(p),
              ),
            ),
          )
        else
          Image.file(File(cap.path), fit: BoxFit.cover),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _RoundIcon(
                      icon: Icons.close_rounded,
                      label: 'Discard',
                      onTap: _retake,
                    ),
                  ],
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _caption,
                    maxLength: maxMomentCaption,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: const InputDecoration(
                      hintText: 'Add a caption…',
                      hintStyle: TextStyle(color: Colors.white70),
                      counterText: '',
                      filled: true,
                      fillColor: Colors.black45,
                      border: OutlineInputBorder(borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: _busy ? null : _retake,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retake'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _busy ? null : _send,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                        label: const Text('Send to partner'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: IconButton(
      tooltip: label,
      onPressed: onTap,
      style: IconButton.styleFrom(backgroundColor: Colors.black38),
      icon: Icon(icon, color: Colors.white),
    ),
  );
}
