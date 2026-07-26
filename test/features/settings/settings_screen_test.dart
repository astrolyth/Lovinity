// test/features/settings/settings_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lovinity/features/home/domain/home_providers.dart';
import 'package:lovinity/features/settings/domain/settings_providers.dart';
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
    await tester.pumpWidget(_app(_profile(gender: 'female')));
    await tester.pump();
    expect(find.textContaining('Share cycle'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsWidgets);
  });

  testWidgets('husband does not see the cycle privacy toggle', (tester) async {
    await tester.pumpWidget(_app(_profile(gender: 'male')));
    await tester.pump();
    expect(find.textContaining('Share cycle'), findsNothing);
  });

  testWidgets('madhhab option reflects the profile value and is enabled',
      (tester) async {
    await tester.pumpWidget(_app(_profile(gender: 'female', madhhab: 'hanafi')));
    await tester.pump();
    expect(find.text('Madhhab'), findsOneWidget);
    final dropdown = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(dropdown.value, 'hanafi');
    expect(dropdown.onChanged, isNotNull);
  });

  testWidgets('madhhab option is disabled until the profile loads',
      (tester) async {
    await tester.pumpWidget(_app(null));
    await tester.pump();
    final dropdown = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(dropdown.value, 'shafi'); // safe default while unknown
    expect(dropdown.onChanged, isNull);
  });
}
