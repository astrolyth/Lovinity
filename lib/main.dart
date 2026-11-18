import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/config_error_app.dart';
import 'core/config/env.dart';
import 'core/crypto/secure_store.dart';
import 'core/storage/secure_session_storage.dart';
import 'core/time/timezone_bootstrap.dart';
import 'shared/providers/supabase_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initTimezones();

  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['fitrahive/dua-dhikr'],
      await rootBundle.loadString('assets/licenses/fitrahive-dua-dhikr.txt'),
    );
  });

  // Fail fast on a missing key. Without this the app boots "successfully",
  // then every Supabase realtime subscription is rejected with an endless
  // stream of `403 ... was not upgraded to websocket` errors (the apikey
  // query param is empty), the couple stream never settles, and cards that
  // depend on it flicker as they mount/unmount. That failure mode is very
  // hard to trace back to a missing build flag, so name the fix here.
  if (!Env.isConfigured) {
    const message =
        'SUPABASE_ANON_KEY is empty — the app was built without its config.\n'
        'Run with the dart-define file, e.g.:\n'
        '  flutter run --dart-define-from-file=config/supabase.local.json\n'
        '(use config/supabase.cloud.json for a cloud project). See '
        'lib/core/config/env.dart.';
    debugPrint(message);
    // Show it on screen too; throwing here leaves only the native splash.
    runApp(const ConfigErrorApp(message: message));
    return;
  }

  // Same key supabase_flutter uses by default, so the legacy session migrates.
  final sessionKey =
      'sb-${Uri.parse(Env.supabaseUrl).host.split('.').first}-auth-token';
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
    debug: false,
    authOptions: FlutterAuthClientOptions(
      localStorage: SecureSessionStorage(
        const FlutterSecureStore(appSecureStorage),
        key: sessionKey,
        legacy: SharedPreferencesLocalStorage(persistSessionKey: sessionKey),
      ),
    ),
  );

  runApp(
    ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(Supabase.instance.client),
      ],
      child: const LovinityApp(),
    ),
  );
}
