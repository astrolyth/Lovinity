import 'package:flutter/material.dart';

/// Shown instead of the app when it was built without its Supabase config,
/// so a plain `flutter run` shows the fix on screen rather than freezing on
/// the native splash.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: SelectableText(message)),
          ),
        ),
      ),
    );
  }
}
