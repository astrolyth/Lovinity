// test/integration/signal_server_test.dart
//
// Integration tests against LOCAL Supabase (Docker). These are the only tests
// that exercise the RPCs and the bytea wire format. Require `supabase start`.
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lovinity/core/crypto/prekey_bundle_source.dart';
import 'package:lovinity/core/crypto/signal_keys.dart';
import 'package:lovinity/core/crypto/signal_registration.dart';

const _url = 'http://127.0.0.1:54321';
const _anon =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

// Service-role key for teardown only (admin.deleteUser). Same throwaway-user
// cleanup pattern as test/features/onboarding/onboarding_repository_test.dart
// and test/features/scoring/scoreboard_repository_test.dart.
const _serviceRoleKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

late SupabaseClient client;
late SupabaseClient adminClient;

Future<String> _signUpUser() async {
  final email = 'sig-${DateTime.now().microsecondsSinceEpoch}@test.local';
  final res = await client.auth.signUp(email: email, password: 'password123');
  final userId = res.user!.id;
  addTearDown(() async {
    await adminClient.auth.admin.deleteUser(userId);
  });
  return userId;
}

void main() {
  setUpAll(() async {
    client = SupabaseClient(
      _url,
      _anon,
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );
    adminClient = SupabaseClient(
      _url,
      _serviceRoleKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  });

  test('BYTEA ROUND-TRIP: published key bytes come back identical', () async {
    await _signUpUser();
    final registrar = SupabaseDeviceRegistrar(client);
    final source = SupabasePreKeyBundleSource(client);
    final generated = generateBundle(deviceId: 'dev-a', oneTimePrekeyCount: 2);
    final pub = generated.public;

    final deviceNum = await registrar.register(
      deviceId: 'dev-a',
      registrationId: pub.registrationId,
      identityPub: pub.identityPub,
      signedPrekeyId: pub.signedPrekeyId,
      signedPrekeyPub: pub.signedPrekeyPub,
      signedPrekeySig: pub.signedPrekeySig,
    );
    await registrar.uploadOneTimePrekeys(
      deviceNum: deviceNum,
      prekeys: {for (final p in pub.oneTimePrekeys) p.id: p.pub},
    );

    final me = client.auth.currentUser!.id;
    final bundle = await source.bundleFor(me, deviceNum);

    expect(bundle, isNotNull);
    // THE point of this test: a JSON int array would silently store the ASCII
    // bytes of "[5,1,171]" instead of the key, and nothing would error.
    expect(bundle!.identityPub, pub.identityPub);
    expect(bundle.signedPrekeyPub, pub.signedPrekeyPub);
    expect(bundle.signedPrekeySig, pub.signedPrekeySig);
    expect(bundle.registrationId, pub.registrationId);
  });

  test('list_devices consumes nothing; fetch_prekey_bundle consumes exactly one',
      () async {
    await _signUpUser();
    final registrar = SupabaseDeviceRegistrar(client);
    final source = SupabasePreKeyBundleSource(client);
    final generated = generateBundle(deviceId: 'dev-b', oneTimePrekeyCount: 3);
    final pub = generated.public;

    final deviceNum = await registrar.register(
      deviceId: 'dev-b',
      registrationId: pub.registrationId,
      identityPub: pub.identityPub,
      signedPrekeyId: pub.signedPrekeyId,
      signedPrekeyPub: pub.signedPrekeyPub,
      signedPrekeySig: pub.signedPrekeySig,
    );
    await registrar.uploadOneTimePrekeys(
      deviceNum: deviceNum,
      prekeys: {for (final p in pub.oneTimePrekeys) p.id: p.pub},
    );
    final me = client.auth.currentUser!.id;

    final before = await registrar.unconsumedPrekeyCount(deviceNum);
    await source.deviceNumsFor(me);
    expect(await registrar.unconsumedPrekeyCount(deviceNum), before,
        reason: 'roster lookup must consume nothing');

    final first = await source.bundleFor(me, deviceNum);
    expect(await registrar.unconsumedPrekeyCount(deviceNum), before - 1);

    final second = await source.bundleFor(me, deviceNum);
    expect(second!.oneTimePrekeyId, isNot(first!.oneTimePrekeyId),
        reason: 'a prekey must never be handed out twice');
  });

  test('exhausted device still returns a bundle with a null one-time prekey',
      () async {
    await _signUpUser();
    final registrar = SupabaseDeviceRegistrar(client);
    final source = SupabasePreKeyBundleSource(client);
    final generated = generateBundle(deviceId: 'dev-c', oneTimePrekeyCount: 1);
    final pub = generated.public;

    final deviceNum = await registrar.register(
      deviceId: 'dev-c',
      registrationId: pub.registrationId,
      identityPub: pub.identityPub,
      signedPrekeyId: pub.signedPrekeyId,
      signedPrekeyPub: pub.signedPrekeyPub,
      signedPrekeySig: pub.signedPrekeySig,
    );
    await registrar.uploadOneTimePrekeys(
      deviceNum: deviceNum,
      prekeys: {for (final p in pub.oneTimePrekeys) p.id: p.pub},
    );
    final me = client.auth.currentUser!.id;

    await source.bundleFor(me, deviceNum); // consumes the only one
    final exhausted = await source.bundleFor(me, deviceNum);

    expect(exhausted, isNotNull,
        reason: 'the device must stay reachable when prekeys run out');
    expect(exhausted!.oneTimePrekeyId, isNull);
    expect(exhausted.signedPrekeyPub, pub.signedPrekeyPub,
        reason: 'handshake falls back to the signed prekey');
  });

  test('re-registering the same device reuses its device_num', () async {
    await _signUpUser();
    final registrar = SupabaseDeviceRegistrar(client);
    final g1 = generateBundle(deviceId: 'dev-d');
    final first = await registrar.register(
      deviceId: 'dev-d',
      registrationId: g1.public.registrationId,
      identityPub: g1.public.identityPub,
      signedPrekeyId: g1.public.signedPrekeyId,
      signedPrekeyPub: g1.public.signedPrekeyPub,
      signedPrekeySig: g1.public.signedPrekeySig,
    );
    final second = await registrar.register(
      deviceId: 'dev-d',
      registrationId: g1.public.registrationId,
      identityPub: g1.public.identityPub,
      signedPrekeyId: g1.public.signedPrekeyId,
      signedPrekeyPub: g1.public.signedPrekeyPub,
      signedPrekeySig: g1.public.signedPrekeySig,
    );

    expect(second, first);
  });

  test('two new devices for one user get distinct device numbers', () async {
    await _signUpUser();
    final registrar = SupabaseDeviceRegistrar(client);
    final g = generateBundle(deviceId: 'x');

    final a = await registrar.register(
      deviceId: 'dev-e1',
      registrationId: g.public.registrationId,
      identityPub: g.public.identityPub,
      signedPrekeyId: g.public.signedPrekeyId,
      signedPrekeyPub: g.public.signedPrekeyPub,
      signedPrekeySig: g.public.signedPrekeySig,
    );
    final b = await registrar.register(
      deviceId: 'dev-e2',
      registrationId: g.public.registrationId,
      identityPub: g.public.identityPub,
      signedPrekeyId: g.public.signedPrekeyId,
      signedPrekeyPub: g.public.signedPrekeyPub,
      signedPrekeySig: g.public.signedPrekeySig,
    );

    expect(a, isNot(b));
  });
}
