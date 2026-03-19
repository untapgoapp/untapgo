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

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  Future<PublicProfile>? _future;
  Future<List<_PublicDeck>>? _decksFuture;

  final Map<String, String?> _imageCache = {};
  static const String _cardBack =
      'https://cards.scryfall.io/card-back.jpg';

  bool get _isMe {
    final me = Supabase.instance.client.auth.currentUser?.id;
    return me != null && me == widget.userId;
  }

  bool _isFavorite = false;
  bool _favoriteLoading = false;

  bool _blockedByMe = false;
  bool _blockLoading = false;

  late final AnimationController _heartController;
  late final Animation<double> _heartScale;
  late final Animation<double> _heartRotation;

  @override
  void initState() {
    super.initState();
    _future = _fetchProfile();
    _decksFuture = _fetchDecks();
    _loadFavoriteStatus();
    _loadBlockStatus();
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _heartScale = Tween<double>(begin: 1, end: 1.3).animate(
      CurvedAnimation(
        parent: _heartController,
        curve: Curves.easeOutBack,
      ),
    );

    _heartRotation = Tween<double>(begin: 0, end: 0.2).animate(
      CurvedAnimation(
        parent: _heartController,
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
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

  Future<void> _loadFavoriteStatus() async {
    if (_isMe) return;

    try {
      final result =
        await ProfileService().isFavorite(widget.userId);

      if (!mounted) return;

      setState(() {
        _isFavorite = result;
      });
    } catch (_) {
    // silencioso
    }
  }

  Future<void> _loadBlockStatus() async {
    if (_isMe) return;

    try {
      final result =
        await ProfileService().getBlockStatus(widget.userId);

      if (!mounted) return;

      setState(() {
        _blockedByMe = result['blocked_by_me'] == true;
      });
    } catch (_) {
      // silencioso
    }
  }

  Future<void> _confirmBlock() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Block user?'),
        content: const Text(
          'You won’t see their events or profile anymore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Block',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _blockLoading = true);

      try {
        await ProfileService().blockUser(widget.userId);

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User blocked')),
        );

        Navigator.pop(context); // salir del perfil
      } catch (_) {
        // opcional snackbar error
      } finally {
        if (mounted) {
          setState(() => _blockLoading = false);
        }
      }
    }
  }

  Future<void> _unblock() async {
    setState(() => _blockLoading = true);

    try {
      await ProfileService().unblockUser(widget.userId);

      if (!mounted) return;

      setState(() {
        _blockedByMe = false;
    });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User unblocked')),
      );
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _blockLoading = false);
      }
    }
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
        width: 72,
        height: 56,
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
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          childrenPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),

          title: Row(
            children: [
              _deckImage(d, name),
              const SizedBox(width: 14), // 👈 micro-fix que mejora todo

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
                        fontSize: 14,
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
                padding: const EdgeInsets.only(bottom: 10),
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
            Builder(
              builder: (_) {
                final raw = d.exportText!;

                final parts = raw.split('Sideboard');

                final mainDeck = parts[0]
                  .replaceFirst('Deck', '')
                  .trim();
                final sideboard =
                    parts.length > 1 ? parts[1].trim() : null;

                return Container(
                  margin: const EdgeInsets.only(top: 6),
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 🔹 Deck title
                      const Text(
                        'Deck',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: Colors.black38,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),

                      SelectableText(
                        mainDeck,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: Colors.black87,
                        ),
                      ),

                      if (sideboard != null) ...[
                        const SizedBox(height: 14),

                        const Text(
                          'Sideboard',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Colors.black38,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),

                        SelectableText(
                          sideboard,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
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
            const SizedBox(height: 8),

            // 🔹 Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Decks',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),

                  const Spacer(),

                  if (_isMe)
                    Container(
                      height: 30,
                      width: 30,
                      decoration: const BoxDecoration(
                        color: Color(0xFF6E5AA7),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(
                          Icons.add,
                          size: 18,
                          color: Colors.white,
                        ),
                        onPressed: () async {
                          final changed = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const EditDeckScreen(),
                            ),
                          );

                          if (changed == true) await _reload();
                        },
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 14), // 👈 más aire real

            if (decks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'No decks yet.',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            else
              ...decks.map((d) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: _deckTile(d),
                  )),
          ],
        );
      },
    );
  }

  Widget _avatarLarge(ImageProvider? avatar) {
    return Container(
      width: 132,
      height: 132,
      child: ClipOval(
        child: avatar != null
            ? Image(image: avatar, fit: BoxFit.cover)
            : const Icon(Icons.person, size: 60),
      ),
    );
  }

  Widget _profileHeader(PublicProfile p, ImageProvider? avatar) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        children: [
          // Avatar con halo sutil
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6E5AA7).withOpacity(0.15),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: _avatarLarge(avatar),
          ),

          const SizedBox(height: 14),

          // Nickname con accent
          Text(
            p.nickname.isNotEmpty ? p.nickname : 'Player',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6E5AA7), // 👈 clave
            ),
          ),

          const SizedBox(height: 6),

          if ((p.mtgArenaUsername ?? '').isNotEmpty)
            Text(
              'Arena · ${p.mtgArenaUsername}',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black54,
              ),
            ),

          if ((p.bio ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              p.bio!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                height: 1.4,
                color: Colors.black87,
              ),
            ),
          ],

          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _statBoxMinimal('Hosted', p.hostedCount ?? 0),
              const SizedBox(width: 40),
              _statBoxMinimal('Played', p.playedCount ?? 0),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBoxMinimal(String label, int value) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black45,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF7F1),
      appBar: null,
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

           return Container(
            color: const Color(0xFFFBF7F1),
            child: CustomScrollView(
              slivers: [

              // 🔹 Barra superior custom (sin AppBar)
              SliverToBoxAdapter(
                child: SafeArea(
                  top: true,
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.pop(context),
                        ),

                        const Spacer(),

                        if (_isMe)
                          GestureDetector(
                            onTap: () => _openEdit(p),
                            child: const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Text(
                                'Edit',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF6E5AA7),
                                ),
                              ),
                            ),
                          ),

                        if (!_isMe)
                          AnimatedBuilder(
                            animation: _heartController,
                            builder: (context, child) {
                              return Transform.rotate(
                                angle: _heartRotation.value,
                                child: Transform.scale(
                                  scale: _heartScale.value,
                                  child: IconButton(
                                    icon: Icon(
                                      _isFavorite
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: _isFavorite
                                          ? const Color(0xFF6E5AA7)
                                          : Colors.grey.shade600,
                                    ),
                                    onPressed: _favoriteLoading
                                        ? null
                                        : () async {
                                            setState(() {
                                              _isFavorite = !_isFavorite;
                                            });

                                            _heartController.forward().then(
                                              (_) => _heartController.reverse(),
                                            );

                                            final service = ProfileService();

                                            if (_isFavorite) {
                                              await service.favorite(widget.userId);
                                            } else {
                                              await service.unfavorite(widget.userId);
                                            }
                                          },
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),

            // 🔹 Header
              SliverToBoxAdapter(
                child: _profileHeader(p, avatar),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: 24),
              ),

              // 🔹 Decks
              SliverToBoxAdapter(
                child: _decksSection(),
              ),

              if (!_isMe) ...[
                const SliverToBoxAdapter(
                  child: SizedBox(height: 32),
                ),

                
                  const Divider(
                    height: 1,
                    thickness: 0.5,
                    color: Colors.black12,
                  ),

                SliverToBoxAdapter(
                  child: ListTile(
                    tileColor: Colors.transparent,
                    leading: const Icon(Icons.flag_outlined),
                    title: const Text('Report user'),
                    onTap: _openReportSheet,
                  ),
                ),

                if (!_blockedByMe)
                  SliverToBoxAdapter(
                    child: ListTile(
                      tileColor: Colors.transparent,
                      leading: const Icon(Icons.block, color: Colors.red),
                      title: const Text(
                        'Block user',
                        style: TextStyle(color: Colors.red),
                      ),
                      onTap: _blockLoading ? null : _confirmBlock,
                    ),
                  ),

                if (_blockedByMe)
                  SliverToBoxAdapter(
                    child: ListTile(
                      tileColor: Colors.transparent,
                      leading: const Icon(Icons.lock_open),
                      title: const Text('Unblock user'),
                      onTap: _blockLoading ? null : _unblock,
                    ),
                  ),
                ],
              ]
            ),
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
  Future<void> _openReportSheet() async {
    final controller = TextEditingController();
    String selectedReason = 'Inappropriate behavior';

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Report user',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedReason,
                items: const [
                  DropdownMenuItem(
                    value: 'Inappropriate behavior',
                    child: Text('Inappropriate behavior'),
                  ),
                  DropdownMenuItem(
                    value: 'Harassment',
                    child: Text('Harassment'),
                  ),
                  DropdownMenuItem(
                    value: 'Spam',
                    child: Text('Spam'),
                  ),
                  DropdownMenuItem(
                    value: 'Other',
                    child: Text('Other'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) selectedReason = v;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Optional details',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Submit report'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true) {
      await ProfileService().reportUser(
        profileId: widget.userId,
        reason: selectedReason,
        details: controller.text,
      );
    }
  }
}