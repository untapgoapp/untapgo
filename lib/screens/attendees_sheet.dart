import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/event_service.dart';
import 'profile_screen.dart';
import 'events/widgets/attendee_card.dart';
import 'event_detail_screen.dart';

/// 🔥 Overlay real (para usPadding( con showGeneralDialog)
class AttendeesOverlay extends StatelessWidget {
  final String eventId;

  const AttendeesOverlay({super.key, required this.eventId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 🔥 Draggable sheet
          DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder: (context, controller) {
              return AttendeesSheet(
                eventId: eventId,
                scrollController: controller,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 🔥 Contenido puro del sheet
class AttendeesSheet extends StatefulWidget {
  final String eventId;
  final ScrollController scrollController;

  const AttendeesSheet({
    super.key,
    required this.eventId,
    required this.scrollController,
  });

  @override
  State<AttendeesSheet> createState() => _AttendeesSheetState();
}

class _AttendeesSheetState extends State<AttendeesSheet> {
  late Future<List<_Attendee>> _future;
  String? _hostUserId;
  bool get _isHostUser {
    final me = Supabase.instance.client.auth.currentUser?.id;
    return me != null && _hostUserId != null && me == _hostUserId;
  }

  @override
  void initState() {
    super.initState();
    _future = _fetchAttendees();
    _loadHost();
  }

  Map<String, String> _headers() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _kick(String userId, String nickname) async {
    final confirm = await _confirmKick(nickname);
    if (!confirm) return;

    try {
      await http.post(
        Uri.parse(
          '${EventService.backendBaseUrl}/events/${widget.eventId}/kick',
        ),
        headers: _headers(),
        body: jsonEncode({
          'user_id': userId,
          'cooldown_minutes': 10,
        }),
      );

      setState(() {
        _future = _fetchAttendees();
      });

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<bool> _confirmKick(String nickname) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove player?'),
        content: Text(
          'Do you want to remove $nickname from this event?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    return res == true;
  }

  Future<void> _loadHost() async {
    try {
      final res = await http.get(
        Uri.parse('${EventService.backendBaseUrl}/events/${widget.eventId}'),
        headers: _headers(),
      );

      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final hostUserId = (data['host_user_id'] ?? '').toString();

      if (!mounted) return;

      setState(() {
        _hostUserId = hostUserId;
      });
    } catch (_) {}
  }

  Future<List<_Attendee>> _fetchAttendees() async {
    final res = await http.get(
      Uri.parse(
        '${EventService.backendBaseUrl}/events/${widget.eventId}/attendees',
      ),
      headers: _headers(),
    );

    if (res.statusCode != 200) {
      throw Exception(res.body);
    }

    final List data = jsonDecode(res.body) as List;
    return data
        .map((e) => _Attendee.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void _openProfile(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = Supabase.instance.client.auth.currentUser?.id;

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(28),
      ),
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.15),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const SizedBox(height: 12),

          // Grab handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          const SizedBox(height: 16),

          // Header con título centrado + X Apple-style
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Spacer(),
                const Text(
                  'Attendees',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: UntapCircleButton(
                    icon: Icons.close,
                    onTap: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Expanded(
            child: FutureBuilder<List<_Attendee>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }

                final attendees = snapshot.data ?? [];

                if (attendees.isEmpty) {
                  return const Center(
                    child: Text('No attendees yet'),
                  );
                }

                _Attendee? host;
                final others = <_Attendee>[];

                for (final a in attendees) {
                  if (_hostUserId != null && a.userId == _hostUserId) {
                    host = a;
                  } else {
                    others.add(a);
                  }
                }

                final displayList = <_Attendee>[
                  if (host != null) host!,
                  ...others,
                ];

                return ListView.separated(
                  controller: widget.scrollController,
                  itemCount: displayList.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: Colors.black.withOpacity(0.05),
                  ),
                  itemBuilder: (context, i) {
                    final a = displayList[i];
                    final isMe = me != null && a.userId == me;
                    final isHostRow =
                        _hostUserId != null && a.userId == _hostUserId;

                    final canKick =
                      _isHostUser &&
                      !isHostRow &&
                      !isMe;

                    return AttendeeCard(
                      userId: a.userId,
                      nickname: a.nickname,
                      avatarUrl: a.avatarUrl,
                      isMe: isMe,
                      isHost: isHostRow,
                      trailing: canKick
                        ? IconButton(
                            icon: const Icon(Icons.person_remove),
                            onPressed: () => _kick(a.userId, a.nickname),
                          )
                        : null,
                      onTap: () => _openProfile(context, a.userId),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Attendee {
  final String userId;
  final String nickname;
  final String? avatarUrl;

  _Attendee({
    required this.userId,
    required this.nickname,
    this.avatarUrl,
  });

  factory _Attendee.fromJson(Map<String, dynamic> json) {
    return _Attendee(
      userId: (json['id'] ?? json['user_id']).toString(),
      nickname: (json['nickname'] ?? '').toString(),
      avatarUrl: json['avatar_url']?.toString(),
    );
  }
}