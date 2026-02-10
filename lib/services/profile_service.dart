import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/public_profile.dart';

class ProfileService {
  /// ✅ PRODUCCIÓN
  static const String backendBaseUrl = 'https://tapin-backend.fly.dev';

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

  Future<PublicProfile> getProfile(String userId) async {
    final res = await http
        .get(
          Uri.parse('$backendBaseUrl/profiles/$userId'),
          headers: _headers(),
        )
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw Exception('Failed to load profile: ${res.body}');
    }

    return PublicProfile.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

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
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw Exception('Failed to update profile: ${res.body}');
    }
  }
}
