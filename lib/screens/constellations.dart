import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tecogroup2/services/stars_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:camera/camera.dart';
// import 'package:flutter_compass/flutter_compass.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

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
  double _lightPollution = 0.3; // 0=oscuro, 1=muy iluminado
  bool _arMode = false;
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
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                      'Constelaciones',
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Líneas', style: TextStyle(color: Colors.white70)),
                      const SizedBox(width: 6),
                      Switch.adaptive(
                        value: _showConstellationLines,
                        onChanged: (bool v) => setState(() => _showConstellationLines = v),
                        activeColor: const Color(0xFF33FFE6),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.nights_stay, color: Colors.white70, size: 18),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 120,
                        child: Slider(
                          value: _lightPollution,
                          onChanged: (v) => setState(() => _lightPollution = v),
                          min: 0,
                          max: 1,
                          divisions: 10,
                          label: _lightPollution.toStringAsFixed(1),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Modo Cámara',
                    onPressed: () => setState(() => _arMode = !_arMode),
                    icon: Icon(_arMode ? Icons.camera_alt : Icons.camera_alt_outlined, color: Colors.white),
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
                    : _arMode
                        ? CameraSkyOverlay(
                            stars: stars,
                            bodies: bodies,
                            animationValue: _controller?.value ?? 0.0,
                          )
                        : AltAzSky(
                            stars: stars,
                            bodies: bodies,
                            constellationSegments: _constellationSegments,
                            highlightedSegments: _highlightedSegmentsForStar(_highlightStarName),
                            showConstellationLines: _showConstellationLines,
                            lightPollution: _lightPollution,
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
    this.lightPollution = 0.3,
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
  final double lightPollution; // 0..1

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
                lightPollution: widget.lightPollution,
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
    required this.lightPollution,
  });

  final List<VisibleStar> stars;
  final List<VisibleBody> bodies;
  final List<List<String>> segments; // pares [A,B]
  final List<List<String>> highlightedSegments;
  final double padding;
  final bool showConstellationLines;
  final double animationValue; // 0..1, derivado del AnimationController superior
  final double lightPollution; // 0..1

  final Paint _circlePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..color = const Color(0x44FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double maxRadius = math.min(size.width, size.height) / 2 - padding;

    // Fondo con gradiente radial (cielo nocturno sutil)
    final Rect skyRect = Rect.fromCircle(center: center, radius: maxRadius + padding);
    final Paint skyPaint = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0xFF090B1A), // cenit ligeramente más claro
          Color(0xFF050713),
          Color(0xFF000000), // horizonte más oscuro
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(skyRect);
    canvas.drawCircle(center, maxRadius + padding, skyPaint);
    // Vía Láctea procedural
    _drawMilkyWayBand(canvas, center, maxRadius + padding);
    // Velado por contaminación lumínica
    if (lightPollution > 0) {
      final double veil = (lightPollution * 0.55).clamp(0.0, 0.6);
      final Paint veilPaint = Paint()..color = Color.fromRGBO(0, 0, 0, veil);
      canvas.drawCircle(center, maxRadius + padding, veilPaint);
    }

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
      // Ajuste leve por refracción cerca del horizonte (solo visual)
      final double altAdj = alt < 10 ? alt + (10 - alt) * 0.03 : alt;
      final double az = star.azimuth % 360;

      // Proyección: r = (1 - alt/90) * maxRadius (horizonte en el borde, cenit al centro)
      final double r = (1 - (altAdj / 90.0)) * maxRadius;

      // Ángulo: 0° = Norte (arriba), 90° = Este (derecha) -> theta = az - 90°
      final double theta = _degToRad(az - 90);

      final double x = center.dx + r * math.cos(theta);
      final double y = center.dy + r * math.sin(theta);

      // Twinkle: factores de tamaño/opacidad por estrella con fase distinta
      final (double sizeMul, double opacityMul) = _twinkleFactors(star.name, star.magnitude);

      final double baseRadius = _radiusForMagnitude(star.magnitude);
      final double radius = (baseRadius * sizeMul).clamp(0.8, 6.0);

      // Brillo base por magnitud con variación (twinkle)
      // atenuación atmosférica hacia el horizonte
      final double extinction = _extinctionForAltitude(altAdj) * (1.0 - lightPollution * 0.35);
      double opacity = _opacityForMagnitude(star.magnitude) * opacityMul * extinction;
      opacity = opacity.clamp(0.45, 1.0);

      // Color: por temperatura o por altitud si no hay datos
      final Color baseColor = _colorForStar(star, altAdj);
      // Núcleo
      starPaint.color = baseColor.withOpacity(opacity);
      canvas.drawCircle(Offset(x, y), radius, starPaint);

      // Halo externo suave (dos capas)
      final double halo1Radius = radius * 1.8;
      final double halo2Radius = radius * 2.8;
      final double haloOpacity = (opacity * 0.35).clamp(0.15, 0.5);
      starPaint.color = baseColor.withOpacity(haloOpacity);
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

      final double baseSize = isMoon ? 9.0 : 6.0; // luna y planetas un poco mayores
      final double magAdj = (1.0 - (body.magnitude * 0.04)).clamp(0.7, 1.4);
      final double radius = baseSize * magAdj;

      if (isMoon) {
        _drawMoonShaded(canvas, Offset(x, y), radius, body.phase?.clamp(0.0, 1.0) ?? 0.5);
      } else if (isPlanet) {
        final Color color = _planetColor(body.name);
        final bool isSaturn = body.name.toLowerCase().contains('saturn');
        _drawPlanet(canvas, Offset(x, y), radius, color, withRings: isSaturn);
      } else {
        // Otros cuerpos: disco simple con halo
        final Color color = const Color(0xFFB0D8FF);
        bodyPaint.color = color.withOpacity(0.95);
        canvas.drawCircle(Offset(x, y), radius, bodyPaint);
        bodyPaint.color = color.withOpacity(0.35);
        canvas.drawCircle(Offset(x, y), radius * 2.2, bodyPaint);
      }

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

  // Atenuación atmosférica simple (1.0 en cenit, 0.75 hacia horizonte)
  double _extinctionForAltitude(double alt) {
    final double t = (alt / 90.0).clamp(0.0, 1.0);
    return 0.75 + 0.25 * t; // 0.75 en 0°, 1.0 en 90°
  }

  // Color base según altitud (más cálido en el horizonte)
  Color _colorForAltitude(double alt) {
    final double t = (alt / 90.0).clamp(0.0, 1.0);
    final Color warm = const Color(0xFFFFE0B2); // cálido
    final Color cold = Colors.white; // cenit blanco
    int lerp(int a, int b) => a + ((b - a) * t).round();
    return Color.fromARGB(
      255,
      lerp(warm.red, cold.red),
      lerp(warm.green, cold.green),
      lerp(warm.blue, cold.blue),
    );
  }

  // Color según datos de la estrella (preferir temp/BV/rgbHex)
  Color _colorForStar(VisibleStar s, double alt) {
    if (s.rgbHex != null && s.rgbHex!.startsWith('#') && s.rgbHex!.length == 7) {
      final int r = int.parse(s.rgbHex!.substring(1, 3), radix: 16);
      final int g = int.parse(s.rgbHex!.substring(3, 5), radix: 16);
      final int b = int.parse(s.rgbHex!.substring(5, 7), radix: 16);
      return Color.fromARGB(255, r, g, b);
    }
    if (s.bv != null) {
      return _colorFromBV(s.bv!.clamp(-0.4, 2.0));
    }
    if (s.colorTempK != null) {
      return _colorFromTempK(s.colorTempK!.clamp(2000, 12000));
    }
    return _colorForAltitude(alt);
  }

  Color _colorFromBV(double bv) {
    // Aproximación simple: azul (-0.3) a rojo (1.7)
    final double t = ((bv + 0.3) / 2.0).clamp(0.0, 1.0);
    final Color cold = const Color(0xFFBBD9FF);
    final Color warm = const Color(0xFFFFC58A);
    int lerp(int a, int b) => a + ((b - a) * t).round();
    return Color.fromARGB(255, lerp(cold.red, warm.red), lerp(cold.green, warm.green), lerp(cold.blue, warm.blue));
  }

  Color _colorFromTempK(double k) {
    // Mapear 2000K (rojizo) a 12000K (azulado)
    final double t = ((k - 2000) / (12000 - 2000)).clamp(0.0, 1.0);
    final Color warm = const Color(0xFFFFB07C);
    final Color cold = const Color(0xFFBFDFFF);
    int lerp(int a, int b) => a + ((b - a) * t).round();
    return Color.fromARGB(255, lerp(warm.red, cold.red), lerp(warm.green, cold.green), lerp(warm.blue, cold.blue));
  }

  void _drawMilkyWayBand(Canvas canvas, Offset center, double radius) {
    canvas.save();
    // Rotar banda con el tiempo de la animación (simulación de rotación celeste)
    final double angle = animationValue * 2 * math.pi;
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.translate(-center.dx, -center.dy);

    // Clip al círculo del cielo
    final Path clip = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.save();
    canvas.clipPath(clip);

    final double bandHalf = radius * 0.18; // ancho de media banda
    final Rect bandRect = Rect.fromLTWH(center.dx - radius, center.dy - bandHalf, radius * 2, bandHalf * 2);
    final Paint bandPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [
          Color(0x00000000),
          Color(0x22B0C4FF),
          Color(0x33FFFFFF),
          Color(0x22B0C4FF),
          Color(0x00000000),
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(bandRect);
    canvas.drawRect(bandRect, bandPaint);

    canvas.restore();
    canvas.restore();
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

  void _drawMoonShaded(Canvas canvas, Offset center, double radius, double phase) {
    // Disco base
    final Paint moon = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFF5F2E9)
      ..blendMode = BlendMode.srcOver;
    canvas.drawCircle(center, radius, moon);

    // Terminador suave usando máscara elíptica y gradiente radial
    final double t = (phase - 0.5); // -0.5..0.5
    final double terminatorOffset = t * radius * 1.2;
    final Rect gradRect = Rect.fromCircle(center: Offset(center.dx + terminatorOffset, center.dy), radius: radius * 1.2);
    final Paint shade = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.black.withOpacity(0.75),
          Colors.black.withOpacity(0.0),
        ],
        stops: const [0.6, 1.0],
      ).createShader(gradRect)
      ..blendMode = BlendMode.dstIn;

    canvas.saveLayer(Rect.fromCircle(center: center, radius: radius * 1.3), Paint());
    // Dibuja un disco negro como sombra en el lado nocturno
    final Path clip = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.clipPath(clip);
    canvas.drawCircle(Offset(center.dx - terminatorOffset, center.dy), radius * 1.05, Paint()..color = Colors.black87);
    // Aplica gradiente para suavizar
    canvas.drawCircle(center, radius * 1.2, shade);
    canvas.restore();

    // Sutil iluminación especular
    final Shader highlightShader = RadialGradient(
      colors: [Colors.white.withOpacity(0.35), Colors.transparent],
      stops: const [0.0, 1.0],
    ).createShader(Rect.fromCircle(center: Offset(center.dx - terminatorOffset * 0.6, center.dy - radius * 0.4), radius: radius));
    canvas.drawCircle(center, radius, Paint()..shader = highlightShader);
  }

  void _drawPlanet(Canvas canvas, Offset center, double radius, Color color, {bool withRings = false}) {
    // Disco del planeta con sombreado radial
    final Paint disk = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withOpacity(1.0),
          Color.lerp(color, Colors.black, 0.4)!,
        ],
        stops: const [0.2, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, disk);

    // Bandas muy sutiles para Júpiter (color anaranjado)
    if (color == const Color(0xFFFFD29B)) {
      final Paint band = Paint()..color = const Color(0x66C78F5A);
      for (int i = -2; i <= 2; i++) {
        final double y = center.dy + i * radius * 0.25;
        canvas.drawLine(Offset(center.dx - radius * 0.9, y), Offset(center.dx + radius * 0.9, y), band);
      }
    }

    // Anillos para Saturno
    if (withRings) {
      final Paint rings = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.6
        ..color = const Color(0x44E0D7B5)
        ..blendMode = BlendMode.srcOver;
      final Rect ellipse = Rect.fromCenter(center: center, width: radius * 3.2, height: radius * 1.4);
      canvas.drawOval(ellipse, rings);
    }

    // Halo leve
    final Paint halo = Paint()
      ..color = color.withOpacity(0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    canvas.drawCircle(center, radius * 1.9, halo);
  }

  Color _planetColor(String name) {
    final String n = name.toLowerCase();
    if (n.contains('mars')) return const Color(0xFFE07A5F);
    if (n.contains('jupiter')) return const Color(0xFFFFD29B);
    if (n.contains('saturn')) return const Color(0xFFEAD7A5);
    if (n.contains('venus')) return const Color(0xFFF2E6C8);
    if (n.contains('mercury')) return const Color(0xFFD0D0D0);
    return const Color(0xFFB0D8FF);
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

// --- AR ligero: cámara + overlay ---
class CameraSkyOverlay extends StatefulWidget {
  const CameraSkyOverlay({super.key, required this.stars, required this.bodies, required this.animationValue});

  final List<VisibleStar> stars;
  final List<VisibleBody> bodies;
  final double animationValue;

  @override
  State<CameraSkyOverlay> createState() => _CameraSkyOverlayState();
}

class _CameraSkyOverlayState extends State<CameraSkyOverlay> {
  CameraController? _cameraController;
  bool _cameraReady = false;
  // StreamSubscription<CompassEvent>? _compassSub;
  double? _headingDeg; // 0..360, 0=N
  StreamSubscription<AccelerometerEvent>? _accelSub;
  double _pitchDeg = 0; // +arriba, -abajo
  double _rollDeg = 0;
  double _headingOffsetDeg = 0; // ajuste manual
  double _horizontalFovDeg = 60;
  double _verticalFovDeg = 45;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String? _targetLabel;
  double? _targetAz;
  double? _targetAlt;

  @override
  void initState() {
    super.initState();
    _initCameraAndSensors();
  }

  Future<void> _initCameraAndSensors() async {
    try {
      // Solicitar permiso de cámara de forma no bloqueante
      final PermissionStatus camStatus = await Permission.camera.request();
      if (!mounted) return;
      if (!camStatus.isGranted) {
        setState(() => _cameraReady = false);
        _subscribeCompass();
        return;
      }
      final List<CameraDescription> cameras = await availableCameras();
      if (!mounted) return;
      final CameraDescription back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.isNotEmpty ? cameras.first : (throw StateError('No cameras')),
      );
      _cameraController = CameraController(back, ResolutionPreset.medium, enableAudio: false);
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() => _cameraReady = true);
      _subscribeCompass();
    } catch (_) {
      if (mounted) setState(() => _cameraReady = false);
      _subscribeCompass();
    }
  }

  void _subscribeCompass() {
    // Si no usamos flutter_compass, mantén headingDeg con offset manual
    _accelSub?.cancel();
    _accelSub = accelerometerEvents.listen((AccelerometerEvent e) {
      // Calcular pitch/roll aproximados
      final double ax = e.x, ay = e.y, az = e.z;
      final double pitchRad = math.atan2(-ax, math.sqrt(ay * ay + az * az));
      final double rollRad = math.atan2(ay, az);
      final double pitch = pitchRad * 180 / math.pi;
      final double roll = rollRad * 180 / math.pi;
      // Suavizado simple
      const double alpha = 0.85;
      _pitchDeg = _pitchDeg * alpha + pitch * (1 - alpha);
      _rollDeg = _rollDeg * alpha + roll * (1 - alpha);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    // _compassSub?.cancel();
    _accelSub?.cancel();
    _cameraController?.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final double headingEffective = ((_headingDeg ?? 0) + _headingOffsetDeg) % 360;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) => _handleTap(details.localPosition, context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_cameraReady && _cameraController != null)
            CameraPreview(_cameraController!)
          else
            Container(color: Colors.black),
          // Overlay AR: proyectar estrellas y cuerpos con rumbo/pitch
          CustomPaint(
            painter: _ArOverlayPainter(
              stars: widget.stars,
              bodies: widget.bodies,
              headingDeg: headingEffective,
              pitchDeg: _pitchDeg,
              rollDeg: _rollDeg,
              horizontalFovDeg: _horizontalFovDeg,
              verticalFovDeg: _verticalFovDeg,
              targetAz: _targetAz,
              targetAlt: _targetAlt,
              targetLabel: _targetLabel,
            ),
          ),
          Positioned(
            top: 10,
            left: 10,
            child: _infoChip(
              _cameraReady ? 'Cámara OK' : 'Cámara no disponible',
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: _infoChip('Rumbo: ${_headingDeg?.toStringAsFixed(0) ?? '--'}° · Adj: ${_headingOffsetDeg.toStringAsFixed(0)}° · Pitch: ${_pitchDeg.toStringAsFixed(0)}°'),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _smallButton('−5°', () => setState(() => _headingOffsetDeg = (_headingOffsetDeg - 5) % 360)),
                const SizedBox(width: 8),
                _smallButton('Reset', () => setState(() => _headingOffsetDeg = 0)),
                const SizedBox(width: 8),
                _smallButton('+5°', () => setState(() => _headingOffsetDeg = (_headingOffsetDeg + 5) % 360)),
              ],
            ),
          ),
          Positioned(
            bottom: 68,
            left: 16,
            right: 16,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0x66000000),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Buscar estrella/planeta (ej. Orion, Marte, Luna)',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _onSearch(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _smallButton('Ir', _onSearch),
                const SizedBox(width: 8),
                _smallButton('X', () => setState(() { _targetAz = null; _targetAlt = null; _targetLabel = null; })),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x66000000),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }

  Widget _smallButton(String label, VoidCallback onTap) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0x99212121),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onTap,
      child: Text(label),
    );
  }

  void _handleTap(Offset localPos, BuildContext context) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Size size = box.size;
    final double halfW = size.width / 2;
    final double halfH = size.height / 2;
    final double headingEffective = ((_headingDeg ?? 0) + _headingOffsetDeg) % 360;

    double wrap180(double deg) {
      double x = ((deg + 180) % 360);
      if (x < 0) x += 360;
      return x - 180;
    }

    VisibleBody? bestBody;
    VisibleStar? bestStar;
    double bestDist = double.infinity;

    // proyectar cuerpos
    for (final VisibleBody b in widget.bodies) {
      if (b.altitude <= 0) continue;
      final double dAz = wrap180(b.azimuth - headingEffective);
      final double dAlt = b.altitude - _pitchDeg;
      if (dAz.abs() > _horizontalFovDeg / 2 || dAlt.abs() > _verticalFovDeg / 2) continue;
      final double x = halfW + (dAz / (_horizontalFovDeg / 2)) * halfW;
      final double y = halfH - (dAlt / (_verticalFovDeg / 2)) * halfH;
      final double r = b.type.toLowerCase() == 'moon' ? 24.0 : 18.0;
      final double d = (localPos - Offset(x, y)).distance;
      if (d <= r && d < bestDist) {
        bestDist = d;
        bestBody = b;
        bestStar = null;
      }
    }

    // proyectar estrellas
    for (final VisibleStar s in widget.stars) {
      if (s.altitude <= 0) continue;
      final double dAz = wrap180(s.azimuth - headingEffective);
      final double dAlt = s.altitude - _pitchDeg;
      if (dAz.abs() > _horizontalFovDeg / 2 || dAlt.abs() > _verticalFovDeg / 2) continue;
      final double x = halfW + (dAz / (_horizontalFovDeg / 2)) * halfW;
      final double y = halfH - (dAlt / (_verticalFovDeg / 2)) * halfH;
      final double base = 4.5 - (s.magnitude + 1.5) * 0.7;
      final double r = (base.clamp(1.0, 4.5) * 6).clamp(10.0, 18.0);
      final double d = (localPos - Offset(x, y)).distance;
      if (d <= r && d < bestDist) {
        bestDist = d;
        bestStar = s;
        bestBody = null;
      }
    }

    if (bestBody != null) {
      _showBodySheet(context, bestBody);
      return;
    }
    if (bestStar != null) {
      _showStarSheet(context, bestStar);
    }
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
        const double navOverlayHeight = 30;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + navOverlayHeight + bottomSafe),
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
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _infoLine('Magnitud', star.magnitude.toStringAsFixed(2)),
              _infoLine('Altitud', '${star.altitude.toStringAsFixed(1)}°'),
              _infoLine('Azimut', '${star.azimuth.toStringAsFixed(1)}°'),
              if (star.distance != null) _infoLine('Distancia', _formatDistance(star.distance!)),
              const SizedBox(height: 12),
            ],
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
        const double navOverlayHeight = 30;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + navOverlayHeight + bottomSafe),
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
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _infoLine('Tipo', body.type),
              _infoLine('Magnitud', body.magnitude.toStringAsFixed(2)),
              _infoLine('Altitud', '${body.altitude.toStringAsFixed(1)}°'),
              _infoLine('Azimut', '${body.azimuth.toStringAsFixed(1)}°'),
              if (body.phase != null) _infoLine('Fase', (body.phase! * 100).toStringAsFixed(0) + '%'),
              if (body.distance != null) _infoLine('Distancia', _formatDistance(body.distance!)),
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
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  String _formatDistance(double value) {
    return value >= 1000 ? '${(value / 1000).toStringAsFixed(2)} k' : value.toStringAsFixed(2);
  }

  void _onSearch() {
    final String query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    final String cq = _canonical(query);
    VisibleBody? body;
    // Priorizar cuerpos (planetas/Luna)
    for (final b in widget.bodies) {
      if (_canonical(b.name).contains(cq)) { body = b; break; }
    }
    final VisibleBody? pickedBody = body;
    if (pickedBody != null) {
      setState(() {
        _targetAz = pickedBody.azimuth;
        _targetAlt = pickedBody.altitude;
        _targetLabel = pickedBody.name;
      });
      return;
    }
    // Buscar estrellas, incluyendo aliases
    VisibleStar? star;
    for (final s in widget.stars) {
      if (_canonical(s.name).contains(cq)) { star = s; break; }
      if (s.aliases.isNotEmpty) {
        final bool any = s.aliases.any((a) => _canonical(a).contains(cq));
        if (any) { star = s; break; }
      }
    }
    final VisibleStar? pickedStar = star;
    if (pickedStar != null) {
      setState(() {
        _targetAz = pickedStar.azimuth;
        _targetAlt = pickedStar.altitude;
        _targetLabel = pickedStar.name;
      });
    }
  }

  String _canonical(String raw) {
    String s = raw.trim().toLowerCase();
    const Map<String, String> acc = {
      'á':'a','à':'a','ä':'a','â':'a',
      'é':'e','è':'e','ë':'e','ê':'e',
      'í':'i','ì':'i','ï':'i','î':'i',
      'ó':'o','ò':'o','ö':'o','ô':'o',
      'ú':'u','ù':'u','ü':'u','û':'u','ñ':'n'
    };
    acc.forEach((k,v){ s = s.replaceAll(k,v);});
    const Map<String,String> greek={
      'α':'alpha','β':'beta','γ':'gamma','δ':'delta','ε':'epsilon','ζ':'zeta','η':'eta','θ':'theta','ι':'iota','κ':'kappa','λ':'lambda','μ':'mu','ν':'nu','ξ':'xi','ο':'omicron','π':'pi','ρ':'rho','σ':'sigma','τ':'tau','υ':'upsilon','φ':'phi','χ':'chi','ψ':'psi','ω':'omega'
    };
    greek.forEach((k,v){ s = s.replaceAll(k,v);});
    s = s.replaceAll(RegExp(r"[^a-z0-9\s]"), ' ');
    s = s.replaceAll(RegExp(r"\s+"), ' ').trim();
    return s;
  }
}

