import 'package:flutter/cupertino.dart';

import '../main.dart';

/// Simple month calendar: 7 columns, one row per week. Days present in
/// [completedDays] (compared by calendar day) get a rose dot underneath.
/// Previous / next month buttons; defaults to the current month.
class CalendarView extends StatefulWidget {
  const CalendarView({required this.completedDays, super.key});

  final Set<DateTime> completedDays;

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  bool _isCompleted(DateTime day) {
    return widget.completedDays.any(
      (d) => d.year == day.year && d.month == day.month && d.day == day.day,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final base = CupertinoTheme.of(context).textTheme.textStyle;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    final line = isDark ? JimColors.darkLine : JimColors.line;
    final today = DateTime.now();
    final firstDay = DateTime(_month.year, _month.month, 1);
    // Sunday-first grid: weekday 7 (Sunday) -> 0 offset.
    final leadingBlanks = firstDay.weekday % 7;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = <Widget>[];
    for (var i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      final done = _isCompleted(date);
      cells.add(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isToday
                    ? JimColors.rose
                    : const Color(0x00000000),
                shape: BoxShape.circle,
                border: isToday
                    ? null
                    : Border.all(color: line),
              ),
              child: Text(
                '$day',
                style: base.copyWith(
                  fontSize: 14,
                  fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
                  color: isToday
                      ? CupertinoColors.white
                      : (isDark ? JimColors.darkText : JimColors.ink),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: done ? JimColors.rose : const Color(0x00000000),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_monthNames[_month.month - 1]} ${_month.year}',
                style: base.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => setState(() {
                _month = DateTime(_month.year, _month.month - 1);
              }),
              child: const Icon(CupertinoIcons.chevron_left),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => setState(() {
                _month = DateTime(_month.year, _month.month + 1);
              }),
              child: const Icon(CupertinoIcons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: const ['S', 'M', 'T', 'W', 'T', 'F', 'S']
              .map(
                (d) => Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6F6A62),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 0,
          childAspectRatio: 0.85,
          children: cells,
        ),
        const SizedBox(height: 4),
        Text(
          'Rose dot — a chapter was finished that day.',
          style: base.copyWith(fontSize: 13, color: muted, height: 1.45),
        ),
      ],
    );
  }
}
