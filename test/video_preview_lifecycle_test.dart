import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motivalarm/services/video_preview_navigation.dart';
import 'package:motivalarm/widgets/native_video_preview.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final created = <int, Map<dynamic, dynamic>>{};
  final disposed = <int>[];
  final visibility = <int, List<Map<dynamic, dynamic>>>{};
  final navigator = GlobalKey<NavigatorState>();
  Completer<void>? pendingCreation;

  setUp(() async {
    created.clear();
    disposed.clear();
    visibility.clear();
    pendingCreation = null;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async {
        final args = call.arguments as Map<dynamic, dynamic>;
        final id = args['id'] as int;
        if (call.method == 'create') {
          created[id] =
              const StandardMessageCodec().decodeMessage(
                    ByteData.sublistView(args['params'] as Uint8List),
                  )
                  as Map<dynamic, dynamic>;
          expect(args['hybrid'], isTrue);
          visibility[id] = [];
          binding.defaultBinaryMessenger.setMockMethodCallHandler(
            MethodChannel('motivalarm/native_video_view_$id'),
            (request) async {
              if (request.method == 'setVisibility') {
                visibility[id]!.add(request.arguments as Map<dynamic, dynamic>);
              }
              return null;
            },
          );
          await pendingCreation?.future;
        } else if (call.method == 'dispose') {
          disposed.add(id);
        }
        return null;
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      null,
    );
    for (final id in created.keys) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel('motivalarm/native_video_view_$id'),
        null,
      );
    }
  });

  Future<void> show(WidgetTester tester, Widget preview) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [videoPreviewRouteObserver],
        home: Scaffold(body: SizedBox(width: 240, height: 160, child: preview)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('covered previews hide before navigation and return afterwards', (
    tester,
  ) async {
    await show(tester, const NativeVideoPreview(uri: '/first.mp4'));
    final firstId = created.keys.single;
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Permissions')),
        ),
      ),
    );
    await tester.pump();
    expect(visibility[firstId]!.last['visible'], isFalse);
    await tester.pumpAndSettle();
    expect(disposed, contains(firstId));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(created.length, 2);
    final resumedId = created.keys.last;
    expect(visibility[resumedId]!.last, {'visible': true, 'playing': true});
    await close(tester);
  });

  testWidgets('menus hide all previews and restore user paused state', (
    tester,
  ) async {
    await show(
      tester,
      const Row(
        children: [
          Expanded(child: NativeVideoPreview(uri: '/first.mp4')),
          Expanded(
            child: NativeVideoPreview(uri: '/second.mp4', playing: false),
          ),
        ],
      ),
    );
    final oldIds = created.keys.toList();
    unawaited(
      showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(content: Text('Menu')),
      ),
    );
    await tester.pumpAndSettle();
    expect(disposed, containsAll(oldIds));
    for (final id in oldIds) {
      expect(visibility[id]!.last['visible'], isFalse);
    }
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    final pausedId = created.keys.lastWhere(
      (id) => created[id]!['uri'] == '/second.mp4',
    );
    expect(visibility[pausedId]!.last['playing'], isFalse);
    await close(tester);
  });

  testWidgets('native alarm preview lifecycle releases editor video', (
    tester,
  ) async {
    await show(
      tester,
      const NativeVideoPreview(uri: '/editor.mp4', muted: false),
    );
    final editorId = created.keys.single;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(visibility[editorId]!.last['visible'], isFalse);
    expect(disposed, contains(editorId));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(created.length, 2);
    expect(visibility[created.keys.last]!.last['visible'], isTrue);
    await close(tester);
  });

  testWidgets(
    'changing video without a parent key replaces the native player',
    (tester) async {
      await show(tester, const NativeVideoPreview(uri: '/old.mp4'));
      final oldId = created.keys.single;
      await show(tester, const NativeVideoPreview(uri: '/new.mp4'));
      expect(disposed, contains(oldId));
      expect(created[created.keys.last]!['uri'], '/new.mp4');
      await close(tester);
    },
  );

  testWidgets('delayed creation cannot reveal a video on another screen', (
    tester,
  ) async {
    pendingCreation = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [videoPreviewRouteObserver],
        home: const Scaffold(
          body: SizedBox(
            width: 200,
            height: 100,
            child: NativeVideoPreview(uri: '/slow.mp4'),
          ),
        ),
      ),
    );
    await tester.pump();
    final id = created.keys.single;
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Settings')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    pendingCreation!.complete();
    await tester.pumpAndSettle();
    expect(disposed, contains(id));
    expect(visibility[id]!.where((state) => state['visible'] == true), isEmpty);
    await close(tester);
  });
}
