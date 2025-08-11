import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:tecogroup2/services/stars_service.dart';

class ConstellationsPage extends StatelessWidget {
  const ConstellationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Ejemplo mínimo de datos (reemplaza por la lista real desde tu servicio)
    final List<VisibleStar> sampleStars = <VisibleStar>[
      VisibleStar(name: 'Sirius', magnitude: -1.46, altitude: 45, azimuth: 110),
      VisibleStar(name: 'Canopus', magnitude: -0.74, altitude: 30, azimuth: 170),
      VisibleStar(name: 'Arcturus', magnitude: -0.05, altitude: 60, azimuth: 60),
      VisibleStar(name: 'Vega', magnitude: 0.03, altitude: 70, azimuth: 320),
      VisibleStar(name: 'Capella', magnitude: 0.08, altitude: 20, azimuth: 20),
      VisibleStar(name: 'Rigel', magnitude: 0.13, altitude: 10, azimuth: 240),
      VisibleStar(name: 'Procyon', magnitude: 0.40, altitude: 55, azimuth: 95),
      VisibleStar(name: 'Betelgeuse', magnitude: 0.42, altitude: 25, azimuth: 230),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(12.0),
              child: Text(
                'Constelaciones',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: Center(
                child: AltAzSky(stars: sampleStars),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget que dibuja el cielo en proyección alt-az (planetario simple)
/// - Altitud (0° horizonte, 90° cenit) se proyecta a radio
/// - Azimut (0° Norte, 90° Este) se proyecta a ángulo
class AltAzSky extends StatelessWidget {
  const AltAzSky({super.key, required this.stars, this.padding = 16});

  final List<VisibleStar> stars;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double size = math.min(constraints.maxWidth, constraints.maxHeight);
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _AltAzPainter(stars: stars, padding: padding),
          ),
        );
      },
    );
  }
}

class _AltAzPainter extends CustomPainter {
  _AltAzPainter({required this.stars, required this.padding});

  final List<VisibleStar> stars;
  final double padding;

  final Paint _circlePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..color = const Color(0x44FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double maxRadius = math.min(size.width, size.height) / 2 - padding;

    // Círculo del horizonte
    canvas.drawCircle(center, maxRadius, _circlePaint);

    // Marcas cardinales (opcionales y sutiles)
    _drawCardinalMarks(canvas, center, maxRadius);

    // Estrellas
    final Paint starPaint = Paint()..style = PaintingStyle.fill;

    for (final VisibleStar star in stars) {
      final double alt = star.altitude.clamp(0, 90).toDouble();
      final double az = star.azimuth % 360;

      // Proyección: r = (1 - alt/90) * maxRadius (horizonte en el borde, cenit al centro)
      final double r = (1 - (alt / 90.0)) * maxRadius;

      // Ángulo: 0° = Norte (arriba), 90° = Este (derecha) -> theta = az - 90°
      final double theta = _degToRad(az - 90);

      final double x = center.dx + r * math.cos(theta);
      final double y = center.dy + r * math.sin(theta);

      final double radius = _radiusForMagnitude(star.magnitude);

      // Brillo leve por magnitud
      final double opacity = _opacityForMagnitude(star.magnitude);
      starPaint.color = Colors.white.withOpacity(opacity);

      canvas.drawCircle(Offset(x, y), radius, starPaint);
    }
  }

  double _degToRad(double degrees) => degrees * math.pi / 180.0;

  double _radiusForMagnitude(double magnitude) {
    // Escala: m=-1.5 -> 4.5px, m=0 -> 3.8px, m=2 -> 2.8px, m=4 -> 1.9px, m=6 -> 1.4px, m>6 -> 1.0px
    final double base = 4.5 - (magnitude + 1.5) * 0.7; // lineal con recorte
    return base.clamp(1.0, 4.5);
  }

  double _opacityForMagnitude(double magnitude) {
    // Más brillante para magnitudes negativas. Rango aproximado 0.5 .. 1.0
    final double base = 1.0 - (magnitude * 0.07);
    return base.clamp(0.5, 1.0);
  }

  void _drawCardinalMarks(Canvas canvas, Offset center, double r) {
    final TextPainter painter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    final List<(String, double, double)> labels = <(String, double, double)>[
      ('N', 0, -r), // arriba
      ('E', r, 0), // derecha
      ('S', 0, r), // abajo
      ('W', -r, 0), // izquierda
    ];

    for (final (String label, double dx, double dy) in labels) {
      painter.text = TextSpan(
        text: label,
        style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 12),
      );
      painter.layout();
      final Offset pos = center + Offset(dx, dy) - Offset(painter.width / 2, painter.height / 2);
      painter.paint(canvas, pos);
    }
  }

  @override
  bool shouldRepaint(covariant _AltAzPainter oldDelegate) {
    // Redibuja si cambia la lista de estrellas o el padding
    return oldDelegate.stars != stars || oldDelegate.padding != padding;
  }
}

