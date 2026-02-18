class Deck {
  final String id;
  final String commanderName;
  final String? deckUrl;

  final String? formatSlug;     // ✅ NEW
  final String? exportText;     // ✅ NEW

  final bool colorWhite;
  final bool colorBlue;
  final bool colorBlack;
  final bool colorRed;
  final bool colorGreen;
  final bool colorColorless;

  final DateTime createdAt;

  Deck({
    required this.id,
    required this.commanderName,
    this.deckUrl,
    this.formatSlug,
    this.exportText,
    required this.colorWhite,
    required this.colorBlue,
    required this.colorBlack,
    required this.colorRed,
    required this.colorGreen,
    required this.colorColorless,
    required this.createdAt,
  });

  factory Deck.fromJson(Map<String, dynamic> json) {
    String s(dynamic v) => v == null ? '' : v.toString();
    String? ss(dynamic v) {
      final t = v?.toString().trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    bool b(dynamic v) => v == true || v == 'true' || v == 1 || v == '1';

    DateTime d(dynamic v) {
      if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
      try {
        return DateTime.parse(v.toString());
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }

    // Preferimos color_identity si viene del backend
    final ci = s(json['color_identity']).trim();

    final bool white = ci.isNotEmpty ? ci.contains('W') : b(json['color_white']);
    final bool blue  = ci.isNotEmpty ? ci.contains('U') : b(json['color_blue']);
    final bool black = ci.isNotEmpty ? ci.contains('B') : b(json['color_black']);
    final bool red   = ci.isNotEmpty ? ci.contains('R') : b(json['color_red']);
    final bool green = ci.isNotEmpty ? ci.contains('G') : b(json['color_green']);

    // Colorless: explícito o fallback si no hay ningún color
    final bool colorlessFromCi = ci.isNotEmpty && ci.contains('C');
    final bool colorlessFromDb = b(json['color_colorless']);

    return Deck(
      id: s(json['id']),
      commanderName: s(json['commander_name']),
      deckUrl: ss(json['deck_url']),
      formatSlug: ss(json['format_slug']),      // ✅ NEW
      exportText: ss(json['export_text']),      // ✅ NEW
      colorWhite: white,
      colorBlue: blue,
      colorBlack: black,
      colorRed: red,
      colorGreen: green,
      colorColorless: colorlessFromCi ||
          colorlessFromDb ||
          (ci.isEmpty && !white && !blue && !black && !red && !green),
      createdAt: d(json['created_at']),
    );
  }

  /// UX rule:
  /// - No colors marked → Colorless (C)
  String get colorIdentity {
    final parts = <String>[];
    if (colorWhite) parts.add('W');
    if (colorBlue) parts.add('U');
    if (colorBlack) parts.add('B');
    if (colorRed) parts.add('R');
    if (colorGreen) parts.add('G');
    if (colorColorless || parts.isEmpty) parts.add('C');
    return parts.join();
  }

String get displayName =>
    commanderName.isNotEmpty ? commanderName : 'Unnamed deck';


  Deck copyWith({
    String? commanderName,
    String? deckUrl,
    String? formatSlug,
    String? exportText,
    bool? colorWhite,
    bool? colorBlue,
    bool? colorBlack,
    bool? colorRed,
    bool? colorGreen,
    bool? colorColorless,
  }) {
    return Deck(
      id: id,
      commanderName: commanderName ?? this.commanderName,
      deckUrl: deckUrl ?? this.deckUrl,
      formatSlug: formatSlug ?? this.formatSlug,
      exportText: exportText ?? this.exportText,
      colorWhite: colorWhite ?? this.colorWhite,
      colorBlue: colorBlue ?? this.colorBlue,
      colorBlack: colorBlack ?? this.colorBlack,
      colorRed: colorRed ?? this.colorRed,
      colorGreen: colorGreen ?? this.colorGreen,
      colorColorless: colorColorless ?? this.colorColorless,
      createdAt: createdAt,
    );
  }
}
