import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flexwell_flutter/app_colors.dart';
import 'package:flexwell_flutter/main.dart';

// NOTE: these tests only exercise the terms gate. Any test that navigates past
// the gate into MainNavigationScreen touches FirebaseAuth / Cloud Firestore,
// which requires Firebase.initializeApp() and a platform channel -- neither of
// which exists in the widget-test environment. So we assert on the gate itself,
// not on the post-acceptance navigation.
void main() {
  testWidgets('App launches to terms gate when terms not accepted', (
    tester,
  ) async {
    await tester.pumpWidget(const FlexWellApp(termsAccepted: false));
    await tester.pump();
    // The app widget itself mounts without throwing.
    expect(find.byType(FlexWellApp), findsOneWidget);
    // And the terms gate is what is showing.
    expect(find.text('Terms & Conditions'), findsOneWidget);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.useMaterial3, isTrue);
    expect(app.theme!.colorScheme.primary, AppColors.primary);
    expect(app.darkTheme!.colorScheme.primary, AppColors.accent);
  });
}
