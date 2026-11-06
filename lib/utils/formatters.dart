import 'package:intl/intl.dart';

const _weekdayNames = {
  1: 'Mon',
  2: 'Tue',
  3: 'Wed',
  4: 'Thu',
  5: 'Fri',
  6: 'Sat',
  7: 'Sun',
};

String formatAlarmTime(int hour, int minute) {
  final date = DateTime(2024, 1, 1, hour, minute);
  return DateFormat('h:mm a').format(date);
}

String formatRepeatDays(List<int> days) {
  if (days.isEmpty) return 'One time';
  if (days.length == 7) return 'Every day';
  const weekdays = [1, 2, 3, 4, 5];
  const weekend = [6, 7];
  if (_sameDays(days, weekdays)) return 'Weekdays';
  if (_sameDays(days, weekend)) return 'Weekend';
  return days
      .map((day) => _weekdayNames[day] ?? '')
      .where((d) => d.isNotEmpty)
      .join(' ');
}

bool _sameDays(List<int> days, List<int> target) {
  final set = days.toSet();
  return set.length == target.length && target.every(set.contains);
}
