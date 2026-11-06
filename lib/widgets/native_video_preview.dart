import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../services/video_preview_navigation.dart';

/// Embeds the same native `android.widget.VideoView`/`MediaPlayer` the real
/// alarm-ringing screen uses, instead of `video_player`/ExoPlayer. ExoPlayer
/// (via Media3) selects a MediaTek hardware decoder for certain resolutions
/// that renders a corrupted/torn texture on MediaTek-chipset devices — a
/// confirmed, open Flutter engine bug (flutter/flutter#174026) with no fix
/// at the Dart API level, affecting portrait and landscape clips alike on
/// affected hardware. `VideoView` goes through a different decoder-selection
/// path that doesn't hit it, which is why the ringing screen never shows
/// this corruption. Used for in-app preview surfaces (home feed, video
/// picker) instead of `video_player`.
///
/// Uses full Hybrid Composition ([PlatformViewsService.initExpensiveAndroidView])
/// rather than the default `AndroidView` texture-bridge mode: `VideoView`
/// renders via a `SurfaceView` internally, and the default texture/buffer
/// bridge between that SurfaceView and Flutter's compositor can briefly
/// desync during window resizes (e.g. the keyboard opening for a nearby
/// text field), flashing the video frame in the wrong place for a moment —
/// a well-documented Flutter limitation with SurfaceView-backed platform
/// views. Embedding the real Android View directly in the view hierarchy
/// (no texture bridge at all) avoids that class of glitch entirely; the
/// extra compositing cost is a non-issue for the handful of small,
/// non-interactive preview surfaces this is used for.
class NativeVideoPreview extends StatefulWidget {
  const NativeVideoPreview({
    required this.uri,
    this.muted = true,
    this.looping = true,
    this.playing = true,
    super.key,
  });

  final String uri;
  final bool muted;
  final bool looping;
  final bool playing;

  @override
  State<NativeVideoPreview> createState() => _NativeVideoPreviewState();
}

class _NativeVideoPreviewState extends State<NativeVideoPreview>
    with WidgetsBindingObserver, RouteAware {
  static const _viewType = 'motivalarm/native_video_view';

  MethodChannel? _channel;
  ModalRoute<dynamic>? _route;
  bool _routeVisible = true;
  bool _appActive = true;
  bool _tickerEnabled = true;
  int _generation = 0;

  bool get _visible => _routeVisible && _appActive && _tickerEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appActive = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route != route) {
      videoPreviewRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) videoPreviewRouteObserver.subscribe(this, route);
    }
    _routeVisible = route?.isCurrent ?? true;
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncNativeState();
  }

  void _syncNativeState() {
    _channel
        ?.invokeMethod<void>('setVisibility', {
          'visible': _visible,
          'playing': widget.playing,
        })
        .catchError((_) {});
    if (!_visible) {
      _channel = null;
      _generation++;
    }
  }

  void _setRouteVisible(bool visible) {
    if (!mounted || _routeVisible == visible) return;
    setState(() => _routeVisible = visible);
    // Hide the actual SurfaceView immediately, before route transitions.
    _syncNativeState();
  }

  @override
  void didPushNext() => _setRouteVisible(false);

  @override
  void didPopNext() => _setRouteVisible(true);

  @override
  void didPop() => _setRouteVisible(false);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() => _appActive = state == AppLifecycleState.resumed);
    _syncNativeState();
  }

  @override
  void didUpdateWidget(covariant NativeVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri ||
        oldWidget.muted != widget.muted ||
        oldWidget.looping != widget.looping) {
      _channel
          ?.invokeMethod<void>('setVisibility', {'visible': false})
          .catchError((_) {});
      _channel = null;
      _generation++;
    }
    _syncNativeState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    videoPreviewRouteObserver.unsubscribe(this);
    _channel
        ?.invokeMethod<void>('setVisibility', {'visible': false})
        .catchError((_) {});
    _channel = null;
    super.dispose();
  }

  Map<String, dynamic> get _creationParams => {
    'uri': widget.uri,
    'muted': widget.muted,
    'looping': widget.looping,
    'playing': widget.playing,
  };

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      // Release decoders/surfaces for covered routes, retaining their layout.
      return const SizedBox.expand();
    }
    final generation = _generation;
    return PlatformViewLink(
      key: ValueKey((widget.uri, widget.muted, widget.looping, generation)),
      viewType: _viewType,
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
      onCreatePlatformView: (params) {
        final controller = PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: _viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: _creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        );
        controller.addOnPlatformViewCreatedListener((id) {
          params.onPlatformViewCreated(id);
          final channel = MethodChannel('${_viewType}_$id');
          if (!mounted || generation != _generation || !_visible) {
            channel
                .invokeMethod<void>('setVisibility', {'visible': false})
                .catchError((_) {});
            return;
          }
          _channel = channel;
          _syncNativeState();
        });
        controller.create();
        return controller;
      },
    );
  }
}
