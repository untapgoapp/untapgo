class Event {
  final String id;
  final String title;

  final String? addressText;

  final double? lat;
  final double? lng;

  final String status;
  final DateTime startsAt;

  final int attendeesCount;
  final int maxPlayers;

  final String hostUserId;
  final String hostNickname;

  final bool isJoined;

  // ✅ Rules metadata
  // Source of truth = slug (ex: "modern")
  final String? formatSlug;

  // Display label (ex: "Modern")
  final String? format;

  final String? proxies;

  final String? powerLevel;
  final String? hostNotes;

  // Optional, only from /events/nearby
  final double? distanceKm;

  // Join / request state
  final String? myStatus; // pending | joined | rejected | kicked | etc
  final int? cooldownSeconds;

  // Host-only signal
  final int? pendingRequestsCount;

  Event({
    required this.id,
    required this.title,
    this.addressText,
    this.lat,
    this.lng,
    required this.status,
    required this.startsAt,
    required this.attendeesCount,
    required this.maxPlayers,
    required this.hostUserId,
    required this.hostNickname,
    required this.isJoined,
    this.formatSlug,
    this.format,
    this.proxies,
    this.powerLevel,
    this.hostNotes,
    this.distanceKm,
    this.myStatus,
    this.cooldownSeconds,
    this.pendingRequestsCount,
  });

  int get playerCount => attendeesCount;

  /// Host check helper
  bool isHostFor(String? currentUserId) {
    final me = (currentUserId ?? '').trim();
    if (me.isEmpty) return false;
    return hostUserId.trim() == me;
  }

  /// Canonical starts label
  static String formatStarts(DateTime startsAt) {
    if (startsAt.year <= 1971) return 'TBD';

    final local = startsAt.toLocal();
    final now = DateTime.now().toLocal();

    DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

    final today = dateOnly(now);
    final tomorrow = today.add(const Duration(days: 1));
    final eventDay = dateOnly(local);

    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final time = '$hh:$mm';

    if (eventDay == today) return 'Today $time';
    if (eventDay == tomorrow) return 'Tomorrow $time';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final month = months[local.month - 1];
    return '$month ${local.day} $time';
  }

  String startsLabel() => Event.formatStarts(startsAt);

  String get statusLabel {
    final s = status.trim();
    switch (s) {
      case 'Open':
      case 'Full':
      case 'Started':
      case 'Ended':
      case 'Cancelled':
        return s;
      default:
        return s.isEmpty ? 'Unknown' : s;
    }
  }

  // --------------------------
  // Format helpers
  // --------------------------

  static String? _cleanNullableString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    if (s.toLowerCase() == 'null') return null;
    return s;
  }

  static String? _slugToTitle(String? slug) {
    final s = (slug ?? '').trim().toLowerCase();
    if (s.isEmpty) return null;

    // Convert "pre-modern" variants just in case
    final normalized = s.replaceAll('_', '-').replaceAll(' ', '-');

    // Title-case words split by '-' (modern -> Modern, premodern -> Premodern)
    final parts = normalized.split('-').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;

    final titled = parts.map((p) {
      if (p.isEmpty) return p;
      return p[0].toUpperCase() + p.substring(1);
    }).join(' ');

    return titled;
  }

  factory Event.fromJson(Map<String, dynamic> json) {
    String s(dynamic v) => v == null ? '' : v.toString();
    int i(dynamic v) => v == null ? 0 : int.tryParse(v.toString()) ?? 0;
    bool b(dynamic v) => v == true || v == 'true' || v == 1 || v == '1';

    double? dd(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    DateTime d(dynamic v) {
      try {
        return DateTime.parse(v.toString());
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }

    final attendees =
        json.containsKey('joined_count') ? i(json['joined_count']) :
        json.containsKey('attendees_count') ? i(json['attendees_count']) :
        i(json['player_count']);

    final addressRaw = s(json['address_text']).trim();
    final addressText = addressRaw.isNotEmpty ? addressRaw : null;

    final notesRaw = s(json['host_notes']).trim();
    final hostNotes = notesRaw.isNotEmpty ? notesRaw : null;

    final plRaw = s(json['power_level']).trim();
    final powerLevel = plRaw.isNotEmpty ? plRaw : null;

    // ✅ FORMAT (new world order)
    final formatSlug = _cleanNullableString(
      json['format_slug'] ?? json['formatSlug'],
    );

    // Prefer explicit name if backend sends it
    final formatName = _cleanNullableString(
      json['format_name'] ??
          json['formatName'] ??
          json['format'] ??
          json['event_format'],
    );

    // Display label fallback: derive from slug
    final String? format = formatName ?? _slugToTitle(formatSlug);

    // PROXIES
    final proxiesRaw =
        json['proxies'] ??
        json['proxies_policy'] ??
        json['proxiesPolicy'] ??
        json['proxy_policy'] ??
        json['proxies_allowed'];

    String? proxies;
    if (proxiesRaw == null) {
      proxies = null;
    } else if (proxiesRaw is bool) {
      proxies = proxiesRaw ? 'Allowed' : 'Not allowed';
    } else {
      final px = proxiesRaw.toString().trim();
      proxies = px.isNotEmpty ? px : null;
    }

    final lat = dd(json['lat'] ?? json['latitude']);
    final lng = dd(json['lng'] ?? json['lon'] ?? json['longitude']);
    final distanceKm = dd(json['distance_km'] ?? json['distanceKm']);

    final myStatusRaw = json['my_status'] ?? json['myStatus'];
    final myStatus = myStatusRaw == null ? null : myStatusRaw.toString();

    int? cooldownSeconds;
    final cs = json['cooldown_seconds'] ?? json['cooldownSeconds'];
    if (cs is int) cooldownSeconds = cs;
    if (cs is num) cooldownSeconds = cs.toInt();
    if (cs is String) cooldownSeconds = int.tryParse(cs);

    final prcRaw =
        json['pending_requests_count'] ?? json['pendingRequestsCount'];
    final int? pendingRequestsCount =
        prcRaw == null ? null : int.tryParse(prcRaw.toString());

    final statusLower = (myStatus ?? '').trim().toLowerCase();
    final joinedDerived = statusLower == 'joined';

    return Event(
      id: s(json['id']),
      title: s(json['title']),
      addressText: addressText,
      lat: lat,
      lng: lng,
      status: s(json['status']),
      startsAt: d(json['starts_at']),
      attendeesCount: attendees,
      maxPlayers: i(json['max_players']),
      hostUserId: s(json['host_user_id']),
      hostNickname: s(json['host_nickname']),
      isJoined: myStatus != null ? joinedDerived : b(json['is_joined']),
      formatSlug: formatSlug,
      format: format,
      proxies: proxies,
      powerLevel: powerLevel,
      hostNotes: hostNotes,
      distanceKm: distanceKm,
      myStatus: myStatus,
      cooldownSeconds: cooldownSeconds,
      pendingRequestsCount: pendingRequestsCount,
    );
  }

  /// Needed for optimistic UI
  Event copyWith({
    String? title,
    String? addressText,
    double? lat,
    double? lng,
    String? status,
    DateTime? startsAt,
    int? attendeesCount,
    int? maxPlayers,
    String? hostUserId,
    String? hostNickname,
    bool? isJoined,

    String? formatSlug,
    String? format,
    String? proxies,

    String? powerLevel,
    String? hostNotes,
    double? distanceKm,
    String? myStatus,
    int? cooldownSeconds,
    int? pendingRequestsCount,
  }) {
    final nextMyStatus = myStatus ?? this.myStatus;
    final derivedJoined =
        (nextMyStatus ?? '').trim().toLowerCase() == 'joined';

    final nextIsJoined =
        isJoined ?? (nextMyStatus != null ? derivedJoined : this.isJoined);

    return Event(
      id: id,
      title: title ?? this.title,
      addressText: addressText ?? this.addressText,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      status: status ?? this.status,
      startsAt: startsAt ?? this.startsAt,
      attendeesCount: attendeesCount ?? this.attendeesCount,
      maxPlayers: maxPlayers ?? this.maxPlayers,
      hostUserId: hostUserId ?? this.hostUserId,
      hostNickname: hostNickname ?? this.hostNickname,
      isJoined: nextIsJoined,
      formatSlug: formatSlug ?? this.formatSlug,
      format: format ?? this.format,
      proxies: proxies ?? this.proxies,
      powerLevel: powerLevel ?? this.powerLevel,
      hostNotes: hostNotes ?? this.hostNotes,
      distanceKm: distanceKm ?? this.distanceKm,
      myStatus: nextMyStatus,
      cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
      pendingRequestsCount: pendingRequestsCount ?? this.pendingRequestsCount,
    );
  }
}