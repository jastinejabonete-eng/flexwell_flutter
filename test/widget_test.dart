import 'package:flutter_test/flutter_test.dart';
import 'package:flexwell_flutter/main.dart';

// NOTE: these tests only exercise the terms gate. Any test that navigates past
// the gate into MainNavigationScreen touches FirebaseAuth / Cloud Firestore,
// which requires Firebase.initializeApp() and a platform channel -- neither of
// which exists in the widget-test environment. So we assert on the gate itself,
// not on the post-acceptance navigation.
void main() {
  testWidgets('App launches to terms gate when terms not accepted', (tester) async {
    await tester.pumpWidget(const FlexWellApp(termsAccepted: false));
    await tester.pump();
    // The app widget itself mounts without throwing.
    expect(find.byType(FlexWellApp), findsOneWidget);
    // And the terms gate is what is showing.
    expect(find.text('TERMS & CONDITIONS'), findsOneWidget);
  });
}
