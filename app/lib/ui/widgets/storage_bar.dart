import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// A drive's capacity as one bar: used space in ink, the part of it that
/// can be reclaimed hatched in amber at the end of the used run, free space
/// as the bare track.
class StorageBar extends StatelessWidget {
  const StorageBar({
    super.key,
    required this.total,
    required this.used,
    required this.reclaimable,
    this.height = 28,
  });

  final int total;
  final int used;
  final int reclaimable;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      label: 'Drive usage',
      value: total == 0
          ? ''
          : '${(used * 100 / total).round()} percent used, '
              '${(reclaimable * 100 / total).round()} percent reclaimable',
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _BarPainter(
            total: total,
            used: used,
            reclaimable: math.min(reclaimable, used),
            ink: t.ink,
            amber: t.amber,
            track: t.track,
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.total,
    required this.used,
    required this.reclaimable,
    required this.ink,
    required this.amber,
    required this.track,
  });

  final int total;
  final int used;
  final int reclaimable;
  final Color ink;
  final Color amber;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 5);
    final whole = RRect.fromRectAndRadius(Offset.zero & size, radius);
    canvas
      ..save()
      ..clipRRect(whole)
      ..drawRect(Offset.zero & size, Paint()..color = track);
    if (total > 0) {
      final usedW = size.width * used / total;
      final reclaimW = size.width * reclaimable / total;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, usedW, size.height),
        Paint()..color = ink,
      );
      if (reclaimW > 0) {
        final r = Rect.fromLTWH(usedW - reclaimW, 0, reclaimW, size.height);
        canvas
          ..save()
          ..clipRect(r)
          ..drawRect(r, Paint()..color = amber);
        // Diagonal hatching: the highlighter mark over what can go.
        final stripe = Paint()
          ..color = ink.withValues(alpha: 0.28)
          ..strokeWidth = 2;
        for (var x = r.left - size.height; x < r.right; x += 7) {
          canvas.drawLine(
            Offset(x, size.height),
            Offset(x + size.height, 0),
            stripe,
          );
        }
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.total != total ||
      old.used != used ||
      old.reclaimable != reclaimable ||
      old.ink != ink ||
      old.amber != amber;
}

/// Small swatch + label + figure used under the bar.
class LegendItem extends StatelessWidget {
  const LegendItem({
    super.key,
    required this.label,
    required this.value,
    required this.swatch,
    this.hatched = false,
  });

  final String label;
  final String value;
  final Color swatch;
  final bool hatched;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CustomPaint(
            painter: _BarPainter(
              total: 1,
              used: 1,
              reclaimable: hatched ? 1 : 0,
              ink: swatch == t.amber ? t.ink : swatch,
              amber: t.amber,
              track: swatch,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: t.muted, fontSize: 13)),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            color: t.ink,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFeatures: tabular,
          ),
        ),
      ],
    );
  }
}
