import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/duas/data/adhkar_progress_store.dart';
import 'package:lovinity/features/duas/data/adhkar_repository.dart';

class MemStorage extends Fake implements FlutterSecureStorage {
  final data = <String, String>{};
  @override
  dynamic noSuchMethod(Invocation i) {
    switch (i.memberName) {
      case #readAll:
        return Future.value(Map<String, String>.of(data));
      case #write:
        data[i.namedArguments[#key] as String] =
            i.namedArguments[#value] as String;
        return Future<void>.value();
      case #delete:
        data.remove(i.namedArguments[#key] as String);
        return Future<void>.value();
    }
    return super.noSuchMethod(i);
  }
}

void main() {
  test('save then load round-trips', () async {
    final store = AdhkarProgressStore(MemStorage());
    await store.save('2026-11-16', AdhkarSet.morning, {'a': 2});
    expect(await store.load('2026-11-16', AdhkarSet.morning), {'a': 2});
  });

  test('new day returns {} and deletes the old key', () async {
    final mem = MemStorage();
    final store = AdhkarProgressStore(mem);
    await store.save('2026-11-16', AdhkarSet.morning, {'a': 2});
    mem.data['other'] = 'keep';
    expect(await store.load('2026-11-17', AdhkarSet.morning), isEmpty);
    expect(mem.data.keys, ['other']);
  });
}
