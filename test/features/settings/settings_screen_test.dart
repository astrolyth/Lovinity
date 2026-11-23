// test/features/settings/settings_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lovinity/features/home/domain/home_providers.dart';
import 'package:lovinity/features/settings/domain/settings_providers.dart';
import 'package:lovinity/core/widgets/lov_kit.dart';
import 'package:lovinity/features/settings/presentation/settings_screen.dart';
import 'package:lovinity/shared/models/user_profile.dart';

UserProfile _profile({required String gender, String madhhab = 'shafi'}) =>
    UserProfile(
      id: 'u',
      displayName: 'Test',
      timezone: 'UTC',
      madhhab: madhhab,
      calcMethod: 'muslim_world_league',
      gender: gender,
    );

/// The redesign's grouped list is taller than the default 800x600 surface.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _app(UserProfile? profile) => ProviderScope(
  overrides: [
    // The screen derives isWife/madhhab from the profile rather than also
    // watching isWifeProvider, so override the profile itself.
    ownProfileProvider.overrideWith((ref) async => profile),
    preferencesProvider.overrideWith((ref) async => <String, dynamic>{}),
  ],
  child: const MaterialApp(home: SettingsScreen()),
);

void main() {
  testWidgets('wife sees the cycle privacy toggle', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(_profile(gender: 'female')));
    await tester.pump();
    expect(find.textContaining('Share cycle'), findsOneWidget);
    expect(find.byType(Switch), findsWidgets);
  });

  testWidgets('husband does not see the cycle privacy toggle', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(_profile(gender: 'male')));
    await tester.pump();
    expect(find.textContaining('Share cycle'), findsNothing);
  });

  testWidgets('Asr time reflects the profile madhhab', (tester) async {
    await tester.pumpWidget(
      _app(_profile(gender: 'female', madhhab: 'hanafi')),
    );
    await tester.pump();
    expect(find.text('Asr time'), findsOneWidget);
    final seg = tester.widget<LovSegmented<String>>(
      find.byType(LovSegmented<String>),
    );
    expect(seg.selected, 'hanafi');
  });

  testWidgets('Asr time defaults to Standard until the profile loads', (
    tester,
  ) async {
    await tester.pumpWidget(_app(null));
    await tester.pump();
    final seg = tester.widget<LovSegmented<String>>(
      find.byType(LovSegmented<String>),
    );
    expect(seg.selected, 'shafi'); // safe default while unknown
    // Choosing before the profile loads must not write anything.
    await tester.tap(find.text('Hanafi'));
    await tester.pump();
  });
}
