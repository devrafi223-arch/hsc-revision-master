import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../main.dart';
import '../models/milestone.dart';

/// Chapter-complete celebration: a Cupertino dialog with a short
/// confetti burst (plain CustomPaint rectangles, no new dependency)
/// and the milestone name. Call [MilestoneCelebration.show] once per
/// chapter — the caller dedupes (see HomeScreen).
class MilestoneCelebration {
  static void show(BuildContext context, String milestoneName) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 110,
              child: _ConfettiBurst(),
            ),
            const SizedBox(height: 12),
            const Text(
              'Milestone unlocked!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              milestoneName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, height: 1.45),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Keep going'),
          ),
        ],
      ),
    );
  }
}

/// Falling coloured rectangles, animated once over ~1.4s.
class _ConfettiBurst extends StatefulWidget {
  const _ConfettiBurst();

  @override
  State<_ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<_ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiPiece> _pieces;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    // Fixed seed so the burst looks the same every time it is shown.
    final random = math.Random(42);
    const colors = [
      Color(0xFFA9716B),
      Color(0xFFCF9A92),
      Color(0xFFE9E4DA),
      Color(0xFF6F6A62),
      Color(0xFFD9A441),
    ];
    _pieces = List.generate(28, (_) {
      return _ConfettiPiece(
        x: random.nextDouble(),
        delay: random.nextDouble() * 0.35,
        speed: 0.55 + random.nextDouble() * 0.45,
        size: 5 + random.nextDouble() * 7,
        rotation: random.nextDouble() * math.pi,
        color: colors[random.nextInt(colors.length)],
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _ConfettiPainter(_controller.value, _pieces),
      ),
    );
  }
}

class _ConfettiPiece {
  const _ConfettiPiece({
    required this.x,
    required this.delay,
    required this.speed,
    required this.size,
    required this.rotation,
    required this.color,
  });

  final double x, delay, speed, size, rotation;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.progress, this.pieces);

  final double progress;
  final List<_ConfettiPiece> pieces;

  @override
  void paint(Canvas canvas, Size size) {
    for (final piece in pieces) {
      final local = (progress - piece.delay) / (1 - piece.delay);
      if (local <= 0) continue;
      final clamped = local.clamp(0.0, 1.0);
      final y = clamped * piece.speed * size.height;
      final alpha = (1 - clamped).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = piece.color.withValues(alpha: alpha);
      canvas.save();
      canvas.translate(piece.x * size.width, y);
      canvas.rotate(piece.rotation + clamped * 4);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: piece.size,
          height: piece.size * 0.6,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

/// A strip of earned-milestone chips (name + subject).
class MilestoneList extends StatelessWidget {
  const MilestoneList({required this.milestones, super.key});

  final List<Milestone> milestones;

  @override
  Widget build(BuildContext context) {
    final isDark =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final base = CupertinoTheme.of(context).textTheme.textStyle;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    if (milestones.isEmpty) {
      return Text(
        'No milestones yet — finish a chapter (6/6) to unlock your first one.',
        style: base.copyWith(fontSize: 14, color: muted, height: 1.45),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: milestones
          .map(
            (m) => Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: JimColors.rose.withValues(alpha: isDark ? 0.18 : 0.08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: JimColors.rose.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                m.name,
                style: base.copyWith(fontSize: 13, height: 1.45),
              ),
            ),
          )
          .toList(),
    );
  }
}
