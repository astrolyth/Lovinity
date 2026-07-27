import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/shared/models/role.dart';
import 'package:lovinity/shared/models/couple.dart';

void main() {
  test('roleOfGender maps male->husband, female->wife, null->null', () {
    expect(roleOfGender('male'), Role.husband);
    expect(roleOfGender('female'), Role.wife);
    expect(roleOfGender(null), isNull);
  });

  test('roleOfUser uses the member gender for the given user', () {
    const couple = Couple(
      id: 'c', memberA: 'aaa', memberB: 'bbb',
      status: 'active', longDistance: false,
    );
    final r = roleOfUser(couple, 'aaa',
        memberAGender: 'female', memberBGender: 'male');
    expect(r, Role.wife);
    final r2 = roleOfUser(couple, 'bbb',
        memberAGender: 'female', memberBGender: 'male');
    expect(r2, Role.husband);
  });
}
