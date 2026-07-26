import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/settings/presentation/settings_screen.dart';
import 'package:lovinity/features/care/presentation/care_screen.dart';
import 'package:lovinity/features/cycle/presentation/cycle_screen.dart';

void main() {
  test('destination screens are const-constructible (smoke)', () {
    expect(const SettingsScreen(), isA<Widget>());
    expect(const CareScreen(), isA<Widget>());
    expect(const CycleScreen(), isA<Widget>());
  });
}
