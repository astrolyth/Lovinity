/// Domain-level error the UI can render without leaking internals.
sealed class AppFailure implements Exception {
  const AppFailure(this.message);
  final String message;

  @override
  String toString() => '$runtimeType($message)';
}

class NetworkFailure extends AppFailure {
  const NetworkFailure([super.message = 'No connection']);
}

class AuthFailure extends AppFailure {
  const AuthFailure(super.message);
}

class PairingFailure extends AppFailure {
  const PairingFailure(super.message);

  factory PairingFailure.fromRpcCode(String code) => switch (code) {
        'invite_not_found' => const PairingFailure('That code isn\'t valid.'),
        'invite_expired' => const PairingFailure('That code has expired. Ask your spouse for a fresh one.'),
        'invite_already_used' => const PairingFailure('That code has already been used.'),
        'cannot_pair_with_self' => const PairingFailure('You can\'t pair with your own code.'),
        'already_paired' => const PairingFailure('You\'re already paired.'),
        'inviter_already_paired' => const PairingFailure('Your spouse is already paired with someone.'),
        'gender_required' => const PairingFailure('Please finish setting up your profile before pairing.'),
        'same_gender_pairing' => const PairingFailure('Lovinity pairs one man and one woman together.'),
        _ => PairingFailure('Something went wrong: $code'),
      };
}

class UnknownFailure extends AppFailure {
  const UnknownFailure([super.message = 'Unexpected error']);
}
