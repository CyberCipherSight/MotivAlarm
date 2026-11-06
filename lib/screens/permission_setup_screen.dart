import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/permission_status_model.dart';
import '../services/permission_service.dart';
import 'alarm_list_screen.dart';

typedef _PermissionCopy = ({String headline, String body, IconData icon});

const _copy = <String, _PermissionCopy>{
  'exactAlarm': (
    headline: 'Wake Up at the Exact Minute',
    body: 'Lets MotivAlarm ring precisely on time, every time.',
    icon: Icons.alarm_rounded,
  ),
  'notification': (
    headline: 'Never Miss an Alert',
    body: "Shows your alarm the moment it's about to ring.",
    icon: Icons.notifications_active_rounded,
  ),
  'battery': (
    headline: 'Guarantee On-Time Wakeup',
    body:
        'Stops your phone from delaying or silencing the alarm in the '
        'background.',
    icon: Icons.battery_charging_full_rounded,
  ),
  'fullScreen': (
    headline: 'See Your Video Instantly',
    body: 'Lets your motivational video take over the screen, even when locked.',
    icon: Icons.fullscreen_rounded,
  ),
  'backgroundRestrictions': (
    headline: "Stop Your Phone From Blocking It",
    body:
        "Some phone makers add their own battery rules on top of Android's "
        'that can silently stop alarms. One quick check avoids that.',
    icon: Icons.phonelink_lock_rounded,
  ),
};

const _fallbackCopy = (
  headline: 'One More Thing',
  body: 'MotivAlarm needs this to keep your alarms reliable.',
  icon: Icons.shield_rounded,
);

class PermissionSetupScreen extends StatefulWidget {
  const PermissionSetupScreen({super.key});

  static const routeName = '/permissions';

  @override
  State<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends State<PermissionSetupScreen>
    with WidgetsBindingObserver {
  final _service = PermissionService();
  final _pageController = PageController();

  List<PermissionStatusModel> _statuses = const [];
  bool _loading = true;
  bool _requesting = false;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatuses();
  }

  Future<void> _load() async {
    final statuses = await _service.getStatuses();
    if (!mounted) return;
    setState(() {
      _statuses = statuses;
      _loading = false;
    });
    // Skip straight to whatever still needs attention instead of always
    // restarting at page 1, so re-visiting this screen after granting most
    // permissions doesn't make the user tap "Next" through done ones again.
    final firstUngranted = statuses.indexWhere((status) => !status.granted);
    if (firstUngranted > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pageController.jumpToPage(firstUngranted);
        setState(() => _pageIndex = firstUngranted);
      });
    }
  }

  Future<void> _refreshStatuses() async {
    final statuses = await _service.getStatuses();
    if (!mounted) return;
    setState(() => _statuses = statuses);
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('motivalarm.setupSeen', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AlarmListScreen.routeName);
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _advanceFrom(int index) async {
    if (index == _statuses.length - 1) {
      await _finish();
    } else {
      _goToPage(index + 1);
    }
  }

  Future<void> _handlePrimaryAction(int index) async {
    final status = _statuses[index];
    if (status.granted) {
      await _advanceFrom(index);
      return;
    }
    setState(() => _requesting = true);
    await _service.request(status.key);
    final refreshed = await _service.getStatuses();
    if (!mounted) return;
    setState(() {
      _statuses = refreshed;
      _requesting = false;
    });
    // Unverifiable keys (OEM background restrictions) never report granted —
    // tapping through to the settings screen is the only signal we get, so
    // treat that as acknowledgement rather than blocking progress forever.
    if (refreshed[index].granted || _service.isUnverifiable(status.key)) {
      await _advanceFrom(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 6),
              child: Text(
                '${_pageIndex + 1} / ${_statuses.length}',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _statuses.length,
                onPageChanged: (index) => setState(() => _pageIndex = index),
                itemBuilder: (context, index) {
                  final status = _statuses[index];
                  final isLast = index == _statuses.length - 1;
                  final copy = _copy[status.key] ?? _fallbackCopy;
                  final label = status.granted
                      ? (isLast ? 'Start Waking Up' : 'Next')
                      : (_service.isDirectRequest(status.key)
                            ? 'Allow'
                            : 'Open Settings');
                  return _PermissionPage(
                    copy: copy,
                    buttonLabel: label,
                    busy: _requesting,
                    onPrimaryAction: () => _handlePrimaryAction(index),
                    referenceUrl: status.referenceUrl,
                    onOpenReference: status.referenceUrl == null
                        ? null
                        : () => _service.openReference(status.referenceUrl!),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionPage extends StatelessWidget {
  const _PermissionPage({
    required this.copy,
    required this.buttonLabel,
    required this.busy,
    required this.onPrimaryAction,
    this.referenceUrl,
    this.onOpenReference,
  });

  final _PermissionCopy copy;
  final String buttonLabel;
  final bool busy;
  final VoidCallback onPrimaryAction;
  final String? referenceUrl;
  final VoidCallback? onOpenReference;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
      child: Column(
        children: [
          Expanded(
            flex: 6,
            child: Center(child: _PulsingGlowIcon(icon: copy.icon)),
          ),
          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  copy.headline,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  copy.body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
                if (onOpenReference != null) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: onOpenReference,
                    child: const Text(
                      'See exact steps for your phone',
                      style: TextStyle(
                        color: Color(0xFF5DA2FF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: FilledButton(
              onPressed: busy ? null : onPrimaryAction,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2F80ED),
                disabledBackgroundColor: const Color(0xFF1B3A5C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      buttonLabel,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingGlowIcon extends StatefulWidget {
  const _PulsingGlowIcon({required this.icon});

  final IconData icon;

  @override
  State<_PulsingGlowIcon> createState() => _PulsingGlowIconState();
}

class _PulsingGlowIconState extends State<_PulsingGlowIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        final scale = 0.92 + (t * 0.16);
        final glow = 0.18 + (t * 0.22);
        return Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFF2F80ED).withValues(alpha: glow),
                Colors.transparent,
              ],
            ),
          ),
          alignment: Alignment.center,
          child: Transform.scale(
            scale: scale,
            child: Icon(widget.icon, color: Colors.white, size: 96),
          ),
        );
      },
    );
  }
}
