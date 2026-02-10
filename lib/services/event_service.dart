import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/event.dart';

/// Lightweight model for pending requests (host review UI).
class EventJoinRequest {
  final String userId;
  final String? nickname;
  final String? avatarUrl;
  final DateTime? requestedAt;

  EventJoinRequest({
    required this.userId,
    this.nickname,
    this.avatarUrl,
    this.requestedAt,
  });

  factory EventJoinRequest.fromJson(Map<String, dynamic> json) {
    DateTime? dt;
    final raw = json['requested_at']?.toString();
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        dt = DateTime.parse(raw);
      } catch (_) {}
    }

    return EventJoinRequest(
      userId: json['id']?.toString() ?? json['user_id']?.toString() ?? '',
      nickname: json['nickname']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      requestedAt: dt,
    );
  }
}

/// Returned by join/leave/accept/reject when backend responds with JSON.
class EventActionResult {
  final bool ok;
  final String? myStatus; // 'pending' | 'joined' | 'rejected' | 'kicked' | null
  final int? cooldownSeconds;
  final Map<String, dynamic> raw;

  EventActionResult({
    required this.ok,
    required this.raw,
    this.myStatus,
    this.cooldownSeconds,
  });

  factory EventActionResult.fromJson(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final ok = decoded['ok'] == true || decoded['success'] == true;

      final myStatus =
          (decoded['my_status'] ?? decoded['myStatus'])?.toString();

      final cs = decoded['cooldown_seconds'] ?? decoded['cooldownSeconds'];
      int? cooldownSeconds;
      if (cs is int) cooldownSeconds = cs;
      if (cs is num) cooldownSeconds = cs.toInt();
      if (cs is String) cooldownSeconds = int.tryParse(cs);

      return EventActionResult(
        ok: ok,
        myStatus: myStatus,
        cooldownSeconds: cooldownSeconds,
        raw: decoded,
      );
    }

    return EventActionResult(ok: true, raw: <String, dynamic>{});
  }
}

/// Typed error for join cooldown (kicked/rejected anti-spam).
class CooldownException implements Exception {
  final String code;
  final int? cooldownSeconds;
  final String? cooldownUntilHHMM;

  CooldownException({
    required this.code,
    this.cooldownSeconds,
    this.cooldownUntilHHMM,
  });

  @override
  String toString() {
    if (cooldownSeconds != null) {
      return '$code|seconds=$cooldownSeconds';
    }
    if (cooldownUntilHHMM != null && cooldownUntilHHMM!.trim().isNotEmpty) {
      return '$code|until=$cooldownUntilHHMM';
    }
    return code;
  }
}

class EventService {
  /// ✅ PRODUCCIÓN
  static const String backendBaseUrl = 'https://tapin-backend.fly.dev';
  static const Duration _timeout = Duration(seconds: 12);

  /// 🔐 Authorization obligatorio
  Map<String, String> _headers({bool json = false}) {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) {
      throw Exception('No Supabase access token available');
    }

