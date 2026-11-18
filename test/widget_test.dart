import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:routine_app/main.dart';

void main() {
  testWidgets('Routine Tracker dashboard builds', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomePage(isDark: true, onThemeChanged: (_) {}),
    ));
    expect(find.text('Lifetime Overview'), findsOneWidget);
  });
}
