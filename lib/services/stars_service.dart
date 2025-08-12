import 'dart:convert';
import 'package:http/http.dart' as http;
class VisibleStarFrame {
  VisibleStarFrame({required this.when, required this.star});
  final DateTime when;
  final VisibleStar star;
}

class VisibleStar {
  VisibleStar({
    required this.name,
    required this.magnitude,
    required this.altitude,
    required this.azimuth,
    this.distance,
    this.aliases = const <String>[],
    this.colorTempK,
    this.bv,
    this.rgbHex,
  });

  final String name;
  final double magnitude;
  final double altitude;
  final double azimuth;
  final double? distance; // opcional
  final List<String> aliases; // opcional
  final double? colorTempK; // opcional (Kelvin)
  final double? bv; // opcional (índice B–V)
  final String? rgbHex; // opcional "#RRGGBB"

  factory VisibleStar.fromJson(Map<String, dynamic> json) {
    // Accept both English and Spanish keys just in case
    String? name = (json['name'] ?? json['nombre']) as String?;
    num? magnitude = (json['magnitude'] ?? json['magnitud']) as num?;
    num? altitude = (json['altitude'] ?? json['altitud'] ?? json['altitude_deg']) as num?;
    num? azimuth = (json['azimuth'] ?? json['azimut'] ?? json['azimuth_deg']) as num?;
    final num? distance = (json['distance'] ?? json['distancia'] ?? json['distance_ly'] ?? json['distance_km'] ?? json['distance_au']) as num?;
    final List<String> aliases = (json['aliases'] as List?)?.whereType<String>().toList() ?? const <String>[];
    final num? colorTempK = (json['color_temp_K'] ?? json['color_temp_k'] ?? json['colorTempK']) as num?;
    final num? bv = (json['bv'] ?? json['B-V'] ?? json['b_v']) as num?;
    final String? rgbHex = json['rgb_hex'] as String?;

    if (name == null || magnitude == null || altitude == null || azimuth == null) {
      throw const FormatException('Respuesta inválida: faltan campos esperados');
    }

    return VisibleStar(
      name: name,
      magnitude: magnitude.toDouble(),
      altitude: altitude.toDouble(),
      azimuth: azimuth.toDouble(),
      distance: distance?.toDouble(),
      aliases: aliases,
      colorTempK: colorTempK?.toDouble(),
      bv: bv?.toDouble(),
      rgbHex: rgbHex,
    );
  }
}

class StarsService {
  StarsService({this.baseUrl = 'http://127.0.0.1:8000'});

  final String baseUrl;

  /// Envía latitud, longitud y fecha/hora ISO 8601, y devuelve la lista de estrellas visibles.
  Future<List<VisibleStar>> fetchVisibleStars({
    required double latitude,
    required double longitude,
    required DateTime when,
  }) async {
    final uri = Uri.parse('$baseUrl/visible-stars').replace(queryParameters: <String, String>{
      'lat': latitude.toString(),
      'lon': longitude.toString(),
      'at': when.toUtc().toIso8601String(),
    });

    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Error ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('La respuesta debe ser una lista');
    }

