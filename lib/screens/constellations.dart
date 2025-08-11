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
class AltAzSky extends StatefulWidget {
  const AltAzSky({super.key, required this.stars, this.padding = 16});

  final List<VisibleStar> stars;
  final double padding;

  @override
  State<AltAzSky> createState() => _AltAzSkyState();
}

class _AltAzSkyState extends State<AltAzSky> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double side = math.min(constraints.maxWidth, constraints.maxHeight);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (TapDownDetails details) {
            final Offset local = details.localPosition;
            final VisibleStar? tapped = _findTappedStarAt(local, Size(side, side));
            if (tapped != null) {
              _showStarSheet(context, tapped);
            }
          },
          child: SizedBox(
            width: side,
            height: side,
            child: CustomPaint(
              painter: _AltAzPainter(stars: widget.stars, padding: widget.padding),
            ),
          ),
        );
      },
    );
  }

  VisibleStar? _findTappedStarAt(Offset point, Size size) {
    final Offset center = size.center(Offset.zero);
    final double maxRadius = math.min(size.width, size.height) / 2 - widget.padding;

    VisibleStar? candidate;
    double closestDistance = double.infinity;

    for (final VisibleStar star in widget.stars) {
      final double alt = star.altitude.clamp(0, 90).toDouble();
      final double az = star.azimuth % 360;

      final double r = (1 - (alt / 90.0)) * maxRadius;
      final double theta = _degToRad(az - 90);
      final Offset pos = Offset(
        center.dx + r * math.cos(theta),
        center.dy + r * math.sin(theta),
      );

      final double dist = (point - pos).distance;
      final double hitRadius = _hitRadiusForMagnitude(star.magnitude);
      if (dist <= hitRadius && dist < closestDistance) {
        closestDistance = dist;
        candidate = star;
      }
    }
    return candidate;
  }

  double _degToRad(double degrees) => degrees * math.pi / 180.0;

  double _hitRadiusForMagnitude(double magnitude) {
    // Facilitar el toque: base en tamaño visual con margen
    final double baseVisual = 4.5 - (magnitude + 1.5) * 0.7; // igual que en el painter
    final double visual = baseVisual.clamp(1.0, 4.5);
    return (visual * 3).clamp(10.0, 18.0); // área táctil mínima 10px
  }

  void _showStarSheet(BuildContext context, VisibleStar star) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.white70),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      star.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _infoLine('Magnitud', star.magnitude.toStringAsFixed(2)),
              _infoLine('Altitud', '${star.altitude.toStringAsFixed(1)}°'),
              _infoLine('Azimut', '${star.azimuth.toStringAsFixed(1)}°'),
              if (star.distance != null)
                _infoLine('Distancia', _formatDistance(star.distance!)),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _infoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(color: Colors.white70)),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatDistance(double value) {
    // Si viene en años luz o parsear en función de tu backend
    // Aquí se asume unidades genéricas
    return value >= 1000
        ? '${(value / 1000).toStringAsFixed(2)} k'
        : value.toStringAsFixed(2);
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

