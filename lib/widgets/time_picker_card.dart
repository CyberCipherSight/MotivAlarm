import 'package:flutter/material.dart';

import '../utils/formatters.dart';

class TimePickerCard extends StatelessWidget {
  const TimePickerCard({
    required this.hour,
    required this.minute,
    required this.onTimeChanged,
    super.key,
  });

  final int hour;
  final int minute;
  final ValueChanged<TimeOfDay> onTimeChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: hour, minute: minute),
          builder: (context, child) {
            return Theme(
              data: ThemeData.dark(useMaterial3: true).copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: Color(0xFFE8EEF8),
                  surface: Color(0xFF171717),
                ),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) onTimeChanged(picked);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Column(
          children: [
            Text(
              formatAlarmTime(hour, minute),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w200,
                letterSpacing: 0,
                fontSize: 96,
                height: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white38,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}