    return decoded
        .cast<dynamic>()
        .map<VisibleStar>((dynamic item) => VisibleStar.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<List<VisibleStarFrame>>> fetchVisibleStarsBatch({
    required double latitude,
    required double longitude,
    required DateTime start,
    required DateTime end,
    int stepHours = 1,
  }) async {
    final uri = Uri.parse('$baseUrl/visible-stars-batch').replace(queryParameters: <String, String>{
      'lat': latitude.toString(),
      'lon': longitude.toString(),
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
      'step_hours': stepHours.toString(),
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) {
      return const <List<VisibleStarFrame>>[]; // no disponible
    }
    if (response.statusCode != 200) {
      throw Exception('Error ${response.statusCode}: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Batch inválido: se esperaba objeto con frames');
    }
    final List<dynamic>? frames = decoded['frames'] as List<dynamic>?;
    if (frames == null) return const <List<VisibleStarFrame>>[];
    return frames.map<List<VisibleStarFrame>>((dynamic fr) {
      final Map<String, dynamic> m = fr as Map<String, dynamic>;
      final String at = (m['at'] ?? m['time'] ?? m['datetime']) as String;
      final DateTime when = DateTime.parse(at).toUtc();
      final List<dynamic> stars = (m['stars'] ?? m['data']) as List<dynamic>;
      return stars
          .map<VisibleStarFrame>((dynamic s) => VisibleStarFrame(
                when: when,
                star: VisibleStar.fromJson(s as Map<String, dynamic>),
              ))
          .toList();
    }).toList();
  }
}


class VisibleBody {
  VisibleBody({
    required this.name,
    required this.type,
    required this.magnitude,
    required this.altitude,
    required this.azimuth,
    this.phase,
    this.distance,
  });

  final String name; // e.g., Mars, Jupiter, Moon
  final String type; // planet, moon, sun, comet, etc.
  final double magnitude;
  final double altitude;
  final double azimuth;
  final double? phase; // 0..1 (principal para la Luna), opcional
  final double? distance; // opcional (unidades según backend)

  factory VisibleBody.fromJson(Map<String, dynamic> json) {
    final String? name = (json['name'] ?? json['nombre']) as String?;
    final String? type = (json['type'] ?? json['tipo']) as String?;
    final num? magnitude = (json['magnitude'] ?? json['magnitud']) as num?;
    final num? altitude = (json['altitude'] ?? json['altitud'] ?? json['altitude_deg']) as num?;
    final num? azimuth = (json['azimuth'] ?? json['azimut'] ?? json['azimuth_deg']) as num?;
    final num? phase = (json['phase'] ?? json['fase']) as num?;
    final num? distance = (json['distance'] ?? json['distancia']) as num?;
    if (name == null || type == null || magnitude == null || altitude == null || azimuth == null) {
      throw const FormatException('Cuerpo inválido: faltan campos');
    }
    return VisibleBody(
      name: name,
      type: type,
      magnitude: magnitude.toDouble(),
      altitude: altitude.toDouble(),
      azimuth: azimuth.toDouble(),
      phase: phase?.toDouble(),
      distance: distance?.toDouble(),
    );
  }
}

extension StarsServiceBodies on StarsService {
  Future<List<VisibleBody>> fetchVisibleBodies({
    required double latitude,
    required double longitude,
    required DateTime when,
  }) async {
    final uri = Uri.parse('$baseUrl/visible-bodies').replace(queryParameters: <String, String>{
      'lat': latitude.toString(),
      'lon': longitude.toString(),
      'at': when.toUtc().toIso8601String(),
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode == 404) {
      return const <VisibleBody>[]; // endpoint no disponible
    }
    if (response.statusCode != 200) {
      throw Exception('Error ${response.statusCode}: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('La respuesta de cuerpos debe ser una lista');
    }
    return decoded
        .cast<dynamic>()
        .map<VisibleBody>((dynamic item) => VisibleBody.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}

class AstronomyEvent {
  AstronomyEvent({
    required this.type,
    required this.time,
    required this.description,
  });

  final String type; // e.g., planet_rise, planet_set, moon_phase, solar_eclipse, lunar_eclipse
  final DateTime time; // UTC
  final String description;

  factory AstronomyEvent.fromJson(Map<String, dynamic> json) {
    final String? type = json['type'] as String?;
    final String? timeStr = (json['time'] ?? json['datetime']) as String?;
    final String? description = json['description'] as String?;
    if (type == null || timeStr == null || description == null) {
      throw const FormatException('Evento inválido: faltan campos');
    }
    return AstronomyEvent(
      type: type,
      time: DateTime.parse(timeStr).toUtc(),
      description: description,
    );
  }
}

extension StarsServiceEvents on StarsService {
  Future<List<AstronomyEvent>> fetchAstronomyEvents({
    required double latitude,
    required double longitude,
    required DateTime startUtc,
    required DateTime endUtc,
  }) async {
    final uri = Uri.parse('$baseUrl/astronomy-events').replace(queryParameters: <String, String>{
      'lat': latitude.toString(),
      'lon': longitude.toString(),
      'start_datetime': startUtc.toIso8601String(),
      'end_datetime': endUtc.toIso8601String(),
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode == 404) {
      // Endpoint no existe en el backend actual: retornar vacío sin error
      return const <AstronomyEvent>[];
    }
    if (response.statusCode != 200) {
      throw Exception('Error ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('La respuesta de eventos debe ser una lista');
    }
    return decoded
        .cast<dynamic>()
        .map<AstronomyEvent>((dynamic item) => AstronomyEvent.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}


