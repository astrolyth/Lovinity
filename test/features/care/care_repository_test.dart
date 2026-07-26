import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/shared/models/care_tip.dart';

void main() {
  test('CareTip.fromRow maps columns + flags pending review', () {
    final t = CareTip.fromRow({
      'audience': 'wife', 'category': 'spiritual', 'title': 'T', 'body': 'B',
      'islamic_reference': 'Q 2:185', 'scientific_reference': null,
      'review_status': 'pending_review',
    });
    expect(t.audience, 'wife');
    expect(t.islamicReference, 'Q 2:185');
    expect(t.isPendingReview, isTrue);
  });
}
