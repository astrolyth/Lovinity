import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/dua_suggestions.dart';

class MoodStore {
  MoodStore(this._storage);
  final FlutterSecureStorage _storage;

  static const _prefix = 'mood:';

  Future<Mood?> read(String dayKey) async {
    final all = await _storage.readAll();
    for (final k in all.keys) {
      if (k.startsWith(_prefix) && k != '$_prefix$dayKey') {
        await _storage.delete(key: k);
      }
    }
    final raw = all['$_prefix$dayKey'];
    return Mood.values.where((m) => m.name == raw).firstOrNull;
  }

  Future<void> write(String dayKey, Mood? mood) => mood == null
      ? _storage.delete(key: '$_prefix$dayKey')
      : _storage.write(key: '$_prefix$dayKey', value: mood.name);
}
