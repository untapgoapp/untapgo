import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/public_profile.dart';
import '../models/favorite_profile.dart';

class ProfileService {
  static const String backendBaseUrl = 'https://tapin-backend.fly.dev';
  static const Duration _timeout = Duration(seconds: 12);

  Map<String, String> _headers() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) {
      throw Exception('AUTH_REQUIRED');
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<void> reportUser({
    required String profileId,
    required String reason,
    String? details,
  }) async {
    final res = await http.post(
      Uri.parse('$backendBaseUrl/profiles/$profileId/report'),
      headers: _headers(),
      body: jsonEncode({
        "reason": reason,
        "details": details,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  // --------------------------------------------------
  // GET profile + decks
  // --------------------------------------------------

  Future<PublicProfile> getProfile(String userId) async {
    final profileRes = await http
        .get(
          Uri.parse('$backendBaseUrl/profiles/$userId'),
          headers: _headers(),
        )
        .timeout(_timeout);

    if (profileRes.statusCode != 200) {
      throw Exception(
        'GET /profiles/$userId failed: '
        '${profileRes.statusCode} ${profileRes.body}',
      );
    }

    final decksRes = await http
        .get(
          Uri.parse('$backendBaseUrl/profiles/$userId/decks'),
          headers: _headers(),
        )
        .timeout(_timeout);

    if (decksRes.statusCode != 200) {
      throw Exception(
        'GET /profiles/$userId/decks failed: '
        '${decksRes.statusCode} ${decksRes.body}',
      );
    }

    final profileJson =
        jsonDecode(profileRes.body) as Map<String, dynamic>;

    final decksJson =
        jsonDecode(decksRes.body) as Map<String, dynamic>;

    profileJson['decks'] = decksJson['decks'] ?? [];

    return PublicProfile.fromJson(profileJson);
  }

  // --------------------------------------------------
  // UPDATE my profile
  // --------------------------------------------------

  Future<void> updateMyProfile({
    required String nickname,
    String? avatarUrl,
    String? bio,
    String? mtgArenaUsername,
  }) async {
    final body = <String, dynamic>{
      'nickname': nickname.trim(),
      'avatar_url':
          (avatarUrl ?? '').trim().isEmpty ? null : avatarUrl!.trim(),
      'bio': (bio ?? '').trim().isEmpty ? null : bio!.trim(),
      'mtg_arena_username': (mtgArenaUsername ?? '').trim().isEmpty
          ? null
          : mtgArenaUsername!.trim(),
    };

    final res = await http
        .patch(
          Uri.parse('$backendBaseUrl/me/profile'),
          headers: _headers(),
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    if (res.statusCode != 200) {
      throw Exception(
        'PATCH /me/profile failed: '
        '${res.statusCode} ${res.body}',
      );
    }
  }

  // --------------------------------------------------
  // FAVORITES
  // --------------------------------------------------

  Future<List<FavoriteProfile>> fetchFavorites() async {
    final res = await http
        .get(
          Uri.parse('$backendBaseUrl/profiles/me/favorites'),
          headers: _headers(),
        )
        .timeout(_timeout);

    if (res.statusCode != 200) {
      throw Exception(
        'GET /profiles/me/favorites failed: '
        '${res.statusCode} ${res.body}',
      );
    }

    final List data = jsonDecode(res.body);
    return data
        .map((e) => FavoriteProfile.fromJson(e))
        .toList();
  }

  Future<bool> isFavorite(String profileId) async {
    final res = await http
        .get(
          Uri.parse('$backendBaseUrl/profiles/$profileId/is-favorite'),
          headers: _headers(),
        )
        .timeout(_timeout);

    if (res.statusCode != 200) {
      throw Exception(res.body);
    }

    final data = jsonDecode(res.body);
    return data['is_favorite'] == true;
  }

  Future<void> favorite(String profileId) async {
    final res = await http.post(
      Uri.parse('$backendBaseUrl/profiles/$profileId/favorite'),
      headers: _headers(),
    );

    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  Future<void> unfavorite(String profileId) async {
    final res = await http.delete(
      Uri.parse('$backendBaseUrl/profiles/$profileId/favorite'),
      headers: _headers(),
    );

    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  Future<void> clearFavorites() async {
    final res = await http.delete(
      Uri.parse('$backendBaseUrl/profiles/me/favorites'),
      headers: _headers(),
    );

    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  // --------------------------------------------------
  // BLOCKS
  // --------------------------------------------------

  Future<Map<String, bool>> getBlockStatus(String profileId) async {
    final res = await http
        .get(
          Uri.parse('$backendBaseUrl/profiles/$profileId/is-blocked'),
          headers: _headers(),
        )
        .timeout(_timeout);

    if (res.statusCode != 200) {
      throw Exception(res.body);
    }

    final data = jsonDecode(res.body);

    return {
      'blocked_by_me': data['blocked_by_me'] == true,
      'blocked_me': data['blocked_me'] == true,
    };
  }

  Future<void> blockUser(String profileId) async {
    final res = await http.post(
      Uri.parse('$backendBaseUrl/profiles/$profileId/block'),
      headers: _headers(),
    );

    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }

  Future<void> unblockUser(String profileId) async {
    final res = await http.delete(
      Uri.parse('$backendBaseUrl/profiles/$profileId/block'),
      headers: _headers(),
    );

    if (res.statusCode != 200) {
      throw Exception(res.body);
    }
  }
}