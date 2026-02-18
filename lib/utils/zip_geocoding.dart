import 'dart:convert';
import 'package:http/http.dart' as http;

class LatLngResult {
  final double lat;
  final double lng;

  const LatLngResult({
    required this.lat,
    required this.lng,
  });
}

class ZipGeocoding {
  static const _baseUrl =
      'https://maps.googleapis.com/maps/api/geocode/json';

  static Future<LatLngResult?> geocodeZip(
    String zip, {
    required String apiKey,
    String country = 'US',
  }) async {
    final uri = Uri.parse(
      '$_baseUrl?address=$zip&components=country:$country&key=$apiKey',
    );

    final res = await http.get(uri);
    if (res.statusCode != 200) return null;

    final json = jsonDecode(res.body);
    if (json['status'] != 'OK') return null;

    final location =
        json['results'][0]['geometry']['location'];

    return LatLngResult(
      lat: (location['lat'] as num).toDouble(),
      lng: (location['lng'] as num).toDouble(),
    );
  }
}
