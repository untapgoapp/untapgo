import 'deck.dart';

class PublicProfile {
  final String id;
  final String nickname;
  final String? avatarUrl;
  final String? bio;

  // MTG Arena username (optional)
  final String? mtgArenaUsername;

  final List<Deck> decks;

  PublicProfile({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    this.bio,
    this.mtgArenaUsername,
    required this.decks,
  });

  factory PublicProfile.fromJson(Map<String, dynamic> json) {
    String s(dynamic v) => v == null ? '' : v.toString();
    String? ss(dynamic v) {
      final t = v?.toString().trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    final rawDecks = json['decks'] as List<dynamic>? ?? [];

    return PublicProfile(
      id: s(json['id']),
      nickname: s(json['nickname']),
      avatarUrl: ss(json['avatar_url']),
      bio: ss(json['bio']),
      mtgArenaUsername: ss(json['mtg_arena_username']),
      decks: rawDecks
          .map((d) => Deck.fromJson(d as Map<String, dynamic>))
          .toList(),
    );
  }
}
