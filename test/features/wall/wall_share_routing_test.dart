import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lovinity/core/platform/share_intake.dart';
import 'package:lovinity/features/auth/domain/auth_controller.dart';
import 'package:lovinity/features/home/domain/home_providers.dart';
import 'package:lovinity/features/pairing/domain/pairing_providers.dart';
import 'package:lovinity/features/wall/domain/wall_share_routing.dart';
import 'package:lovinity/shared/models/couple.dart';
import 'package:lovinity/shared/models/user_profile.dart';

class _MockSession extends Mock implements Session {}

class _MockUser extends Mock implements User {}

Session _session() {
  final s = _MockSession();
  final u = _MockUser();
  when(() => u.id).thenReturn('me');
  when(() => s.user).thenReturn(u);
  return s;
}

const _couple =
    Couple(id: 'c1', memberA: 'me', memberB: 'sp', status: 'active', longDistance: false);
UserProfile _profile({String? gender = 'male'}) => UserProfile(
    id: 'me',
    displayName: 'Me',
    timezone: 'UTC',
    madhhab: 'shafi',
    calcMethod: 'muslim_world_league',
    gender: gender);
const _share = SharedPayload(text: 'https://youtu.be/a');

ProviderContainer _container({Session? session, Couple? couple, UserProfile? profile}) {
  final c = ProviderContainer(overrides: [
    authSessionProvider.overrideWith((ref) => Stream.value(session)),
    currentCoupleProvider.overrideWith((ref) => Stream.value(couple)),
    ownProfileProvider.overrideWith((ref) async => profile),
  ]);
  addTearDown(c.dispose);
  c.listen(authSessionProvider, (_, _) {});
  c.listen(currentCoupleProvider, (_, _) {});
  return c;
}

void main() {
  test('accepts and stores the share when signed in and paired', () async {
    final c = _container(session: _session(), couple: _couple, profile: _profile());
    expect(await c.read(acceptShareProvider)(_share), isTrue);
    expect(c.read(pendingShareProvider)?.text, _share.text);
  });

  test('ignores the share when unpaired', () async {
    final c = _container(session: _session());
    expect(await c.read(acceptShareProvider)(_share), isFalse);
    expect(c.read(pendingShareProvider), isNull);
  });

  test('ignores the share when the profile is missing', () async {
    final c = _container(session: _session(), couple: _couple);
    expect(await c.read(acceptShareProvider)(_share), isFalse);
    expect(c.read(pendingShareProvider), isNull);
  });

  test('ignores the share when onboarding is not finished (no gender)', () async {
    final c = _container(
        session: _session(), couple: _couple, profile: _profile(gender: null));
    expect(await c.read(acceptShareProvider)(_share), isFalse);
    expect(c.read(pendingShareProvider), isNull);
  });

  test('ignores the share when signed out', () async {
    final c = _container();
    expect(await c.read(acceptShareProvider)(_share), isFalse);
    expect(c.read(pendingShareProvider), isNull);
  });
}
