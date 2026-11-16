// lib/features/chat/presentation/photo_viewer_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';

/// Full-screen, pinch-to-zoom view of a decrypted, locally-cached chat photo.
class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({super.key, required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.file(File(filePath)),
        ),
      ),
    );
  }
}
