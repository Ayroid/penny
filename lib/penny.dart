import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// The mascot: a copper coin with a green sprout, outlined in navy.
///
/// Six poses, and deliberately no disappointed one. A blown budget dims the
/// mark; it never turns the app against the person using it.
///
/// The five poses on the character sheet map onto the family's six names —
/// `Track` reads as thinking, `Save` (eyes closed, holding the pig) as rest,
/// `Invest` as focus, `Plan` (a ticked clipboard) as complete.
/// The constants are the family's pose vocabulary; the filenames are the ones
/// on Penny's own character sheet. They differ, and the `asset` field is where
/// the two are reconciled — `Penny.rest` is the pose called "Save" in the art,
/// where she is holding the piggy bank with her eyes closed.
enum Penny {
  standing('penny_default'),
  focus('penny_invest'),
  complete('penny_plan'),
  thinking('penny_track'),
  celebrate('penny_celebrate'),
  rest('penny_save');

  const Penny(this.asset);

  final String asset;

  String get path => 'assets/mascot/$asset.png';

  /// A missing pose falls back to the default rather than to a hole in the
  /// layout. The default itself falls back to the drawn mark.
  Penny? get fallback => this == Penny.standing ? null : Penny.standing;
}

/// One pose, at [size] tall.
///
/// Height only, never a square: the poses do not share an aspect ratio and
/// boxing them renders the wide ones short.
class PennyImage extends StatelessWidget {
  const PennyImage(this.pose, {super.key, this.size = 132, this.semanticLabel});

  final Penny pose;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      pose.path,
      height: size,
      fit: BoxFit.fitHeight,
      // The art is 512 tall and the largest use is 156. Without this a few MB
      // per pose sits in the image cache for no benefit.
      cacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      filterQuality: FilterQuality.medium,
      semanticLabel: semanticLabel,
      errorBuilder: (context, _, _) => pose.fallback == null
          // Nothing left to fall back to — draw the mark instead of leaving a
          // gap. This is also what runs before the art has been dropped in.
          ? CoinMark(size: size, semanticLabel: semanticLabel)
          : PennyImage(pose.fallback!,
              size: size, semanticLabel: semanticLabel),
    );
  }
}

/// Penny reduced to her silhouette: the coin and the sprout, drawn rather than
/// shipped.
///
/// Drawn because it has to scale from a 24px chip to a 512px splash mark and
/// recolour with the theme, which a raster cannot do. It is also what stands in
/// for a pose whose PNG is missing, so the app is complete before the art is.
class CoinMark extends StatelessWidget {
  const CoinMark({super.key, this.size = 132, this.semanticLabel});

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      child: CustomPaint(
        size: Size(size, size),
        painter: _CoinPainter(dark: isDark(context)),
      ),
    );
  }
}

class _CoinPainter extends CustomPainter {
  _CoinPainter({required this.dark});

  final bool dark;

  // The character's own colours, not the semantic tokens: this is the mascot,
  // and the mascot does not change hue when a category does.
  static const _face = Color(0xFFEFA76B);
  static const _shade = Color(0xFFDE9155);
  static const _leaf = Color(0xFF4CC26E);
  static const _leafShade = Color(0xFF35A957);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final line = dark ? const Color(0xFF0F1B3D) : navy;
    final stroke = s * 0.045;

    // The coin sits low; the sprout occupies the top fifth.
    final r = s * 0.34;
    final centre = Offset(size.width / 2, size.height - r - stroke);

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = line;

    // Stem.
    canvas.drawLine(
      Offset(centre.dx, centre.dy - r + stroke),
      Offset(centre.dx, centre.dy - r - s * 0.17),
      outline,
    );

    // Two leaves, mirrored around the stem.
    for (final left in [true, false]) {
      final dir = left ? -1.0 : 1.0;
      final base = Offset(centre.dx, centre.dy - r - s * 0.10);
      final tip = Offset(base.dx + dir * s * 0.20, base.dy - s * 0.13);
      final leaf = Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(
            base.dx + dir * s * 0.04, tip.dy - s * 0.05, tip.dx, tip.dy)
        ..quadraticBezierTo(
            tip.dx - dir * s * 0.02, base.dy - s * 0.01, base.dx, base.dy)
        ..close();
      canvas.drawPath(leaf, Paint()..color = left ? _leafShade : _leaf);
      canvas.drawPath(leaf, outline);
    }

    // Coin body, its inner rim, and a highlight at the upper left.
    canvas.drawCircle(centre, r, Paint()..color = _face);
    canvas.drawCircle(centre, r, outline);
    canvas.drawCircle(
      centre,
      r * 0.78,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.6
        ..color = _shade,
    );
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: r * 0.62),
      math.pi * 1.05,
      math.pi * 0.42,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.9
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.55),
    );

    // Eyes.
    final eye = Paint()..color = line;
    for (final dir in [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(centre.dx + dir * r * 0.32, centre.dy - r * 0.10),
          width: r * 0.17,
          height: r * 0.27,
        ),
        eye,
      );
    }

    // A closed smile, never a frown.
    canvas.drawArc(
      Rect.fromCircle(center: Offset(centre.dx, centre.dy + r * 0.12), radius: r * 0.24),
      math.pi * 0.15,
      math.pi * 0.7,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.8
        ..strokeCap = StrokeCap.round
        ..color = line,
    );
  }

  @override
  bool shouldRepaint(_CoinPainter old) => old.dark != dark;
}

/// The empty-state block: a pose, a headline, one muted line, one action.
///
/// This is the mascot's main job — empty screens and quiet moments, never
/// decoration on a screen that already has content.
class PennyMessage extends StatelessWidget {
  const PennyMessage({
    super.key,
    this.pose = Penny.standing,
    required this.headline,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.size = 132,
  });

  final Penny pose;
  final String headline;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double size;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PennyImage(pose, size: size, semanticLabel: 'Penny'),
            const SizedBox(height: 18),
            Text(headline, style: text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(body, style: text.bodySmall, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A celebration. One tap to dismiss, no score, nothing to beat.
Future<void> showPennyMoment(
  BuildContext context, {
  Penny pose = Penny.celebrate,
  required String headline,
  required String body,
  String action = 'Nice',
}) {
  return showDialog<void>(
    context: context,
    // Ink at 32%, never plain black.
    barrierColor: navy.withValues(alpha: 0.32),
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PennyImage(pose, size: 148, semanticLabel: 'Penny'),
            const SizedBox(height: 12),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineLarge
                  ?.copyWith(fontSize: 24, color: sproutOf(context)),
            ),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(action),
            ),
          ],
        ),
      ),
    ),
  );
}
