// lib/screens/profile_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/event_service.dart';
import '../services/profile_service.dart';
import 'edit_profile_screen.dart';
import 'my_decks_screen.dart';

class PublicProfile {
  final String id;
  final String nickname;
  final String? avatarUrl;
  final String? bio;
  final String? mtgArenaUsername;

  // ✅ NEW: stats
  final int hostedCount;
  final int playedCount;

  PublicProfile({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    this.bio,
    this.mtgArenaUsername,
    this.hostedCount = 0,
    this.playedCount = 0,
  });

  factory PublicProfile.fromJson(Map<String, dynamic> json) {
    String s(dynamic v) => v == null ? '' : v.toString();
    String? ss(dynamic v) {
      final t = s(v).trim();
      return t.isEmpty ? null : t;
    }

    int ii(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return PublicProfile(
      id: s(json['id'] ?? json['user_id']),
      nickname: s(json['nickname']),
      avatarUrl: ss(json['avatar_url']),
      bio: ss(json['bio']),
      mtgArenaUsername: ss(json['mtg_arena_username']),
      hostedCount: ii(json['hosted_count'] ?? json['hosted'] ?? json['hostedCount']),
      playedCount: ii(json['played_count'] ?? json['played'] ?? json['playedCount']),
    );
  }
}

class _PublicDeck {
  final String id;
  final String commanderName;
  final String? deckUrl;
  final String? formatSlug;

  // ✅ plain text export
  final String? exportText;

  final bool w, u, b, r, g, c;

  _PublicDeck({
    required this.id,
    required this.commanderName,
    required this.deckUrl,
    required this.formatSlug,
    required this.exportText,
    required this.w,
    required this.u,
    required this.b,
    required this.r,
    required this.g,
    required this.c,
  });

  factory _PublicDeck.fromJson(Map<String, dynamic> json) {
    bool bb(dynamic v) => v == true || v == 'true' || v == 1 || v == '1';
    String? ss(dynamic v) {
      final t = v?.toString().trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    return _PublicDeck(
      id: (json['id'] ?? '').toString(),
      commanderName: (json['commander_name'] ?? '').toString(),
      deckUrl: ss(json['deck_url']),
      formatSlug: ss(json['format_slug']),
      exportText: ss(json['export_text'] ?? json['deck_text']), // tolerate old key
      w: bb(json['color_white']),
      u: bb(json['color_blue']),
      b: bb(json['color_black']),
      r: bb(json['color_red']),
      g: bb(json['color_green']),
      c: bb(json['color_colorless']),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  final String userId;

  const ProfileScreen({
    super.key,
    required this.userId,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<PublicProfile>? _future;
  Future<List<_PublicDeck>>? _decksFuture;

  bool get _isMe {
    final me = Supabase.instance.client.auth.currentUser?.id;
    return me != null && me == widget.userId;
  }

  Map<String, String> _headers() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @override
  void initState() {
    super.initState();
    _future = _fetchProfile();
    _decksFuture = _fetchDecks();
  }

  // ---------------------------
  // Networking
  // ---------------------------

  Future<PublicProfile> _fetchProfile() async {
    final res = await http.get(
      Uri.parse('${EventService.backendBaseUrl}/profiles/${widget.userId}'),
      headers: _headers(),
    );

    if (res.statusCode != 200) {
      throw Exception(res.body);
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return PublicProfile.fromJson(data);
  }

  Future<List<_PublicDeck>> _fetchDecks() async {
    final res = await http.get(
      Uri.parse('${EventService.backendBaseUrl}/profiles/${widget.userId}/decks'),
      headers: _headers(),
    );

    if (res.statusCode != 200) {
      return const <_PublicDeck>[];
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map && decoded['decks'] is List) {
      final list = decoded['decks'] as List;

      final decks = list
          .whereType<Map<String, dynamic>>()
          .map((e) => _PublicDeck.fromJson(e))
          .toList();

      // ✅ cap in UI (and feels nicer)
      if (decks.length > 10) return decks.take(10).toList();
      return decks;
    }

    return const <_PublicDeck>[];
  }

  Future<void> _reload() async {
    setState(() {
      _future = _fetchProfile();
      _decksFuture = _fetchDecks();
    });
    await _future;
  }

  // ---------------------------
  // Actions
  // ---------------------------

  void _openAvatarPreview(ImageProvider image) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                color: Colors.black,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Image(image: image, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEdit(PublicProfile p) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return;

    final service = ProfileService();

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          service: service,
          initialNickname: p.nickname,
          initialAvatarUrl: p.avatarUrl,
          initialBio: p.bio,
          initialMtgArenaUsername: p.mtgArenaUsername,
        ),
      ),
    );

    if (changed == true) {
      await _reload();
    }
  }

  Future<void> _openMyDecks() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyDecksScreen()),
    );
    await _reload();
  }

  Future<void> _openDeckUrl(String url) async {
    final u = url.trim();
    if (u.isEmpty) return;

    final uri = Uri.tryParse(u);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid URL')),
      );
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }

  // ---------------------------
  // UI helpers
  // ---------------------------

