import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'adhkar_repository.dart';

class AdhkarProgressStore {
  AdhkarProgressStore(this._storage);
  final FlutterSecureStorage _storage;

  static const _prefix = 'adhkar:';
  String _key(String dayKey, AdhkarSet s) => '$_prefix$dayKey:${s.dbValue}';

  Future<Map<String, int>> load(String dayKey, AdhkarSet set) async {
    final all = await _storage.readAll();
    // Drop prior days' progress; keys are adhkar:<dayKey>:<set>.
    for (final k in all.keys) {
      if (k.startsWith(_prefix) && k.split(':')[1] != dayKey) {
        await _storage.delete(key: k);
      }
    }
    final raw = all[_key(dayKey, set)];
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', v as int));
    } catch (_) {
      return {};
    }
  }

  Future<void> save(
    String dayKey,
    AdhkarSet set,
    Map<String, int> countsByDuaId,
  ) =>
      _storage.write(key: _key(dayKey, set), value: jsonEncode(countsByDuaId));
}
