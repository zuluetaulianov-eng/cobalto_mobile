import 'package:flutter_test/flutter_test.dart';
import 'package:cobalto_mobile/main.dart';

void main() {
  testWidgets('CobaltoApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const CobaltoApp());
  });
}
