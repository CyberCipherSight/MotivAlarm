import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/alarm_list_screen.dart';
import 'screens/permission_setup_screen.dart';
import 'screens/settings_screen.dart';
import 'services/backup_service.dart';
import 'services/video_preview_navigation.dart';
import 'utils/constants.dart';

class VideoAlarmClockApp extends StatelessWidget {
  const VideoAlarmClockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      navigatorObservers: [videoPreviewRouteObserver],
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppConstants.primaryBlue,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8FB),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppConstants.primaryBlue,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF080D14),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        useMaterial3: true,
      ),
      routes: {
        AlarmListScreen.routeName: (_) => const AlarmListScreen(),
        PermissionSetupScreen.routeName: (_) => const PermissionSetupScreen(),
        SettingsScreen.routeName: (_) => const SettingsScreen(),
      },
      home: const _StartupGate(),
    );
  }
}

class _StartupGate extends StatelessWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasSeenSetup(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data!
            ? const AlarmListScreen()
            : const PermissionSetupScreen();
      },
    );
  }

  Future<bool> _hasSeenSetup() async {
    final prefs = await SharedPreferences.getInstance();
    // Post-restore self-heal: Android Auto Backup restores the data but not
    // the registered alarms (and the native firing cache is deliberately
    // excluded from backup), so re-register everything on start. Idempotent
    // and cheap on a normal launch; fire-and-forget so startup isn't blocked.
    // ignore: unawaited_futures
    BackupService().rescheduleAll().catchError((_) {});
    return prefs.getBool('motivalarm.setupSeen') ?? false;
  }
}
