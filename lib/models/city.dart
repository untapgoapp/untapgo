class City {
  final int id;
  final String name;
  final double centerLat;
  final double centerLng;
  final int radiusM;

  City({
    required this.id,
    required this.name,
    required this.centerLat,
    required this.centerLng,
    required this.radiusM,
  });

  factory City.fromJson(Map<String, dynamic> j) => City(
        id: j['id'] as int,
        name: j['name'] as String,
        centerLat: (j['center_lat'] as num).toDouble(),
        centerLng: (j['center_lng'] as num).toDouble(),
        radiusM: (j['radius_m'] as num).toInt(),
      );
}