    return <String, String>{
      if (json) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ---------------------------
  // Error helpers
  // ---------------------------

  int? _cooldownSecondsFromBody(String body) {
    try {
      final decoded = jsonDecode(body);
      final detail = (decoded is Map) ? decoded['detail'] : null;

      if (detail is Map) {
        final code = detail['code']?.toString();
        if (code == 'KICK_COOLDOWN_ACTIVE' || code == 'JOIN_COOLDOWN_ACTIVE') {
          final secs = detail['cooldown_seconds'];
          if (secs is int) return secs;
          if (secs is num) return secs.toInt();
          if (secs is String) return int.tryParse(secs);
        }
      }
    } catch (_) {}
    return null;
  }

  String? _cooldownHHMMFromBody(String body) {
    try {
      final decoded = jsonDecode(body);
      final detail = (decoded is Map) ? decoded['detail'] : null;

      if (detail is Map) {
        final code = detail['code']?.toString();
        if (code == 'KICK_COOLDOWN_ACTIVE' || code == 'JOIN_COOLDOWN_ACTIVE') {
          final until = detail['cooldown_until']?.toString();
          if (until != null && until.trim().isNotEmpty) {
            final s = until.trim();
            if (RegExp(r'^\d{2}:\d{2}$').hasMatch(s)) return s;
          }
        }
      }

      if (detail is String) {
        final s = detail.trim();
        if (RegExp(r'^\d{2}:\d{2}$').hasMatch(s)) return s;
      }
    } catch (_) {}
    return null;
  }

  String? _cooldownCodeFromBody(String body) {
    try {
      final decoded = jsonDecode(body);
      final detail = (decoded is Map) ? decoded['detail'] : null;
      if (detail is Map) {
        final code = detail['code']?.toString();
        if (code == 'KICK_COOLDOWN_ACTIVE' || code == 'JOIN_COOLDOWN_ACTIVE') {
          return code;
        }
      }
    } catch (_) {}
    return null;
  }

  Never _throwHttp(String method, Uri url, http.Response res) {
    final body = res.body;

    final code = _cooldownCodeFromBody(body);
    final secs = _cooldownSecondsFromBody(body);
    if (code != null && secs != null) {
      throw CooldownException(code: code, cooldownSeconds: secs);
    }

    final hhmm = _cooldownHHMMFromBody(body);
    if (code != null && hhmm != null) {
      throw CooldownException(code: code, cooldownUntilHHMM: hhmm);
    }

    throw Exception('$method $url failed: ${res.statusCode} $body');
  }

  Future<void> _waitForSession({int maxMs = 5000}) async {
    final tries = (maxMs / 100).round();
    for (var i = 0; i < tries; i++) {
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token != null) return;
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  List<Event> _decodeEvents(String body, Uri uri) {
    final decoded = jsonDecode(body);

    if (decoded is List) {
      return decoded
          .map((e) => Event.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    if (decoded is Map<String, dynamic> && decoded['events'] is List) {
      final list = decoded['events'] as List;
      return list
          .map((e) => Event.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw Exception('GET $uri returned unexpected shape: $body');
  }

  EventActionResult _decodeActionResult(String body) {
    try {
      final decoded = jsonDecode(body);
      return EventActionResult.fromJson(decoded);
    } catch (_) {
      return EventActionResult(ok: true, raw: <String, dynamic>{});
    }
  }

  // ---------------------------
  // API
  // ---------------------------

  /// ✅ All feed (optionally ask backend to compute distance_km if lat/lng provided)
  Future<List<Event>> fetchEvents({
    bool includeFull = true,
    double? lat,
    double? lng,
  }) async {
    final base = Uri.parse('$backendBaseUrl/events');

    final qp = <String, String>{
      'include_full': includeFull.toString(),
      if (lat != null && lng != null) 'lat': lat.toString(),
      if (lat != null && lng != null) 'lng': lng.toString(),
    };

    final uri = base.replace(queryParameters: qp);

    await _waitForSession(maxMs: 5000);

    final res = await http.get(uri, headers: _headers()).timeout(_timeout);
    if (res.statusCode != 200) _throwHttp('GET', uri, res);

    return _decodeEvents(res.body, uri);
  }

  Future<List<Event>> fetchAllEvents() async {
    final uri = Uri.parse('$backendBaseUrl/events/all');

    await _waitForSession(maxMs: 5000);

    final res = await http.get(uri, headers: _headers()).timeout(_timeout);
    if (res.statusCode != 200) _throwHttp('GET', uri, res);

    return _decodeEvents(res.body, uri);
  }

  Future<List<Event>> fetchMyEvents() async {
    final uri = Uri.parse('$backendBaseUrl/events/mine');

    await _waitForSession(maxMs: 5000);

    final res = await http.get(uri, headers: _headers()).timeout(_timeout);
    if (res.statusCode != 200) _throwHttp('GET', uri, res);

    return _decodeEvents(res.body, uri);
  }

  /// ✅ Nearby feed (server-side distance + filtering).
  Future<List<Event>> fetchNearbyEvents({
    required double lat,
    required double lng,
    int radiusKm = 50,
    bool includeFull = true,
  }) async {
    final base = Uri.parse('$backendBaseUrl/events/nearby');
    final uri = base.replace(queryParameters: {
      'lat': lat.toString(),
      'lng': lng.toString(),
      'radius_km': radiusKm.toString(),
      'include_full': includeFull.toString(),
    });

    await _waitForSession(maxMs: 5000);

    final res = await http.get(uri, headers: _headers()).timeout(_timeout);
    if (res.statusCode != 200) _throwHttp('GET', uri, res);

    return _decodeEvents(res.body, uri);
  }

  Future<String> createEvent({
    required String title,
    required DateTime startsAt,
    required int durationMinutes,
    required int maxPlayers,
    required String powerLevel,
    required String proxiesPolicy,
    required String format_slug, // ✅ NEW
    required String addressText,
    required String placeId,
    required double lat,
    required double lng,
    String? hostNotes,
  }) async {
    final uri = Uri.parse('$backendBaseUrl/events');

    await _waitForSession(maxMs: 5000);

    final body = <String, dynamic>{
      'title': title,
      'description': '',
      'starts_at': startsAt.toIso8601String(),
      'duration_minutes': durationMinutes,
      'max_players': maxPlayers,
      'power_level': powerLevel,
      'proxies_policy': proxiesPolicy,
      'format_slug': format_slug, // ✅ NEW
      'address_text': addressText,
      'place_id': placeId,
      'lat': lat,
      'lng': lng,
      if (hostNotes != null) 'host_notes': hostNotes,
    };

    final res = await http
        .post(uri, headers: _headers(json: true), body: jsonEncode(body))
        .timeout(_timeout);

    if (res.statusCode != 200 && res.statusCode != 201) {
      _throwHttp('POST', uri, res);
    }

    final decoded = jsonDecode(res.body);

    String? id;

    if (decoded is List && decoded.isNotEmpty) {
      final first = decoded.first;
      if (first is Map) {
        final v = first['id'];
        if (v != null) id = v.toString();
      }
    }

    if (id == null && decoded is Map) {
      final direct = decoded['id'];
      if (direct != null) id = direct.toString();

      if (id == null) {
        final eventObj = decoded['event'];
        if (eventObj is Map) {
          final nested = eventObj['id'];
          if (nested != null) id = nested.toString();
        }
      }
    }

    if (id == null || id.trim().isEmpty) {
      throw Exception('Create event succeeded but response had no id: ${res.body}');
    }

    return id;
  }

  /// ✅ PATCH /events/{eventId} (used by EditEventScreen)
  Future<Event> updateEvent({
    required String eventId,
    required Map<String, dynamic> patch,
  }) async {
    final uri = Uri.parse('$backendBaseUrl/events/$eventId');

    await _waitForSession(maxMs: 5000);

    final res = await http
        .patch(uri, headers: _headers(json: true), body: jsonEncode(patch))
        .timeout(_timeout);

    if (res.statusCode != 200) {
      _throwHttp('PATCH', uri, res);
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) {
      return Event.fromJson(decoded);
    }
    throw Exception('PATCH $uri returned unexpected shape: ${res.body}');
  }

  /// Join now creates a REQUEST (pending).
  Future<EventActionResult> joinEvent(String eventId) async {
    final uri = Uri.parse('$backendBaseUrl/events/$eventId/join');

    await _waitForSession(maxMs: 5000);

    final res = await http
        .post(uri, headers: _headers(json: true), body: jsonEncode({}))
        .timeout(_timeout);

    if (res.statusCode != 200 && res.statusCode != 201) {
      _throwHttp('POST', uri, res);
    }

    return _decodeActionResult(res.body);
  }

  Future<EventActionResult> leaveEvent(String eventId) async {
    final uri = Uri.parse('$backendBaseUrl/events/$eventId/leave');

    await _waitForSession(maxMs: 5000);

    final res = await http
        .post(uri, headers: _headers(json: true), body: jsonEncode({}))
        .timeout(_timeout);

    if (res.statusCode != 200 && res.statusCode != 201) {
      _throwHttp('POST', uri, res);
    }

    return _decodeActionResult(res.body);
  }

  Future<EventActionResult> cancelEvent(String eventId) async {
    final uri = Uri.parse('$backendBaseUrl/events/$eventId/cancel');

    await _waitForSession(maxMs: 5000);

    final res = await http
        .post(uri, headers: _headers(json: true), body: jsonEncode({}))
        .timeout(_timeout);

    if (res.statusCode != 200 && res.statusCode != 201) {
      _throwHttp('POST', uri, res);
    }

    return _decodeActionResult(res.body);
  }

  // ---------------------------
  // Host approvals (requests)
  // ---------------------------

  Future<List<EventJoinRequest>> fetchEventRequests(String eventId) async {
    final uri = Uri.parse('$backendBaseUrl/events/$eventId/requests');

    await _waitForSession(maxMs: 5000);

    final res = await http.get(uri, headers: _headers()).timeout(_timeout);
    if (res.statusCode != 200) _throwHttp('GET', uri, res);

    final decoded = jsonDecode(res.body);
    if (decoded is List) {
      return decoded
          .map((e) => EventJoinRequest.fromJson(e as Map<String, dynamic>))
          .where((r) => r.userId.trim().isNotEmpty)
          .toList();
    }

    throw Exception('GET $uri returned unexpected shape: ${res.body}');
  }

  /// ✅ Matches your backend: POST /events/{eventId}/accept with body {user_id}
  Future<EventActionResult> acceptEventRequest({
    required String eventId,
    required String userId,
  }) async {
    final uri = Uri.parse('$backendBaseUrl/events/$eventId/accept');

    await _waitForSession(maxMs: 5000);

    final body = <String, dynamic>{
      'user_id': userId,
    };

    final res = await http
        .post(uri, headers: _headers(json: true), body: jsonEncode(body))
        .timeout(_timeout);

    if (res.statusCode != 200 && res.statusCode != 201) {
      _throwHttp('POST', uri, res);
    }

    return _decodeActionResult(res.body);
  }

  /// ✅ Matches your backend: POST /events/{eventId}/reject with body {user_id, cooldown_minutes}
  Future<EventActionResult> rejectEventRequest({
    required String eventId,
    required String userId,
    int cooldownMinutes = 10,
  }) async {
    final uri = Uri.parse('$backendBaseUrl/events/$eventId/reject');

    await _waitForSession(maxMs: 5000);

    final body = <String, dynamic>{
      'user_id': userId,
      'cooldown_minutes': cooldownMinutes,
    };

    final res = await http
        .post(uri, headers: _headers(json: true), body: jsonEncode(body))
        .timeout(_timeout);

    if (res.statusCode != 200 && res.statusCode != 201) {
      _throwHttp('POST', uri, res);
    }

    return _decodeActionResult(res.body);
  }
}