class _ArOverlayPainter extends CustomPainter {
  _ArOverlayPainter({
    required this.stars,
    required this.bodies,
    required this.headingDeg,
    required this.pitchDeg,
    required this.rollDeg,
    required this.horizontalFovDeg,
    required this.verticalFovDeg,
    this.targetAz,
    this.targetAlt,
    this.targetLabel,
  });

  final List<VisibleStar> stars;
  final List<VisibleBody> bodies;
  final double headingDeg; // 0=N
  final double pitchDeg; // +arriba
  final double rollDeg;
  final double horizontalFovDeg;
  final double verticalFovDeg;
  final double? targetAz;
  final double? targetAlt;
  final String? targetLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()..style = PaintingStyle.fill;
    final double halfW = size.width / 2;
    final double halfH = size.height / 2;

    void drawPoint(double dx, double dy, Color color, double r, [String? label]) {
      p.color = color.withOpacity(0.95);
      canvas.drawCircle(Offset(dx, dy), r, p);
      p.color = color.withOpacity(0.35);
      canvas.drawCircle(Offset(dx, dy), r * 2.0, p);
      if (label != null) {
        final TextPainter tp = TextPainter(
          text: TextSpan(text: label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(dx + 6, dy - 6));
      }
    }

    double wrap180(double deg) {
      double x = ((deg + 180) % 360);
      if (x < 0) x += 360;
      return x - 180;
    }

    // Dibujar estrellas
    for (final VisibleStar s in stars) {
      if (s.altitude <= 0) continue;
      final double dAz = wrap180(s.azimuth - headingDeg);
      final double dAlt = s.altitude - pitchDeg;
      if (dAz.abs() > horizontalFovDeg / 2 || dAlt.abs() > verticalFovDeg / 2) continue;
      final double x = halfW + (dAz / (horizontalFovDeg / 2)) * halfW;
      final double y = halfH - (dAlt / (verticalFovDeg / 2)) * halfH;
      final double r = (4.5 - (s.magnitude + 1.5) * 0.6).clamp(1.5, 5.0);
      drawPoint(x, y, Colors.white, r, s.magnitude <= 1.0 ? s.name : null);
    }

    // Dibujar cuerpos
    for (final VisibleBody b in bodies) {
      if (b.altitude <= 0) continue;
      final double dAz = wrap180(b.azimuth - headingDeg);
      final double dAlt = b.altitude - pitchDeg;
      if (dAz.abs() > horizontalFovDeg / 2 || dAlt.abs() > verticalFovDeg / 2) continue;
      final double x = halfW + (dAz / (horizontalFovDeg / 2)) * halfW;
      final double y = halfH - (dAlt / (verticalFovDeg / 2)) * halfH;
      final bool isMoon = b.type.toLowerCase() == 'moon';
      final bool isPlanet = b.type.toLowerCase() == 'planet';
      final Color color = isMoon
          ? const Color(0xFFFFF3C4)
          : isPlanet
              ? const Color(0xFF99E0FF)
              : Colors.white;
      final double r = isMoon ? 7.0 : 5.0;
      drawPoint(x, y, color, r, b.name);
    }

    // Retícula simple
    final Paint cross = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(halfW - 10, halfH), Offset(halfW + 10, halfH), cross);
    canvas.drawLine(Offset(halfW, halfH - 10), Offset(halfW, halfH + 10), cross);

