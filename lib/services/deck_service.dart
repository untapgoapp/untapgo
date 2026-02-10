import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/deck.dart';

class DeckService {
  static const String backendBaseUrl = 'https://tapin-backend.fly.dev';
  static const Duration _timeout = Duration(seconds: 12);

  Map<String, String> _headers({bool json = false}) {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) {
      throw Exception('AUTH_REQUIRED');
    }

    return <String, String>{
      if (json) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<List<Deck>> fetchMyDecks({String? formatSlug}) async {
    final base = Uri.parse('$backendBaseUrl/me/decks');
    final uri = (formatSlug == null || formatSlug.trim().isEmpty)
        ? base
        : base.replace(
            queryParameters: {'format_slug': formatSlug.trim()},
          );

    final res =
        await http.get(uri, headers: _headers()).timeout(_timeout);

    if (res.statusCode != 200) {
      throw Exception('GET $uri failed: ${res.statusCode} ${res.body}');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map && decoded['decks'] is List) {
      final list = decoded['decks'] as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map((e) => Deck.fromJson(e))
          .toList();
    }

    throw Exception('GET $uri returned unexpected shape: ${res.body}');
  }

  Future<Deck> updateDeck({
    required String deckId,
    String? commanderName,
    String? deckUrl,
    String? formatSlug,
    String? exportText,
  }) async {
    final uri = Uri.parse('$backendBaseUrl/me/decks/$deckId');

    final patch = <String, dynamic>{
      if (commanderName != null)
        'commander_name':
            commanderName.trim().isEmpty ? null : commanderName.trim(),
      if (deckUrl != null)
        'deck_url': deckUrl.trim().isEmpty ? null : deckUrl.trim(),
      if (formatSlug != null)
        'format_slug':
            formatSlug.trim().isEmpty ? null : formatSlug.trim(),
      if (exportText != null)
        'export_text':
            exportText.trim().isEmpty ? null : exportText.trim(),
    };

    final res = await http
        .patch(
          uri,
          headers: _headers(json: true),
          body: jsonEncode(patch),
        )
        .timeout(_timeout);

    if (res.statusCode != 200) {
      throw Exception('PATCH $uri failed: ${res.statusCode} ${res.body}');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) {
      return Deck.fromJson(decoded);
    }

    throw Exception('PATCH $uri returned unexpected shape: ${res.body}');
  }
}
