class FavoriteProfile {
  final String id;
  final String nickname;
  final String? avatarUrl;
  final int hostedCount;
  final int playedCount;

  FavoriteProfile({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    required this.hostedCount,
    required this.playedCount,
  });

  factory FavoriteProfile.fromJson(Map<String, dynamic> json) {
    return FavoriteProfile(
      id: json['id'],
      nickname: json['nickname'] ?? '',
      avatarUrl: json['avatar_url'],
      hostedCount: json['hosted_count'] ?? 0,
      playedCount: json['played_count'] ?? 0,
    );
  }
}