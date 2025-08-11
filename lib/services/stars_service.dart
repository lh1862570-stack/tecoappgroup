import 'dart:convert';
import 'package:http/http.dart' as http;

class VisibleStar {
  VisibleStar({
    required this.name,
    required this.magnitude,
    required this.altitude,
    required this.azimuth,
    this.distance,
  });

  final String name;
  final double magnitude;
  final double altitude;
  final double azimuth;
  final double? distance; // opcional

  factory VisibleStar.fromJson(Map<String, dynamic> json) {
    // Accept both English and Spanish keys just in case
    String? name = (json['name'] ?? json['nombre']) as String?;
    num? magnitude = (json['magnitude'] ?? json['magnitud']) as num?;
    num? altitude = (json['altitude'] ?? json['altitud'] ?? json['altitude_deg']) as num?;
    num? azimuth = (json['azimuth'] ?? json['azimut'] ?? json['azimuth_deg']) as num?;
    final num? distance = (json['distance'] ?? json['distancia']) as num?;

    if (name == null || magnitude == null || altitude == null || azimuth == null) {
      throw const FormatException('Respuesta inválida: faltan campos esperados');
    }

    return VisibleStar(
      name: name,
      magnitude: magnitude.toDouble(),
      altitude: altitude.toDouble(),
      azimuth: azimuth.toDouble(),
      distance: distance?.toDouble(),
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
    final uri = Uri.parse('$baseUrl/visible-stars');

    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        'datetime': when.toUtc().toIso8601String(),
      }),
    );

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
    final uri = Uri.parse('$baseUrl/astronomy-events');
    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        'start_datetime': startUtc.toIso8601String(),
        'end_datetime': endUtc.toIso8601String(),
      }),
    );

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