  Widget _squircleAvatar({
    required ImageProvider? avatar,
    required VoidCallback? onTap,
    double size = 88,
  }) {
    final r = BorderRadius.circular(size * 0.28);

    return InkWell(
      borderRadius: r,
      onTap: onTap,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: r,
            child: Container(
              width: size,
              height: size,
              color: Colors.grey.shade200,
              child: avatar != null
                  ? Image(image: avatar, fit: BoxFit.cover)
                  : const Center(child: Icon(Icons.person, size: 42)),
            ),
          ),
          if (avatar != null)
            Positioned(
              bottom: 6,
              right: 6,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.zoom_in, size: 17, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statsRow(PublicProfile p) {
    Widget stat(String label, int value) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade600,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value.toString(),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          stat('Hosted', p.hostedCount),
          const SizedBox(width: 18),
          stat('Played', p.playedCount),
        ],
      ),
    );
  }

  String _formatLabel(String? slug) {
    final s = (slug ?? '').trim().toLowerCase();
    if (s.isEmpty) return 'Other';
    return s[0].toUpperCase() + s.substring(1);
  }

  Widget _deckColors(_PublicDeck d) {
    final letters = <String>[];
    if (d.w) letters.add('W');
    if (d.u) letters.add('U');
    if (d.b) letters.add('B');
    if (d.r) letters.add('R');
    if (d.g) letters.add('G');
    final showC = d.c || letters.isEmpty;

    return Wrap(
      spacing: 6,
      runSpacing: -10,
      children: [
        ...letters.map(
          (c) => Chip(
            label: Text(
              c,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                height: 1.0,
              ),
            ),
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        if (showC)
          const Chip(
            label: Text(
              'C',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                height: 1.0,
              ),
            ),
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
    );
  }

  Widget _deckCard(_PublicDeck d) {
    final name = d.commanderName.trim().isEmpty ? 'Unnamed deck' : d.commanderName.trim();
    final fmt = _formatLabel(d.formatSlug);
    final hasLink = (d.deckUrl ?? '').trim().isNotEmpty;

    final export = (d.exportText ?? '').trim();
    final hasExport = export.isNotEmpty;

    return ExpansionTile(
      initiallyExpanded: false,
      tilePadding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Chip(
            label: Text(
              fmt,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 11,
                height: 1.0,
              ),
            ),
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Expanded(child: _deckColors(d)),
            if (hasLink) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _openDeckUrl(d.deckUrl!),
                icon: const Icon(Icons.link, size: 14),
                label: const Text(
                  'Open',
                  style: TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ],
        ),
      ),
      trailing: hasExport ? const Icon(Icons.expand_more, size: 20) : const SizedBox(width: 20),
      children: [
        if (hasExport) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black12),
            ),
            child: SelectableText(
              export,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.25,
              ),
            ),
          ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _isMe ? 'No export text yet.' : 'No export text.',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _decksSection() {
    return FutureBuilder<List<_PublicDeck>>(
      future: _decksFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final decks = snap.data ?? const <_PublicDeck>[];

        // ✅ less bulky: no Card wrapper, just a subtle container
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black12),
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withOpacity(0.55),
          ),
          child: ExpansionTile(
            initiallyExpanded: false,
            tilePadding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            title: Row(
              children: [
                Text(
                  'Decks',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const Spacer(),
                if (_isMe)
                  TextButton.icon(
                    onPressed: _openMyDecks,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Manage'),
                  ),
              ],
            ),
            children: [
              if (decks.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_isMe ? 'No decks yet.' : 'No decks.'),
                )
              else
                ...decks.map(_deckCard).toList(),
              if (decks.length >= 10)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Showing latest 10 decks',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------
  // Build
  // ---------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<PublicProfile>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snap.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 120),
                  Center(child: Text('Error: ${snap.error}')),
                ],
              );
            }

            final p = snap.data!;
            final bio = (p.bio ?? '').trim();
            final arena = (p.mtgArenaUsername ?? '').trim();

            final hasAvatar = (p.avatarUrl ?? '').trim().isNotEmpty;
            final ImageProvider? avatar = hasAvatar ? NetworkImage(p.avatarUrl!) : null;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                // Header "lighter": soft container, less padding, smaller avatar
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white.withOpacity(0.55),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _squircleAvatar(
                        avatar: avatar,
                        onTap: avatar == null ? null : () => _openAvatarPreview(avatar),
                        size: 88,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.nickname.isNotEmpty ? p.nickname : 'Player',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            if (arena.isNotEmpty) ...[
                              Chip(
                                avatar: const Icon(Icons.videogame_asset_outlined, size: 18),
                                label: Text('Arena: $arena'),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(height: 6),
                            ],
                            if (bio.isNotEmpty)
                              Text(
                                bio,
                                style: TextStyle(
                                  color: Colors.grey.shade800,
                                  height: 1.25,
                                ),
                              ),
                            // ✅ hosted/played
                            _statsRow(p),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                if (_isMe) ...[
                  FilledButton.icon(
                    onPressed: () => _openEdit(p),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit profile'),
                  ),
                  const SizedBox(height: 12),
                ],

                // ✅ Decks collapsible section + per-deck export collapsible
                _decksSection(),
              ],
            );
          },
        ),
      ),
    );
  }
}
