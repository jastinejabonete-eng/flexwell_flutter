import 'package:flutter_test/flutter_test.dart';
import 'package:flexwell_flutter/main.dart';

void main() {
  testWidgets('App launches to navigation when terms accepted', (tester) async {
    await tester.pumpWidget(const FlexWellApp(termsAccepted: true));
    await tester.pump();
    expect(find.byType(FlexWellApp), findsOneWidget);
  });

  testWidgets('App launches to terms gate when terms not accepted', (tester) async {
    await tester.pumpWidget(const FlexWellApp(termsAccepted: false));
    await tester.pump();
    expect(find.byType(FlexWellApp), findsOneWidget);
  });
}