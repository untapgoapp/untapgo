import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'edit_deck_screen.dart';

class MyDecksScreen extends StatelessWidget {
  const MyDecksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My decks')),
      body: const MyDecksBody(),
    );
  }
}

class MyDecksBody extends StatefulWidget {
  const MyDecksBody({super.key});

  @override
  State<MyDecksBody> createState() => _MyDecksBodyState();
}

class _MyDecksBodyState extends State<MyDecksBody> {
  static const String _backendBaseUrl = 'https://tapin-backend.fly.dev';

  String _formatFilter = '';
  late Future<List<_Deck>> _future;

  static const List<Map<String, String>> _formatOptions = [
    {'slug': '', 'label': 'All'},
    {'slug': 'commander', 'label': 'Commander'},
    {'slug': 'modern', 'label': 'Modern'},
    {'slug': 'pioneer', 'label': 'Pioneer'},
    {'slug': 'standard', 'label': 'Standard'},
    {'slug': 'legacy', 'label': 'Legacy'},
    {'slug': 'vintage', 'label': 'Vintage'},
    {'slug': 'pauper', 'label': 'Pauper'},
    {'slug': 'sealed', 'label': 'Sealed'},
    {'slug': 'draft', 'label': 'Draft'},
    {'slug': 'cube', 'label': 'Cube'},
    {'slug': 'other', 'label': 'Other'},
  ];

  @override
  void initState() {
    super.initState();
    _future = _fetchMyDecks();
  }

  Future<void> _reload() async {
    setState(() {
      _future = _fetchMyDecks();
    });
    await _future;
  }

  Uri _decksUri() {
    final base = Uri.parse('$_backendBaseUrl/me/decks');
    final slug = _formatFilter.trim();
    if (slug.isEmpty) return base;
    return base.replace(queryParameters: {'format_slug': slug});
  }

  Future<void> _waitForSession({int maxMs = 5000}) async {
    final tries = (maxMs / 100).round();
    for (var i = 0; i < tries; i++) {
      if (Supabase.instance.client.auth.currentSession?.accessToken != null) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<List<_Deck>> _fetchMyDecks() async {
    await _waitForSession();

    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    final res = await http.get(
      _decksUri(),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (res.statusCode != 200) {
      throw Exception(res.body);
    }

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final List decks = decoded['decks'] ?? [];
    return decks.map((e) => _Deck.fromJson(e)).toList();
  }

  Future<void> _openAddDeck() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const EditDeckScreen()),
    );

    if (changed == true && mounted) {
      await _reload();
    }
  }

  Future<void> _openEditDeck(_Deck d) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditDeckScreen(
          deckId: d.id,
          initialCommanderName: d.commanderName,
          initialDeckUrl: d.deckUrl,
          initialW: d.w,
          initialU: d.u,
          initialB: d.b,
          initialR: d.r,
          initialG: d.g,
        ),
      ),
    );

    if (changed == true && mounted) {
      await _reload();
    }
  }

  Future<void> _deleteDeck(_Deck d) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return;

    final res = await http.delete(
      Uri.parse('$_backendBaseUrl/me/decks/${d.id}'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception(res.body);
    }
  }

  Future<bool> _confirmDelete(_Deck d) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete deck'),
            content: Text(
              'Delete "${d.commanderName.isNotEmpty ? d.commanderName : 'this deck'}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _openDeckUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _formatLabel(String? slug) {
    final s = (slug ?? '').trim().toLowerCase();
    if (s.isEmpty) return 'Other';
    for (final o in _formatOptions) {
      if (o['slug'] == s) return o['label'] ?? s;
    }
    return s;
  }

  Widget _swipeEditBackground() {
    return Container(
      color: Colors.blue.shade600,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: const Row(
        children: [
          Icon(Icons.edit, color: Colors.white),
          SizedBox(width: 8),
          Text('Edit',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _swipeDeleteBackground() {
    return Container(
      color: Colors.red.shade600,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('Delete',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          SizedBox(width: 8),
          Icon(Icons.delete, color: Colors.white),
        ],
      ),
    );
  }

  Widget _colorChips(_Deck d) {
    final letters = <String>[
      if (d.w) 'W',
      if (d.u) 'U',
      if (d.b) 'B',
      if (d.r) 'R',
      if (d.g) 'G',
      if (d.c) 'C',
    ];

    return Wrap(
      spacing: 6,
      runSpacing: -8,
      children: letters
          .map(
            (c) => Chip(
              label: Text(
                c,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12, height: 1),
              ),
              visualDensity:
                  const VisualDensity(horizontal: -4, vertical: -4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          )
          .toList(),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Decks',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _openAddDeck,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Format:'),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _formatFilter,
                  items: _formatOptions
                      .map(
                        (o) => DropdownMenuItem<String>(
                          value: o['slug']!,
                          child: Text(o['label']!),
                        ),
                      )
                      .toList(),
                  onChanged: (v) async {
                    setState(() => _formatFilter = v ?? '');
                    await _reload();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_Deck>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final decks = snapshot.data!;

        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: decks.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == 0) return _header();

              final d = decks[i - 1];
              final hasLink = (d.deckUrl ?? '').isNotEmpty;
              final fmt = _formatLabel(d.formatSlug);

              return Dismissible(
                key: ValueKey(d.id),
                background: _swipeEditBackground(),
                secondaryBackground: _swipeDeleteBackground(),
                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.startToEnd) {
                    _openEditDeck(d);
                    return false;
                  }
                  if (direction == DismissDirection.endToStart) {
                    return await _confirmDelete(d);
                  }
                  return false;
                },
                onDismissed: (_) async {
                  await _deleteDeck(d);
                  await _reload();
                },
                child: ListTile(
                  dense: true,
                  title: Text(
                    d.commanderName.isNotEmpty
                        ? d.commanderName
                        : 'Unnamed deck',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: -8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(
                          label: Text(
                            fmt,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                                height: 1),
                          ),
                          visualDensity: const VisualDensity(
                              horizontal: -4, vertical: -4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        _colorChips(d),
                      ],
                    ),
                  ),
                  trailing: hasLink
                      ? IconButton(
                          icon: const Icon(Icons.link, size: 18),
                          visualDensity: const VisualDensity(
                              horizontal: -4, vertical: -4),
                          onPressed: () => _openDeckUrl(d.deckUrl!),
                        )
                      : null,
                  onTap: () => _openEditDeck(d),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _Deck {
  final String id;
  final String commanderName;
  final String? deckUrl;
  final String? formatSlug;
  final String? exportText;
  final bool w, u, b, r, g, c;

  _Deck({
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

  factory _Deck.fromJson(Map<String, dynamic> json) {
    bool bb(dynamic v) => v == true || v == 1 || v == '1';

    return _Deck(
      id: json['id'].toString(),
      commanderName: (json['commander_name'] ?? '').toString(),
      deckUrl: json['deck_url']?.toString(),
      formatSlug: json['format_slug']?.toString(),
      exportText: json['export_text']?.toString(),
      w: bb(json['color_white']),
      u: bb(json['color_blue']),
      b: bb(json['color_black']),
      r: bb(json['color_red']),
      g: bb(json['color_green']),
      c: bb(json['color_colorless']),
    );
  }
}
