import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tecogroup2/services/stars_service.dart';
import 'package:geolocator/geolocator.dart';

class ConstellationsPage extends StatefulWidget {
  const ConstellationsPage({super.key});

  @override
  State<ConstellationsPage> createState() => _ConstellationsPageState();
}

class _ConstellationsPageState extends State<ConstellationsPage> with SingleTickerProviderStateMixin {
  final StarsService _service = StarsService(baseUrl: 'http://10.0.0.55:8000');
  final List<List<VisibleStar>> _hourlyFrames = <List<VisibleStar>>[];
  final List<List<VisibleBody>> _hourlyBodyFrames = <List<VisibleBody>>[];
  List<List<String>> _constellationSegments = <List<String>>[]; // pares [nameA, nameB]
  String? _highlightStarName;
  bool _showConstellationLines = true;
  AnimationController? _controller;
  bool _loading = true;
  bool _playing = true;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
    _loadConstellationSegments();
  }

  void _initAndLoad() {
    // No bloquear el arranque esperando permisos; usar fallback inmediato
    _loadNightFrames();
    _ensureLocationPermission();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadConstellationSegments() async {
    try {
      final String jsonStr = await rootBundle.loadString('assets/constellations_lines.json');
      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        final List<dynamic>? consts = decoded['constellations'] as List<dynamic>?;
        if (consts != null) {
          final List<List<String>> segs = <List<String>>[];
          for (final dynamic c in consts) {
            if (c is Map<String, dynamic>) {
              final List<dynamic>? segments = c['segments'] as List<dynamic>?;
              if (segments != null) {
                for (final dynamic seg in segments) {
                  if (seg is List && seg.length == 2) {
                    final String? a = seg[0] is String ? seg[0] as String : null;
                    final String? b = seg[1] is String ? seg[1] as String : null;
                    if (a != null && b != null) {
                      segs.add(<String>[a, b]);
                    }
                  }
                }
              }
            }
          }
          if (mounted) {
            setState(() => _constellationSegments = segs);
          }
        }
      }
    } catch (_) {
      // Asset opcional: si falla, se ignora
    }
  }

  Future<void> _loadNightFrames() async {
    setState(() => _loading = true);
    try {
      final List<DateTime> times = _generateNightHoursUtc(DateTime.now().toUtc());

      // Resolver ubicación rápida con timeout corto; fallback RD
      final (double lat, double lon) = await _getLatLonFast();

      // Disparar peticiones en paralelo para reducir espera
      final List<Future<(List<VisibleStar>, List<VisibleBody>)>> tasks = times.map((DateTime t) async {
        try {
          final starsF = _service.fetchVisibleStars(latitude: lat, longitude: lon, when: t);
          final bodiesF = _service.fetchVisibleBodies(latitude: lat, longitude: lon, when: t);
          final results = await Future.wait([starsF, bodiesF]);
          return (results[0] as List<VisibleStar>, results[1] as List<VisibleBody>);
        } catch (_) {
          return (const <VisibleStar>[], const <VisibleBody>[]);
        }
      }).toList();

      final List<(List<VisibleStar>, List<VisibleBody>)> results = await Future.wait(tasks);
      final List<List<VisibleStar>> frames = results.map((r) => r.$1).toList();
      final List<List<VisibleBody>> bodyFrames = results.map((r) => r.$2).toList();

      if (!mounted) return;

      _hourlyFrames
        ..clear()
        ..addAll(frames);
      _hourlyBodyFrames
        ..clear()
        ..addAll(bodyFrames);

      _controller?.dispose();
      // Un ciclo completo (18:00 -> 06:00) durará 20 segundos por defecto
      _controller = AnimationController(vsync: this, duration: const Duration(seconds: 20))
        ..addListener(() => setState(() {}))
        ..repeat();

      _playing = true;
    } catch (_) {
      // Ignorar, UI seguirá sin bloquearse
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<(double, double)> _getLatLonFast() async {
    // Fallback: Santiago de los Caballeros, RD
    const double fallbackLat = 19.4517;
    const double fallbackLon = -70.6970;
    try {
      // Intentar último conocido primero (no bloquea)
      final Position? last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return (last.latitude, last.longitude);
      }
      // Intentar una lectura rápida con límite de tiempo
      final Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 3),
      );
      return (pos.latitude, pos.longitude);
    } catch (_) {
      return (fallbackLat, fallbackLon);
    }
  }

  Future<void> _ensureLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // No forzar UI aquí; el fallback cubrirá
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    // deniedForever será cubierto por fallback
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

  List<VisibleBody> _interpolatedBodies() {
    if (_hourlyBodyFrames.length < 2 || _controller == null) {
      return const <VisibleBody>[];
    }
    final int segments = _hourlyBodyFrames.length - 1;
    final double progress = _controller!.value * segments; // 0..segments
    final int i = progress.floor().clamp(0, segments - 1);
    final double t = progress - i;

    final List<VisibleBody> a = _hourlyBodyFrames[i];
    final List<VisibleBody> b = _hourlyBodyFrames[i + 1];

    final Map<String, VisibleBody> mapA = {for (final s in a) s.name: s};
    final Map<String, VisibleBody> mapB = {for (final s in b) s.name: s};

    final List<VisibleBody> result = <VisibleBody>[];
    for (final String name in mapA.keys) {
      final VisibleBody? sA = mapA[name];
      final VisibleBody? sB = mapB[name];
      if (sA == null || sB == null) continue;

      final double alt = sA.altitude + (sB.altitude - sA.altitude) * t;
      final double deltaAz = (((sB.azimuth - sA.azimuth) + 540) % 360) - 180;
      final double az = (sA.azimuth + deltaAz * t) % 360;

      if (alt <= 0) continue;

      result.add(VisibleBody(
        name: name,
        type: sA.type,
        magnitude: sA.magnitude,
        altitude: alt,
        azimuth: az < 0 ? az + 360 : az,
        phase: sA.phase,
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
    final List<VisibleBody> bodies = _hourlyBodyFrames.isEmpty ? const <VisibleBody>[] : _interpolatedBodies();

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
                  Row(
                    children: [
                      const Text('Líneas', style: TextStyle(color: Colors.white70)),
                      const SizedBox(width: 8),
                      Switch.adaptive(
                        value: _showConstellationLines,
                        onChanged: (bool v) => setState(() => _showConstellationLines = v),
                        activeColor: const Color(0xFF33FFE6),
                      ),
                    ],
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
                    : AltAzSky(
                        stars: stars,
                        bodies: bodies,
                        constellationSegments: _constellationSegments,
                        highlightedSegments: _highlightedSegmentsForStar(_highlightStarName),
                        showConstellationLines: _showConstellationLines,
                        animationValue: _controller?.value ?? 0.0,
                      ),
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

  List<List<String>> _highlightedSegmentsForStar(String? starName) {
    if (starName == null || _constellationSegments.isEmpty) return const <List<String>>[];
    return _constellationSegments.where((List<String> seg) {
      return seg.length == 2 && (seg[0] == starName || seg[1] == starName);
    }).toList(growable: false);
  }
}

/// Widget que dibuja el cielo en proyección alt-az (planetario simple)
/// - Altitud (0° horizonte, 90° cenit) se proyecta a radio
/// - Azimut (0° Norte, 90° Este) se proyecta a ángulo
class AltAzSky extends StatefulWidget {
  const AltAzSky({
    super.key,
    required this.stars,
    required this.bodies,
    required this.constellationSegments,
    required this.highlightedSegments,
    required this.animationValue,
    this.showConstellationLines = true,
    this.padding = 16,
  });

  final List<VisibleStar> stars;
  final List<VisibleBody> bodies;
  final List<List<String>> constellationSegments;
  final List<List<String>> highlightedSegments;
  final double padding;
  final bool showConstellationLines;
  // Valor de 0..1 que avanza en el tiempo para animaciones sutiles (twinkle)
  final double animationValue;

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
            final Size viewport = Size(side, side);
            final VisibleBody? tappedBody = _findTappedBodyAt(local, viewport);
            if (tappedBody != null) {
              _showBodySheet(context, tappedBody);
              return;
            }
            final VisibleStar? tappedStar = _findTappedStarAt(local, viewport);
            final state = context.findAncestorStateOfType<_ConstellationsPageState>();
            if (tappedStar != null) {
              _showStarSheet(context, tappedStar);
              state?.setState(() => state._highlightStarName = tappedStar.name);
            } else {
              state?.setState(() => state._highlightStarName = null);
            }
          },
          child: SizedBox(
            width: side,
            height: side,
            child: CustomPaint(
              painter: _AltAzPainter(
                stars: widget.stars,
                bodies: widget.bodies,
                segments: widget.constellationSegments,
                highlightedSegments: widget.highlightedSegments,
                padding: widget.padding,
                showConstellationLines: widget.showConstellationLines,
                animationValue: widget.animationValue,
              ),
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

  VisibleBody? _findTappedBodyAt(Offset point, Size size) {
    final Offset center = size.center(Offset.zero);
    final double maxRadius = math.min(size.width, size.height) / 2 - widget.padding;

    VisibleBody? candidate;
    double closestDistance = double.infinity;

    for (final VisibleBody body in widget.bodies) {
      if (body.altitude <= 0) continue;
      final double alt = body.altitude.clamp(0, 90).toDouble();
      final double az = body.azimuth % 360;

      final double r = (1 - (alt / 90.0)) * maxRadius;
      final double theta = _degToRad(az - 90);
      final Offset pos = Offset(
        center.dx + r * math.cos(theta),
        center.dy + r * math.sin(theta),
      );

      final double dist = (point - pos).distance;
      final double hitRadius = _hitRadiusForBody(body);
      if (dist <= hitRadius && dist < closestDistance) {
        closestDistance = dist;
        candidate = body;
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

  double _hitRadiusForBody(VisibleBody body) {
    final bool isMoon = body.type.toLowerCase() == 'moon';
    final double base = isMoon ? 24.0 : 18.0;
    final double magAdj = (1.0 - (body.magnitude * 0.04)).clamp(0.8, 1.4);
    return base * magAdj;
  }

  void _showStarSheet(BuildContext context, VisibleStar star) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        final double bottomSafe = MediaQuery.of(context).padding.bottom;
        const double navOverlayHeight = 30; // CurvedNavigationBar height
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + navOverlayHeight + bottomSafe),
          child: SingleChildScrollView(
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
          ),
        );
      },
    );
  }

  void _showBodySheet(BuildContext context, VisibleBody body) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        final double bottomSafe = MediaQuery.of(context).padding.bottom;
        const double navOverlayHeight = 30; // CurvedNavigationBar height
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + navOverlayHeight + bottomSafe),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.public, color: Colors.white70),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        body.name,
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
                _infoLine('Tipo', body.type),
                _infoLine('Magnitud', body.magnitude.toStringAsFixed(2)),
                _infoLine('Altitud', '${body.altitude.toStringAsFixed(1)}°'),
                _infoLine('Azimut', '${body.azimuth.toStringAsFixed(1)}°'),
                if (body.phase != null)
                  _infoLine('Fase', (body.phase! * 100).toStringAsFixed(0) + '%'),
                if (body.distance != null)
                  _infoLine('Distancia', _formatDistance(body.distance!)),
                const SizedBox(height: 12),
              ],
            ),
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
    // Usar fallback de RD: Santiago de los Caballeros
    _future = widget.service.fetchAstronomyEvents(
      latitude: 19.4517,
      longitude: -70.6970,
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
  _AltAzPainter({
    required this.stars,
    required this.bodies,
    required this.segments,
    required this.highlightedSegments,
    required this.padding,
    required this.showConstellationLines,
    required this.animationValue,
  });

  final List<VisibleStar> stars;
  final List<VisibleBody> bodies;
  final List<List<String>> segments; // pares [A,B]
  final List<List<String>> highlightedSegments;
  final double padding;
  final bool showConstellationLines;
  final double animationValue; // 0..1, derivado del AnimationController superior

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

    // Mapa rápido de posiciones proyectadas por nombre (normalizado) de estrella visible
    final Map<String, Offset> nameToPos = <String, Offset>{};

    // Estrellas
    final Paint starPaint = Paint()
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.plus; // suma aditiva para halo sutil

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

      // Twinkle: factores de tamaño/opacidad por estrella con fase distinta
      final (double sizeMul, double opacityMul) = _twinkleFactors(star.name, star.magnitude);

      final double baseRadius = _radiusForMagnitude(star.magnitude);
      final double radius = (baseRadius * sizeMul).clamp(0.8, 6.0);

      // Brillo base por magnitud con variación (twinkle)
      double opacity = _opacityForMagnitude(star.magnitude) * opacityMul;
      opacity = opacity.clamp(0.45, 1.0);

      // Núcleo
      starPaint.color = Colors.white.withOpacity(opacity);
      canvas.drawCircle(Offset(x, y), radius, starPaint);

      // Halo externo suave (dos capas)
      final double halo1Radius = radius * 1.8;
      final double halo2Radius = radius * 2.8;
      final double haloOpacity = (opacity * 0.35).clamp(0.15, 0.5);
      starPaint.color = Colors.white.withOpacity(haloOpacity);
      canvas.drawCircle(Offset(x, y), halo1Radius, starPaint);
      canvas.drawCircle(Offset(x, y), halo2Radius, starPaint);

      // Etiqueta para estrellas muy brillantes
      if (star.magnitude <= 1.0) {
        _drawLabel(canvas, Offset(x, y), star.name);
      }

      nameToPos[_normalizeName(star.name)] = Offset(x, y);
    }

    // Líneas de constelaciones: trazar solo si ambos extremos están visibles
    if (showConstellationLines && segments.isNotEmpty) {
      final Paint line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0x99FFFFFF);
      for (final List<String> seg in segments) {
        if (seg.length != 2) continue;
        final Offset? a = nameToPos[canonicalStarName(seg[0])];
        final Offset? b = nameToPos[canonicalStarName(seg[1])];
        if (a == null || b == null) continue;
        canvas.drawLine(a, b, line);
      }
    }

    // Segmentos resaltados (por toque): más gruesos y brillantes por encima
    if (showConstellationLines && highlightedSegments.isNotEmpty) {
      final Paint lineHi = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..color = const Color(0xCC33FFE6)
        ..blendMode = BlendMode.plus;
      for (final List<String> seg in highlightedSegments) {
        if (seg.length != 2) continue;
        final Offset? a = nameToPos[canonicalStarName(seg[0])];
        final Offset? b = nameToPos[canonicalStarName(seg[1])];
        if (a == null || b == null) continue;
        canvas.drawLine(a, b, lineHi);
      }
    }

    // Si no hay líneas, no mostramos highlights tampoco

    // Cuerpos (planetas y Luna): estilo diferenciado
    final Paint bodyPaint = Paint()
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.plus;

    for (final VisibleBody body in bodies) {
      if (body.altitude <= 0) continue;
      final double alt = body.altitude.clamp(0, 90).toDouble();
      final double az = body.azimuth % 360;

      final double r = (1 - (alt / 90.0)) * maxRadius;
      final double theta = _degToRad(az - 90);
      final double x = center.dx + r * math.cos(theta);
      final double y = center.dy + r * math.sin(theta);

      final bool isMoon = body.type.toLowerCase() == 'moon';
      final bool isPlanet = body.type.toLowerCase() == 'planet';

      final double baseSize = isMoon ? 8.0 : 5.5; // luna más grande
      final double magAdj = (1.0 - (body.magnitude * 0.04)).clamp(0.7, 1.3);
      final double radius = baseSize * magAdj;

      final Color color = isMoon
          ? const Color(0xFFFFF3C4)
          : isPlanet
              ? const Color(0xFF99E0FF)
              : Colors.white;

      // Núcleo
      bodyPaint.color = color.withOpacity(0.95);
      canvas.drawCircle(Offset(x, y), radius, bodyPaint);
      // Halo
      bodyPaint.color = color.withOpacity(0.35);
      canvas.drawCircle(Offset(x, y), radius * 2.2, bodyPaint);

      // Fase lunar simple (si disponible): dibujar un disco recortado
      if (isMoon && body.phase != null) {
        _drawMoonPhase(canvas, Offset(x, y), radius, body.phase!.clamp(0.0, 1.0));
      }

      // Etiqueta
      _drawLabel(canvas, Offset(x, y), body.name);
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

  (double, double) _twinkleFactors(String name, double magnitude) {
    // Fase por estrella a partir del nombre (estable entre renders)
    final int h = name.hashCode;
    final double phase = (h & 0xFFFF) / 0xFFFF * 2 * math.pi;
    // Velocidad global: multiplicamos animationValue (0..1) para que parpadee ~2 Hz
    final double t = animationValue * 12.0 * 2 * math.pi; // ~6 ciclos por vuelta
    // Amplitud menor para estrellas débiles (menos notorio)
    final double magnitudeFactor = (1.5 - magnitude).clamp(0.4, 1.2);
    final double s = math.sin(t + phase);
    final double sizeMul = 1.0 + 0.06 * s * magnitudeFactor; // +/- 6%
    final double opacityMul = 1.0 + 0.10 * s * magnitudeFactor; // +/- 10%
    return (sizeMul, opacityMul);
  }

  void _drawLabel(Canvas canvas, Offset pos, String text) {
    final TextPainter painter = TextPainter(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );
    // Sombra ligera
    painter.text = TextSpan(
      text: text,
      style: const TextStyle(
        fontSize: 11,
        color: Colors.black54,
        fontWeight: FontWeight.w500,
      ),
    );
    painter.layout();
    final Offset shadowPos = pos + const Offset(8, -10) + const Offset(1, 1);
    painter.paint(canvas, shadowPos);

    // Texto principal
    painter.text = const TextSpan(
      text: '',
    );
    painter.text = TextSpan(
      text: text,
      style: const TextStyle(
        fontSize: 11,
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
    );
    painter.layout();
    final Offset textPos = pos + const Offset(8, -10);
    painter.paint(canvas, textPos);
  }

  String _normalizeName(String name) => name.trim().toLowerCase();

  // Nombre canónico: minúsculas, sin acentos, símbolos griegos transliterados
  String canonicalStarName(String raw) {
    String s = raw.trim().toLowerCase();
    // Quitar acentos básicos
    const Map<String, String> accentMap = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
      'ñ': 'n'
    };
    accentMap.forEach((k, v) => s = s.replaceAll(k, v));
    // Letras griegas comunes
    const Map<String, String> greek = {
      'α': 'alpha', 'β': 'beta', 'γ': 'gamma', 'δ': 'delta', 'ε': 'epsilon',
      'ζ': 'zeta', 'η': 'eta', 'θ': 'theta', 'ι': 'iota', 'κ': 'kappa',
      'λ': 'lambda', 'μ': 'mu', 'ν': 'nu', 'ξ': 'xi', 'ο': 'omicron', 'π': 'pi',
      'ρ': 'rho', 'σ': 'sigma', 'τ': 'tau', 'υ': 'upsilon', 'φ': 'phi', 'χ': 'chi',
      'ψ': 'psi', 'ω': 'omega'
    };
    greek.forEach((k, v) => s = s.replaceAll(k, v));
    // Eliminar puntuación y dobles espacios
    s = s.replaceAll(RegExp(r"[^a-z0-9\s]"), ' ');
    s = s.replaceAll(RegExp(r"\s+"), ' ').trim();
    return s;
  }

  void _drawMoonPhase(Canvas canvas, Offset center, double radius, double phase) {
    // fase 0 = nueva, 0.5 = llena. Render aproximado con máscara elíptica
    final Paint lightPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFFF3C4).withOpacity(0.95)
      ..blendMode = BlendMode.plus;

    // Disco base ya dibujado; aplicar sombra para fase
    final Path clip = Path()..addOval(Rect.fromCircle(center: center, radius: radius));

    // Simular terminador como elipse desplazada
    final double k = (phase - 0.5).abs() * 2.0; // 0..1 ancho de sombra
    final double shadowW = radius * (0.4 + 0.6 * k);
    final Rect shadowRect = Rect.fromCenter(center: center, width: shadowW * 2, height: radius * 2);

    canvas.save();
    canvas.clipPath(clip);
    // Sombra (lado oscuro)
    final Paint shadow = Paint()..color = Colors.black.withOpacity(0.6);
    canvas.drawOval(shadowRect, shadow);
    // Luz residual para no perder volumen
    canvas.drawCircle(center, radius * 0.6, lightPaint..color = lightPaint.color.withOpacity(0.25));
    canvas.restore();
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
    return oldDelegate.stars != stars ||
        oldDelegate.bodies != bodies ||
        oldDelegate.padding != padding ||
        oldDelegate.animationValue != animationValue;
  }
}

