import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motivalarm/widgets/local_audio_picker_card.dart';
import 'package:motivalarm/widgets/video_picker_card.dart';

void main() {
  const native = MethodChannel('motivalarm/native');
  const picker = MethodChannel('miguelruivo.flutter.plugins.filepicker');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];

  setUp(() {
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(native, (
      call,
    ) async {
      calls.add(call.method);
      return null;
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(native, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, null);
  });

  Future<void> show(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  Widget video() => VideoPickerCard(
    videoUri: null,
    durationSeconds: null,
    onVideoChanged: (_, _) => fail('An unreadable video must not be selected'),
  );

  testWidgets('video picker failure releases busy state', (tester) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (_) async {
      throw PlatformException(code: 'permission_denied');
    });
    await show(tester, video());
    await tester.tap(find.text('Choose Video'));
    await tester.pumpAndSettle();
    expect(find.text('Could not read this video.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty or cancelled media picks keep the current selection', (
    tester,
  ) async {
    for (final result in [null, <Map<String, Object?>>[]]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        picker,
        (_) async => result,
      );
      await show(tester, video());
      await tester.tap(find.text('Choose Video'));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('deleted video validation failure is handled', (tester) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (_) async {
      return [
        {'name': 'deleted.mp4', 'size': 1, 'identifier': 'content://deleted/1'},
      ];
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(native, (_) async {
      throw PlatformException(code: 'MOTIVALARM_NATIVE_ERROR');
    });
    await show(tester, video());
    await tester.tap(find.text('Choose Video'));
    await tester.pumpAndSettle();
    expect(find.text('Could not read this video.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finishing validation after disposal has no side effects', (
    tester,
  ) async {
    final validation = Completer<Object?>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (_) async {
      return [
        {'name': 'video.mp4', 'size': 1, 'identifier': 'content://video/1'},
      ];
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) {
      calls.add(call.method);
      return validation.future;
    });
    await show(tester, video());
    await tester.tap(find.text('Choose Video'));
    await tester.pump();
    expect(calls, contains('validateVideo'));
    await tester.pumpWidget(const SizedBox());
    validation.complete({'valid': true, 'durationSeconds': 3});
    await tester.pumpAndSettle();
    expect(calls, isNot(contains('persistVideoUriPermission')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleted audio preview can be retried and removed', (
    tester,
  ) async {
    String? selected = 'content://deleted/audio';
    binding.defaultBinaryMessenger.setMockMethodCallHandler(native, (
      call,
    ) async {
      calls.add(call.method);
      throw PlatformException(code: 'MOTIVALARM_NATIVE_ERROR');
    });
    await show(
      tester,
      LocalAudioPickerCard(
        audioUri: selected,
        onAudioChanged: (uri) => selected = uri,
      ),
    );
    await tester.tap(find.byTooltip('Preview audio'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Preview audio'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Remove audio'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('audio picker failure does not replace the selected audio', (
    tester,
  ) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (_) async {
      throw PlatformException(code: 'permission_denied');
    });
    await show(
      tester,
      LocalAudioPickerCard(
        audioUri: 'content://existing/audio',
        onAudioChanged: (_) => fail('Existing audio must be preserved'),
      ),
    );
    await tester.tap(find.text('Change Music'));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
