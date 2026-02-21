class Badge {
  final String code;
  final String name;
  final String icon;

  Badge({
    required this.code,
    required this.name,
    required this.icon,
  });

  factory Badge.fromJson(Map<String, dynamic> json) {
    return Badge(
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      icon: json['icon'] ?? '',
    );
  }
}