    // Flecha hacia objetivo si está fuera de FOV
    if (targetAz != null && targetAlt != null) {
      final double dAz = wrap180(targetAz! - headingDeg);
      final double dAlt = targetAlt! - pitchDeg;
      final bool inFov = dAz.abs() <= horizontalFovDeg / 2 && dAlt.abs() <= verticalFovDeg / 2;
      final Paint arrow = Paint()..color = const Color(0xFFFFD54F);
      if (inFov) {
        final double x = halfW + (dAz / (horizontalFovDeg / 2)) * halfW;
        final double y = halfH - (dAlt / (verticalFovDeg / 2)) * halfH;
        canvas.drawCircle(Offset(x, y), 6, arrow);
        final TextPainter tp = TextPainter(
          text: TextSpan(text: targetLabel ?? 'Objetivo', style: const TextStyle(color: Colors.white)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 8, y - 8));
      } else {
        // Dibujar en el borde la dirección horizontal
        final double angle = math.atan2(-dAlt, dAz); // orientación aproximada
        final double x = halfW + (halfW - 20) * math.cos(angle);
        final double y = halfH - (halfH - 20) * math.sin(angle);
        final Path tri = Path()
          ..moveTo(x, y)
          ..lineTo(x - 10, y + 6)
          ..lineTo(x - 10, y - 6)
          ..close();
        canvas.drawPath(tri, arrow);
      }
    }
  }

    @override
    bool shouldRepaint(covariant _ArOverlayPainter oldDelegate) {
      return oldDelegate.stars != stars ||
          oldDelegate.bodies != bodies ||
          oldDelegate.headingDeg != headingDeg ||
          oldDelegate.pitchDeg != pitchDeg ||
          oldDelegate.rollDeg != rollDeg ||
          oldDelegate.horizontalFovDeg != horizontalFovDeg ||
          oldDelegate.verticalFovDeg != verticalFovDeg;
    }
}

