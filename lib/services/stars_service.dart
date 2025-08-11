import 'dart:convert';
import 'package:http/http.dart' as http;

class VisibleStar {
  VisibleStar({
    required this.name,
    required this.magnitude,
    required this.altitude,
    required this.azimuth,
  });

  final String name;
  final double magnitude;
  final double altitude;
  final double azimuth;

  factory VisibleStar.fromJson(Map<String, dynamic> json) {
    // Accept both English and Spanish keys just in case
    String? name = (json['name'] ?? json['nombre']) as String?;
    num? magnitude = (json['magnitude'] ?? json['magnitud']) as num?;
    num? altitude = (json['altitude'] ?? json['altitud']) as num?;
    num? azimuth = (json['azimuth'] ?? json['azimut']) as num?;

    if (name == null || magnitude == null || altitude == null || azimuth == null) {
      throw const FormatException('Respuesta inválida: faltan campos esperados');
    }

    return VisibleStar(
      name: name,
      magnitude: magnitude.toDouble(),
      altitude: altitude.toDouble(),
      azimuth: azimuth.toDouble(),
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


