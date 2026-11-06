import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motivalarm/screens/alarm_list_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('alarm list shows clock-style home', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('motivalarm/native');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => <Object?>[],
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    await tester.pumpWidget(const MaterialApp(home: AlarmListScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Video Alarm'), findsWidgets);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.text('No video alarms yet'), findsOneWidget);
    expect(find.text('World clock'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
