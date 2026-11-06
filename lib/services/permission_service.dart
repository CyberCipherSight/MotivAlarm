import 'package:permission_handler/permission_handler.dart' as ph;

import '../models/permission_status_model.dart';
import 'native_alarm_bridge.dart';

/// Permissions that Android can grant through a single native system
/// dialog (via [ph.Permission.request]), as opposed to ones that only
/// have a Settings-screen deep link (e.g. full-screen intent access).
const _directRequestKeys = {'notification', 'exactAlarm', 'battery'};

/// Permissions Android gives no API to verify, so [PermissionStatusModel]
/// always reports them as ungranted — the UI shouldn't block progress on
/// that and should just treat a tap as acknowledgement.
const _unverifiableKeys = {'backgroundRestrictions'};

class PermissionService {
  PermissionService({NativeAlarmBridge? bridge})
    : _bridge = bridge ?? const NativeAlarmBridge();

  final NativeAlarmBridge _bridge;

  Future<List<PermissionStatusModel>> getStatuses() =>
      _bridge.getPermissionStatuses();

  /// Whether [key] can be granted with a one-tap native dialog rather than
  /// a trip to the system Settings app.
  bool isDirectRequest(String key) => _directRequestKeys.contains(key);

  /// Whether [key]'s grant state can't be checked, so the UI should treat
  /// any tap as acknowledged rather than waiting for `granted` to flip.
  bool isUnverifiable(String key) => _unverifiableKeys.contains(key);

  /// Requests [key] the easiest way Android allows: a native system
  /// dialog when one exists, otherwise the matching Settings screen.
  Future<void> request(String key) async {
    switch (key) {
      case 'notification':
        await _requestWithSettingsFallback(ph.Permission.notification);
      case 'exactAlarm':
        await ph.Permission.scheduleExactAlarm.request();
      case 'battery':
        await ph.Permission.ignoreBatteryOptimizations.request();
      case 'fullScreen':
        await _bridge.openFullScreenIntentSettings();
      case 'backgroundRestrictions':
        await _bridge.openBackgroundRestrictionSettings();
      default:
        await ph.openAppSettings();
    }
  }

  Future<void> openReference(String url) => _bridge.openUrl(url);

  /// Requests a permission; if Android refuses to show the dialog again
  /// because it was already permanently denied, falls through to the
  /// app's Settings page so the button never becomes a dead end.
  Future<void> _requestWithSettingsFallback(ph.Permission permission) async {
    final status = await permission.request();
    if (status.isPermanentlyDenied) {
      await ph.openAppSettings();
    }
  }
}
