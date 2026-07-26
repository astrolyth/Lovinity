import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/chat/presentation/chat_screen.dart';

void main() {
  test('ChatScreen is const-constructible (route target smoke)', () {
    expect(const ChatScreen(), isA<Widget>());
  });
}
