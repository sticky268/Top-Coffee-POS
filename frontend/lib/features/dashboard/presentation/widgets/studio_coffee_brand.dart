import 'package:flutter/material.dart';

/// Scalable line artwork from the approved dashboard brand treatment.
class StudioCoffeeBrand extends StatelessWidget {
  const StudioCoffeeBrand({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Top Coffee',
        image: true,
        child: ExcludeSemantics(
            child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          child: Column(children: [
            const SizedBox(
                width: 70,
                height: 60,
                child: CustomPaint(painter: _CoffeeMark())),
            const SizedBox(height: 10),
            Text('TOP COFFEE',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFF0CA80),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.4)),
          ]),
        )),
      );
}

class _CoffeeMark extends CustomPainter {
  const _CoffeeMark();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 70, size.height / 60);
    final pen = Paint()
      ..color = const Color(0xFFF0CA80)
      ..strokeWidth = 2.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawOval(const Rect.fromLTWH(10, 25, 43, 9), pen);
    canvas.drawPath(
        Path()
          ..moveTo(11, 30)
          ..cubicTo(13, 59, 48, 59, 52, 30),
        pen);
    canvas.drawPath(
        Path()
          ..moveTo(53, 29)
          ..cubicTo(75, 24, 68, 48, 49, 43),
        pen);
    canvas.drawPath(
        Path()
          ..moveTo(30, 22)
          ..cubicTo(20, 15, 41, 12, 32, 4),
        pen);
    canvas.drawPath(
        Path()
          ..moveTo(39, 21)
          ..quadraticBezierTo(48, 15, 43, 12),
        pen);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CoffeeMark oldDelegate) => false;
}
