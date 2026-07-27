class CareTip {
  const CareTip({
    required this.audience,
    required this.category,
    required this.title,
    required this.body,
    required this.reviewStatus,
    this.islamicReference,
    this.scientificReference,
  });
  final String audience;
  final String category;
  final String title;
  final String body;
  final String reviewStatus;
  final String? islamicReference;
  final String? scientificReference;

  bool get isPendingReview => reviewStatus == 'pending_review';

  factory CareTip.fromRow(Map<String, dynamic> row) => CareTip(
        audience: row['audience'] as String,
        category: row['category'] as String,
        title: row['title'] as String,
        body: row['body'] as String,
        reviewStatus: (row['review_status'] ?? 'pending_review') as String,
        islamicReference: row['islamic_reference'] as String?,
        scientificReference: row['scientific_reference'] as String?,
      );
}
