// lib/screens/profile_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/event_service.dart';
import '../services/profile_service.dart';
import 'edit_profile_screen.dart';
import 'edit_deck_screen.dart';
import '../widgets/badge_widget.dart';
import '../models/badge.dart';
import '../models/public_profile.dart';


class _PublicDeck {
  final String id;
  final String commanderName;
  final String? deckUrl;
  final String? formatSlug;
  final String? exportText;
  final String? imageUrl;
  final bool w, u, b, r, g, c;

  _PublicDeck({
    required this.id,
    required this.commanderName,
    required this.deckUrl,
    required this.formatSlug,
    required this.exportText,
    required this.imageUrl,
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
      exportText: ss(json['export_text']),
      imageUrl: ss(json['image_url']),
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

  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<PublicProfile>? _future;
  Future<List<_PublicDeck>>? _decksFuture;

  final Map<String, String?> _imageCache = {};
  static const String _cardBack =
      'https://cards.scryfall.io/card-back.jpg';

  bool get _isMe {
    final me = Supabase.instance.client.auth.currentUser?.id;
    return me != null && me == widget.userId;
  }

  @override
  void initState() {
    super.initState();
    _future = _fetchProfile();
    _decksFuture = _fetchDecks();
  }

  Map<String, String> _headers() {
    final token =
        Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<PublicProfile> _fetchProfile() async {
    final res = await http.get(
      Uri.parse('${EventService.backendBaseUrl}/profiles/${widget.userId}'),
      headers: _headers(),
    );

    if (res.statusCode != 200) throw Exception(res.body);
    return PublicProfile.fromJson(jsonDecode(res.body));
  }

  Future<List<_PublicDeck>> _fetchDecks() async {
    final res = await http.get(
      Uri.parse(
          '${EventService.backendBaseUrl}/profiles/${widget.userId}/decks'),
      headers: _headers(),
    );

    if (res.statusCode != 200) return [];

    final decoded = jsonDecode(res.body);
    if (decoded is Map && decoded['decks'] is List) {
      return (decoded['decks'] as List)
          .whereType<Map<String, dynamic>>()
          .map((e) => _PublicDeck.fromJson(e))
          .take(10)
          .toList();
    }

    return [];
  }

  Future<void> _reload() async {
    setState(() {
      _future = _fetchProfile();
      _decksFuture = _fetchDecks();
    });
    await _future;
  }

  Future<void> _deleteDeck(String id) async {
    final token =
        Supabase.instance.client.auth.currentSession?.accessToken;

    await http.delete(
      Uri.parse('${EventService.backendBaseUrl}/me/decks/$id'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
  }

  Future<void> _openDeckUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https'))) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }


  Widget _imageBox(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 90,
        height: 70,
        color: Colors.grey.shade200,
        child: Image.network(url, fit: BoxFit.cover),
      ),
    );
  }

  Widget _deckImage(_PublicDeck d, String name) {
    final imageUrl = (d.imageUrl ?? '').trim();

    return _imageBox(
      imageUrl.startsWith('http') ? imageUrl : _cardBack,
    );
  }

  Widget _deckColors(_PublicDeck d) {
    final letters = <String>[];
    if (d.w) letters.add('W');
    if (d.u) letters.add('U');
    if (d.b) letters.add('B');
    if (d.r) letters.add('R');
    if (d.g) letters.add('G');
    if (d.c || letters.isEmpty) letters.add('C');

    return Wrap(
      spacing: 6,
      children: letters
          .map((c) => SvgPicture.asset(
                'assets/mana/${c.toLowerCase()}.svg',
                width: 18,
                height: 18,
              ))
          .toList(),
    );
  }

  Widget _deckTile(_PublicDeck d) {
    final name = d.commanderName.trim().isEmpty
        ? 'Unnamed deck'
        : d.commanderName.trim();

    return Dismissible(
      key: ValueKey(d.id),
      direction:
          _isMe ? DismissDirection.horizontal : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: Colors.blueGrey,
        child: const Icon(Icons.edit, color: Colors.white),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (!_isMe) return false;

        if (direction == DismissDirection.startToEnd) {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Edit deck?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Edit'),
                ),
              ],
            ),
          );

          if (confirm == true) {
            final changed = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => EditDeckScreen(
                  deckId: d.id,
                  initialCommanderName: d.commanderName,
                  initialDeckUrl: d.deckUrl,
                  initialFormatSlug: d.formatSlug,
                  initialExportText: d.exportText,
                  initialW: d.w,
                  initialU: d.u,
                  initialB: d.b,
                  initialR: d.r,
                  initialG: d.g,
                  initialC: d.c,
                ),
              ),
            );

            if (changed == true) await _reload();
          }

