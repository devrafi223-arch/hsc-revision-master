import 'dart:async';

import 'package:flutter/cupertino.dart';

/// 25-minute Pomodoro countdown, Cupertino style. [initialDuration] exists
/// so widget tests can use a short timer instead of waiting 25 minutes.
class PomodoroTimer extends StatefulWidget {
  const PomodoroTimer({super.key, this.initialDuration = const Duration(minutes: 25)});

  final Duration initialDuration;

  @override
  State<PomodoroTimer> createState() => _PomodoroTimerState();
}

class _PomodoroTimerState extends State<PomodoroTimer> {
  late Duration _remaining;
  Timer? _timer;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.initialDuration;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    if (_remaining <= Duration.zero) _remaining = widget.initialDuration;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remaining > Duration.zero) {
          _remaining -= const Duration(seconds: 1);
        }
        if (_remaining <= Duration.zero) {
          _running = false;
          _timer?.cancel();
        }
      });
    });
    setState(() => _running = true);
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _running = false);
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _running = false;
      _remaining = widget.initialDuration;
    });
  }

  String get _label {
    final minutes = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = CupertinoTheme.of(context).textTheme.textStyle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: Text(
            _label,
            key: ValueKey(_label),
            style: textStyle.copyWith(
              fontSize: 40,
              fontWeight: FontWeight.w600,
              height: 1.2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _remaining <= Duration.zero
              ? 'Done — take a 5-minute break.'
              : _running
                  ? 'Focus — no phone, just this chapter.'
                  : 'Pomodoro — 25 minutes of focused revision.',
          key: const Key('pomodoro-time'),
          style: textStyle.copyWith(height: 1.45),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          children: [
            CupertinoButton.filled(
              key: const Key('pomodoro-start'),
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              borderRadius: BorderRadius.circular(14),
              onPressed: _running ? _pause : _start,
              child: Text(_running ? 'Pause' : 'Start'),
            ),
            CupertinoButton(
              key: const Key('pomodoro-reset'),
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              borderRadius: BorderRadius.circular(14),
              onPressed: _reset,
              child: const Text('Reset'),
            ),
          ],
        ),
      ],
    );
  }
}
