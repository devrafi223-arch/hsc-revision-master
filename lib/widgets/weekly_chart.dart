import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart';

/// Weekly progress chart: 7 rose bars, one per day (S M T W T F S).
/// No chart dependency — plain Containers. [chaptersPerDay] must have
/// exactly 7 entries (Mon..Sun order is not assumed; the caller passes
/// the 7 days ending today, labelled S M T W T F S left to right).
class WeeklyChart extends StatelessWidget {
  const WeeklyChart({required this.chaptersPerDay, super.key});

  final List<int> chaptersPerDay;

  static const List<String> _labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    final line = isDark ? JimColors.darkLine : JimColors.line;
    final days = List<int>.generate(
      7,
      (i) => i < chaptersPerDay.length ? chaptersPerDay[i] : 0,
    );
    final max = days.fold<int>(0, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      days[i] == 0 ? '' : '${days[i]}',
                      style: base.copyWith(fontSize: 12, color: muted),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: max == 0 ? 8 : 8 + (days[i] / max) * 92,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: days[i] == 0 ? line : JimColors.rose,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _labels[i],
                      style: base.copyWith(fontSize: 13, color: muted),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
