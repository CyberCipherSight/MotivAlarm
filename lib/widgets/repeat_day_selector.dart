import 'package:flutter/material.dart';

class RepeatDaySelector extends StatelessWidget {
  const RepeatDaySelector({
    required this.selectedDays,
    required this.onChanged,
    super.key,
  });

  final List<int> selectedDays;
  final ValueChanged<List<int>> onChanged;

  static const _days = [
    (1, 'M'),
    (2, 'T'),
    (3, 'W'),
    (4, 'T'),
    (5, 'F'),
    (6, 'S'),
    (7, 'S'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _days.map((day) {
        final selected = selectedDays.contains(day.$1);
        return Expanded(
          child: Center(
            child: _DayCircle(
              label: day.$2,
              selected: selected,
              onTap: () {
                final updated = [...selectedDays];
                if (selected) {
                  updated.remove(day.$1);
                } else {
                  updated.add(day.$1);
                }
                updated.sort();
                onChanged(updated);
              },
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DayCircle extends StatelessWidget {
  const _DayCircle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? const Color(0xFFE7ECF4) : Colors.transparent,
          border: Border.all(
            color: selected ? Colors.transparent : const Color(0xFF3A3A3A),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white70,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