          return false;
        }

        if (direction == DismissDirection.endToStart) {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Delete deck?'),
              content: const Text('This cannot be undone.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );

          if (confirm == true) {
            await _deleteDeck(d.id);
            await _reload();
            return true;
          }
        }

        return false;
      },
      child: ExpansionTile(
        tilePadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Row(
          children: [
            _deckImage(d, name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),

                  if ((d.formatSlug ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      d.formatSlug![0].toUpperCase() +
                        d.formatSlug!.substring(1),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],

                  const SizedBox(height: 4),
                  _deckColors(d),
                ],
              ),
            ),
          ],
        ),
        children: [
          if ((d.deckUrl ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => _openDeckUrl(d.deckUrl!),
                child: Text(
                  'Open deck link',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          if ((d.exportText ?? '').isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                d.exportText!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _decksSection() {
    return FutureBuilder<List<_PublicDeck>>(
      future: _decksFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Failed to load decks'),
          );
        }

        final decks = snap.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text(
                    'Decks',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16),
                  ),
                  const Spacer(),
                  if (_isMe)
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.add, size: 20),
                        onPressed: () async {
                          final changed =
                              await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const EditDeckScreen(),
                            ),
                          );

                          if (changed == true) await _reload();
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (decks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Text('No decks yet.'),
              )
            else
              ...decks.map(_deckTile).toList(),
          ],
        );
      },
    );
  }

  Widget _avatar(ImageProvider? avatar) {
    final r = BorderRadius.circular(24);
    return ClipRRect(
      borderRadius: r,
      child: Container(
        width: 88,
        height: 88,
        color: Colors.grey.shade200,
        child: avatar != null
            ? Image(image: avatar, fit: BoxFit.cover)
            : const Icon(Icons.person, size: 42),
      ),
    );
  }

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

            if (snap.hasError || snap.data == null) {
              return const Center(child: Text('Failed to load profile'));
            }

            final p = snap.data!;
            

            final avatar = (p.avatarUrl ?? '').isNotEmpty
                ? NetworkImage(p.avatarUrl!)
                : null;

            return ListView(
              padding:
                  const EdgeInsets.symmetric(vertical: 20),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16),
                  child: Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      _avatar(avatar),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    p.nickname.isNotEmpty
                                        ? p.nickname
                                        : 'Player',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                            fontWeight:
                                                FontWeight.w700),
                                  ),
                                ),
                                if (_isMe)
                                  GestureDetector(
                                    onTap: () =>
                                        _openEdit(p),
                                    child: Text(
                                      'Edit',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight:
                                            FontWeight.w500,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),

                            // 🔹 Badge (si tiene)
                            if (p.badges.isNotEmpty) ...[
                              Wrap(
                                spacing: 6,
                                children: p.badges.map((badge) {
                                  return BadgeWidget(
                                    icon: badge.icon,
                                    size: 18
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 8),
                              ],

                              // 🔹 Arena tag
                              if ((p.mtgArenaUsername ?? '').isNotEmpty)
                                Text(
                                  'Arena · ${p.mtgArenaUsername}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFDB5C42),
                                  )
                                ),

                              // 🔹 Bio
                              if ((p.bio ?? '').isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Text(
                                  p.bio!,
                                  style: const TextStyle(height: 1.3),
                                ),
                              ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                _decksSection(),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openEdit(PublicProfile p) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          service: ProfileService(),
          initialNickname: p.nickname,
          initialAvatarUrl: p.avatarUrl,
          initialBio: p.bio,
          initialMtgArenaUsername: p.mtgArenaUsername,
        ),
      ),
    );

    if (changed == true) await _reload();
  }
}
