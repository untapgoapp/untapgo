import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/public_profile.dart';

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

  // --------------------------------------------------
  // GET profile + decks
  // --------------------------------------------------

  Future<PublicProfile> getProfile(String userId) async {
    // 1️⃣ Load profile
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

    // 2️⃣ Load public decks
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

    // Inject decks into profile payload
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
}
