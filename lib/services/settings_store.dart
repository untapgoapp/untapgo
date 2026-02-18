import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DistanceUnit { km, mi }
enum LocationSource { gps, zip }

class SettingsStore {
  // Distance / sorting
  static const _kDistanceUnit = 'distance_unit'; // 'km' | 'mi'
  static const _kSortByDistance = 'sort_by_distance'; // bool

  // Location
  static const _kLocationSource = 'location_source'; // 'gps' | 'zip'
  static const _kManualZip = 'manual_zip';
  static const _kLat = 'location_lat';
  static const _kLng = 'location_lng';

  // Notifiers
  static final ValueNotifier<DistanceUnit> _distanceUnit =
      ValueNotifier<DistanceUnit>(DistanceUnit.km);

  static final ValueNotifier<bool> _sortByDistance =
      ValueNotifier<bool>(true);

  static final ValueNotifier<LocationSource> _locationSource =
      ValueNotifier<LocationSource>(LocationSource.gps);

  static final ValueNotifier<String?> _manualZip =
      ValueNotifier<String?>(null);

  static final ValueNotifier<double?> _lat =
      ValueNotifier<double?>(null);

  static final ValueNotifier<double?> _lng =
      ValueNotifier<double?>(null);

  // Exposed listenables / getters
  static ValueListenable<DistanceUnit> get distanceUnit => _distanceUnit;
  static DistanceUnit get currentDistanceUnit => _distanceUnit.value;

  static ValueListenable<bool> get sortByDistance => _sortByDistance;
  static bool get currentSortByDistance => _sortByDistance.value;

  static ValueListenable<LocationSource> get locationSource => _locationSource;
  static LocationSource get currentLocationSource => _locationSource.value;

  static ValueListenable<String?> get manualZip => _manualZip;
  static String? get currentManualZip => _manualZip.value;

  static double? get currentLat => _lat.value;
  static double? get currentLng => _lng.value;

  static bool get isMiles => _distanceUnit.value == DistanceUnit.mi;
  static bool get isKilometers => _distanceUnit.value == DistanceUnit.km;

  static bool get isUsingGps => _locationSource.value == LocationSource.gps;
  static bool get isUsingZip => _locationSource.value == LocationSource.zip;

  static bool get hasLocation => _lat.value != null && _lng.value != null;

  // Parsers / serializers
  static DistanceUnit _parseDistanceUnit(String? raw) {
    return raw == 'mi' ? DistanceUnit.mi : DistanceUnit.km;
  }

  static String _serializeDistanceUnit(DistanceUnit unit) {
    return unit == DistanceUnit.mi ? 'mi' : 'km';
  }

  static LocationSource _parseLocationSource(String? raw) {
    return raw == 'zip' ? LocationSource.zip : LocationSource.gps;
  }

  static String _serializeLocationSource(LocationSource source) {
    return source == LocationSource.zip ? 'zip' : 'gps';
  }

  // Init
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    final loadedUnit = _parseDistanceUnit(
      prefs.getString(_kDistanceUnit),
    );
    if (_distanceUnit.value != loadedUnit) {
      _distanceUnit.value = loadedUnit;
    }

    final loadedSort = prefs.getBool(_kSortByDistance) ?? true;
    if (_sortByDistance.value != loadedSort) {
      _sortByDistance.value = loadedSort;
    }

    final loadedSource = _parseLocationSource(
      prefs.getString(_kLocationSource),
    );
    if (_locationSource.value != loadedSource) {
      _locationSource.value = loadedSource;
    }

    _manualZip.value = prefs.getString(_kManualZip);
    _lat.value = prefs.getDouble(_kLat);
    _lng.value = prefs.getDouble(_kLng);
  }

  // Distance / sorting setters
  static Future<void> setDistanceUnit(DistanceUnit unit) async {
    if (_distanceUnit.value == unit) return;

    _distanceUnit.value = unit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kDistanceUnit,
      _serializeDistanceUnit(unit),
    );
  }

  static Future<void> setSortByDistance(bool enabled) async {
    if (_sortByDistance.value == enabled) return;

    _sortByDistance.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSortByDistance, enabled);
  }

  // Location setters
  static Future<void> setGpsLocation({
    required double lat,
    required double lng,
  }) async {
    _locationSource.value = LocationSource.gps;
    _manualZip.value = null;
    _lat.value = lat;
    _lng.value = lng;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kLocationSource,
      _serializeLocationSource(LocationSource.gps),
    );
    await prefs.remove(_kManualZip);
    await prefs.setDouble(_kLat, lat);
    await prefs.setDouble(_kLng, lng);
  }

  static Future<void> setZipLocation({
    required String zip,
    required double lat,
    required double lng,
  }) async {
    _locationSource.value = LocationSource.zip;
    _manualZip.value = zip;
    _lat.value = lat;
    _lng.value = lng;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kLocationSource,
      _serializeLocationSource(LocationSource.zip),
    );
    await prefs.setString(_kManualZip, zip);
    await prefs.setDouble(_kLat, lat);
    await prefs.setDouble(_kLng, lng);
  }
}
 