import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:tecogroup2/services/stars_service.dart';

class ConstellationsPage extends StatefulWidget {
  const ConstellationsPage({super.key});

  @override
  State<ConstellationsPage> createState() => _ConstellationsPageState();
}

class _ConstellationsPageState extends State<ConstellationsPage> with SingleTickerProviderStateMixin {
  final StarsService _service = StarsService(baseUrl: 'http://10.0.0.55:8000');
  final List<List<VisibleStar>> _hourlyFrames = <List<VisibleStar>>[];
  AnimationController? _controller;
  bool _loading = true;
  bool _playing = true;

  @override
  void initState() {
    super.initState();
    _loadNightFrames();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadNightFrames() async {
    setState(() => _loading = true);

    final List<DateTime> times = _generateNightHoursUtc(DateTime.now().toUtc());

    final List<List<VisibleStar>> frames = <List<VisibleStar>>[];
    for (final DateTime t in times) {
      try {
        // TODO: reemplaza lat/lon por los reales del usuario
        final stars = await _service.fetchVisibleStars(
          latitude: -12.0464,
          longitude: -77.0428,
          when: t,
        );
        frames.add(stars);
      } catch (_) {
        frames.add(const <VisibleStar>[]);
      }
    }

    if (!mounted) return;

    _hourlyFrames
      ..clear()
      ..addAll(frames);

    _controller?.dispose();
    // Un ciclo completo (18:00 -> 06:00) durará 20 segundos por defecto
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 20))
      ..addListener(() => setState(() {}))
      ..repeat();

    _playing = true;
    setState(() => _loading = false);
  }

  List<DateTime> _generateNightHoursUtc(DateTime nowUtc) {
    // Noche: 18:00 del día base a 06:00 del día siguiente (incluye 18..23 y 00..06)
    final DateTime base = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    final DateTime start = base.add(const Duration(hours: 18)); // 18:00 UTC del día actual
    final DateTime end = base.add(const Duration(days: 1, hours: 6)); // 06:00 UTC del día siguiente

    final List<DateTime> hours = <DateTime>[];
    DateTime cursor = start;
    while (!cursor.isAfter(end)) {
      hours.add(cursor);
      cursor = cursor.add(const Duration(hours: 1));
    }
    return hours;
  }

  List<VisibleStar> _interpolatedStars() {
    if (_hourlyFrames.length < 2 || _controller == null) {
      return const <VisibleStar>[];
    }

    final int segments = _hourlyFrames.length - 1;
    final double progress = _controller!.value * segments; // 0..segments
    final int i = progress.floor().clamp(0, segments - 1);
    final double t = progress - i;

    final List<VisibleStar> a = _hourlyFrames[i];
    final List<VisibleStar> b = _hourlyFrames[i + 1];

    final Map<String, VisibleStar> mapA = {for (final s in a) s.name: s};
    final Map<String, VisibleStar> mapB = {for (final s in b) s.name: s};

    final List<VisibleStar> result = <VisibleStar>[];
    for (final String name in mapA.keys) {
      final VisibleStar? sA = mapA[name];
      final VisibleStar? sB = mapB[name];
      if (sA == null || sB == null) continue;

      final double alt = sA.altitude + (sB.altitude - sA.altitude) * t;
      // Interpolación circular de azimut por el camino más corto
      final double deltaAz = (((sB.azimuth - sA.azimuth) + 540) % 360) - 180;
      final double az = (sA.azimuth + deltaAz * t) % 360;

      if (alt <= 0) continue; // visible sobre el horizonte

      result.add(VisibleStar(
        name: name,
        magnitude: sA.magnitude,
        altitude: alt,
        azimuth: az < 0 ? az + 360 : az,
        distance: sA.distance,
      ));
    }

    return result;
  }

  void _togglePlay() {
    if (_controller == null) return;
    if (_playing) {
      _controller!.stop();
    } else {
      _controller!.repeat();
    }
    setState(() => _playing = !_playing);
  }

  @override
  Widget build(BuildContext context) {
    final List<VisibleStar> stars = _hourlyFrames.isEmpty ? const <VisibleStar>[] : _interpolatedStars();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Constelaciones',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: _togglePlay,
                    icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        color: Colors.white),
                  ),
                  IconButton(
                    onPressed: _loadNightFrames,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : AltAzSky(stars: stars),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: AstronomyEventsSection(service: _service),
            ),
            // sección educativa movida a SearchPage
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
      if (star.altitude <= 0) continue; // ignorar bajo horizonte
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

// Sección educativa movida a SearchPage

class AstronomyEventsSection extends StatefulWidget {
  const AstronomyEventsSection({super.key, required this.service});

  final StarsService service;

  @override
  State<AstronomyEventsSection> createState() => _AstronomyEventsSectionState();
}

class _AstronomyEventsSectionState extends State<AstronomyEventsSection> {
  late Future<List<AstronomyEvent>> _future;

  @override
  void initState() {
    super.initState();
    final DateTime nowUtc = DateTime.now().toUtc();
    _future = widget.service.fetchAstronomyEvents(
      latitude: -12.0464, // TODO: reemplazar por coordenadas reales
      longitude: -77.0428,
      startUtc: DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day, 0, 0, 0),
      endUtc: DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day, 23, 59, 59),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AstronomyEvent>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Error al cargar eventos', style: const TextStyle(color: Colors.white70)),
          );
        }
        final List<AstronomyEvent> events = snapshot.data ?? const <AstronomyEvent>[];
        if (events.isEmpty) {
          return const Center(
            child: Text('Sin eventos para hoy', style: TextStyle(color: Colors.white70)),
          );
        }
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: events.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final e = events[index];
            final (IconData icon, Color color) = _iconAndColorForType(e.type);
            return Container(
              width: 280,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x22FFFFFF)),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _titleForType(e.type),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatUtc(e.time),
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Text(e.description, style: const TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  (IconData, Color) _iconAndColorForType(String type) {
    switch (type) {
      case 'planet_rise':
        return (Icons.arrow_upward, const Color(0xFF81D4FA));
      case 'planet_set':
        return (Icons.arrow_downward, const Color(0xFF4FC3F7));
      case 'moon_phase':
        return (Icons.brightness_2, const Color(0xFFFFF59D));
      case 'solar_eclipse':
        return (Icons.brightness_3, const Color(0xFFFF7043));
      case 'lunar_eclipse':
        return (Icons.brightness_1, const Color(0xFFBA68C8));
      default:
        return (Icons.stars, const Color(0xFF90CAF9));
    }
  }

  String _titleForType(String type) {
    switch (type) {
      case 'planet_rise':
        return 'Salida de planeta';
      case 'planet_set':
        return 'Puesta de planeta';
      case 'moon_phase':
        return 'Fase lunar';
      case 'solar_eclipse':
        return 'Eclipse solar';
      case 'lunar_eclipse':
        return 'Eclipse lunar';
      default:
        return 'Evento astronómico';
    }
  }

  String _formatUtc(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'UTC ${two(t.hour)}:${two(t.minute)} · ${two(t.day)}/${two(t.month)}/${t.year}';
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
      if (star.altitude <= 0) continue; // solo por encima del horizonte
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

