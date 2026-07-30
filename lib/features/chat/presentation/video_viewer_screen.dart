// lib/features/chat/presentation/video_viewer_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Full-screen playback of a decrypted, locally-cached chat video.
class VideoViewerScreen extends StatefulWidget {
  const VideoViewerScreen({super.key, required this.filePath});

  final String filePath;

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  late VideoPlayerController _controller;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  void _initializeController() {
    _hasError = false;
    _controller = VideoPlayerController.file(File(widget.filePath));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _controller.play();
    }).catchError((Object e, StackTrace st) {
      debugPrint('VideoViewerScreen: failed to initialize video: $e');
      if (!mounted) return;
      setState(() => _hasError = true);
    });
  }

  void _retry() {
    _controller.dispose();
    setState(() {});
    _initializeController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : _hasError
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.white70,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Couldn't play this video",
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: _retry,
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
      ),
      floatingActionButton: _controller.value.isInitialized
          ? FloatingActionButton(
              onPressed: () {
                setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                });
              },
              child: Icon(
                  _controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
            )
          : null,
    );
  }
}
