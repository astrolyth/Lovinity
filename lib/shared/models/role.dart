import 'couple.dart';

enum Gender { male, female }

enum Role { husband, wife }

Role? roleOfGender(String? gender) => switch (gender) {
      'male' => Role.husband,
      'female' => Role.wife,
      _ => null,
    };

/// Role of [userId] within [couple], given each member's gender.
Role? roleOfUser(
  Couple couple,
  String userId, {
  required String? memberAGender,
  required String? memberBGender,
}) {
  final g = userId == couple.memberA ? memberAGender : memberBGender;
  return roleOfGender(g);
}
