import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/prayer_log/presentation/qibla_sheet.dart';

void main() {
  test('Qibla bearing matches known cities', () {
    // Published bearings: London ~119° (SE), New York ~58° (NE).
    expect(qiblaBearing(51.5074, -0.1278), closeTo(119, 1));
    expect(qiblaBearing(40.7128, -74.0060), closeTo(58.5, 1));
    expect(compassPoint(119), 'SE');
    expect(compassPoint(58.5), 'NE');
    expect(compassPoint(359), 'N');
  });
}
