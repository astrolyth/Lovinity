import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provided by [ProviderScope] at app boot after Supabase.initialize completes.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  throw UnimplementedError(
    'supabaseClientProvider must be overridden at ProviderScope root',
  );
});

/// The app's one keychain/keystore config; also backs the Supabase session.
const appSecureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);

final secureStorageProvider =
    Provider<FlutterSecureStorage>((ref) => appSecureStorage);
