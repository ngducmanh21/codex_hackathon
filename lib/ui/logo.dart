import 'package:flutter/material.dart';

import 'theme.dart';

/// SCOAI Voice's logo: the hexagon mark and the one-line wordmark, "SCOAI"
/// extra-bold and " Voice" regular in navy, as in the SCOAI Voice app.
class ScoaiLogo extends StatelessWidget {
  const ScoaiLogo({super.key, this.height = 24});

  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'SCOAI Voice',
    image: true,
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScoaiMark(size: height),
          const SizedBox(width: 8),
          Text.rich(
            const TextSpan(
              children: [
                TextSpan(
                  text: 'SCOAI',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(text: ' Voice'),
              ],
            ),
            maxLines: 1,
            softWrap: false,
            textScaler: TextScaler.noScaling,
            style: TextStyle(fontSize: height * 17 / 24, height: 1.2, fontWeight: FontWeight.w400, color: C.brand),
          ),
        ],
      ),
    ),
  );
}

/// The hexagon alone, [size] dp high.
class ScoaiMark extends StatelessWidget {
  const ScoaiMark({super.key, this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(key: const Key('scoai-mark'), size: Size(size * 32 / 36, size), painter: const _MarkPainter());
}

/// Paths of the SCOAI mark (viewport 32×36): a rounded hexagon with four
/// linked nodes.
class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  static const fill = Color(0xFF0B476A);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 32, size.height / 36);
    final hexagon = Path()
      ..moveTo(14.6, 0.8)
      ..quadraticBezierTo(16, 0, 17.4, 0.8)
      ..lineTo(29.9, 8)
      ..quadraticBezierTo(31.3, 8.8, 31.3, 10.5)
      ..lineTo(31.3, 25.5)
      ..quadraticBezierTo(31.3, 27.2, 29.9, 28)
      ..lineTo(17.4, 35.2)
      ..quadraticBezierTo(16, 36, 14.6, 35.2)
      ..lineTo(2.1, 28)
      ..quadraticBezierTo(0.7, 27.2, 0.7, 25.5)
      ..lineTo(0.7, 10.5)
      ..quadraticBezierTo(0.7, 8.8, 2.1, 8)
      ..close();
    canvas.drawPath(hexagon, Paint()..color = fill);
    const top = Offset(18.3, 10.2);
    const left = Offset(7.9, 19.1);
    const bottom = Offset(20.9, 25.1);
    const right = Offset(24, 14.8);
    final links = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..lineTo(right.dx, right.dy);
    canvas.drawPath(
      links,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final nodes = Paint()..color = Colors.white;
    for (final p in const [top, left, bottom, right]) {
      canvas.drawCircle(p, 2.3, nodes);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) => false;
}
