import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/event_service.dart';
import 'profile_screen.dart';

class AttendeesScreen extends StatefulWidget {
  final String eventId;

  const AttendeesScreen({super.key, required this.eventId});

  @override
  State<AttendeesScreen> createState() => _AttendeesScreenState();
}

class _AttendeesScreenState extends State<AttendeesScreen> {
  // ─────────────────────────────────────────────────────────────
  // State
  // ─────────────────────────────────────────────────────────────

  late Future<List<_Attendee>> _future;

  bool _isHost = false;
  bool _loadingHost = true;
  bool _busy = false;
  bool _changed = false;

  String? _eventStatus; // Open / Full / Started / Ended / Cancelled

  // ─────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _future = _fetchAttendees();
    _loadHostAndStatus();
  }

  // ─────────────────────────────────────────────────────────────
  // Networking
  // ─────────────────────────────────────────────────────────────

  Map<String, String> _headers() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _loadHostAndStatus() async {
    setState(() => _loadingHost = true);
    try {
      final res = await http.get(
        Uri.parse('${EventService.backendBaseUrl}/events/${widget.eventId}'),
        headers: _headers(),
      );

      if (res.statusCode != 200) throw Exception(res.body);

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final hostUserId = (data['host_user_id'] ?? '').toString();
      final status = (data['status'] ?? '').toString();
      final me = Supabase.instance.client.auth.currentUser?.id;

      if (!mounted) return;
      setState(() {
        _isHost = me != null && me == hostUserId;
        _eventStatus = status;
        _loadingHost = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isHost = false;
        _eventStatus = null;
        _loadingHost = false;
      });
    }
  }

  Future<List<_Attendee>> _fetchAttendees() async {
    final res = await http.get(
      Uri.parse('${EventService.backendBaseUrl}/events/${widget.eventId}/attendees'),
      headers: _headers(),
    );

    if (res.statusCode != 200) {
      throw Exception(res.body);
    }

    final List data = jsonDecode(res.body) as List;
    return data.map((e) => _Attendee.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _reload() async {
    setState(() {
      _future = _fetchAttendees();
    });
    await _future;
    await _loadHostAndStatus();
  }

  // ─────────────────────────────────────────────────────────────
  // Navigation
  // ─────────────────────────────────────────────────────────────

  void _openProfile(BuildContext context, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: userId),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Host actions (Accept / Reject / Kick)
  // ─────────────────────────────────────────────────────────────

  Future<void> _acceptUser(String userId) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) throw Exception('AUTH_REQUIRED');

    final res = await http.post(
      Uri.parse('${EventService.backendBaseUrl}/events/${widget.eventId}/accept'),
      headers: _headers(),
      body: jsonEncode({'user_id': userId}),
    );

    if (res.statusCode != 200) throw Exception(res.body);
  }

  Future<void> _rejectUser(String userId, {int cooldownMinutes = 10}) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) throw Exception('AUTH_REQUIRED');

    final res = await http.post(
      Uri.parse('${EventService.backendBaseUrl}/events/${widget.eventId}/reject'),
      headers: _headers(),
      body: jsonEncode({'user_id': userId, 'cooldown_minutes': cooldownMinutes}),
    );

    if (res.statusCode != 200) throw Exception(res.body);
  }

  Future<void> _kickUser(String userId, {int cooldownMinutes = 10}) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) throw Exception('AUTH_REQUIRED');

    final res = await http.post(
      Uri.parse('${EventService.backendBaseUrl}/events/${widget.eventId}/kick'),
      headers: _headers(),
      body: jsonEncode({'user_id': userId, 'cooldown_minutes': cooldownMinutes}),
    );

    if (res.statusCode != 200) throw Exception(res.body);
  }

  String _actionErrorMessage(String raw, {required String action}) {
    if (raw.contains('EVENT_ENDED')) return 'This event has already ended.';
    if (raw.contains('EVENT_STARTED')) return 'This event already started.';
    if (raw.contains('NOT_EVENT_HOST')) return 'Only the host can do that.';
    if (raw.contains('AUTH_REQUIRED') || raw.contains('NOT_AUTHENTICATED')) {
      return 'You need to be logged in.';
    }

    if (raw.contains('EVENT_FULL')) return 'Event is full.';
    if (raw.contains('MEMBERSHIP_NOT_REQUESTED')) return 'This player is not requested.';
    if (raw.contains('ACCEPT_NOT_ALLOWED_FOR_EVENT_STATUS')) return 'Accept is not allowed now.';
    if (raw.contains('REJECT_NOT_ALLOWED_FOR_EVENT_STATUS')) return 'Reject is not allowed now.';
    if (raw.contains('KICK_NOT_ALLOWED_FOR_EVENT_STATUS')) return 'Kick is not allowed now.';

    return '$action failed. Please try again.';
  }

  Future<void> _doHostAction({
    required Future<void> Function() run,
    required String okMessage,
    required String actionName,
  }) async {
    if (_busy || !_isHost || _loadingHost) return;

    final canByStatus = _eventStatus == 'Open' || _eventStatus == 'Full';
    if (!canByStatus) return;

    setState(() => _busy = true);
    try {
      await run();
      _changed = true;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(okMessage)),
      );

      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_actionErrorMessage(e.toString(), action: actionName))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmKick(BuildContext context, _Attendee a) async {
    if (_busy || !_isHost || _loadingHost) return;

    final canByStatus = _eventStatus == 'Open' || _eventStatus == 'Full';
    if (!canByStatus) return;

    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me != null && a.userId == me) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kick player'),
        content: Text(
          'Kick ${a.nickname.isNotEmpty ? a.nickname : 'this player'} '
          'from the event?\n\nThey can rejoin after 10 minutes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kick (10 min)'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await _doHostAction(
      run: () => _kickUser(a.userId, cooldownMinutes: 10),
      okMessage: '${a.nickname.isNotEmpty ? a.nickname : 'Player'} kicked (10 min cooldown)',
      actionName: 'Kick',
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Status helpers
  // ─────────────────────────────────────────────────────────────

  bool _isRequestedStatus(String? s) {
    final v = (s ?? '').trim().toLowerCase();
    return v == 'requested' || v == 'pending';
  }

  bool _isJoinedStatus(String? s) {
    return (s ?? '').trim().toLowerCase() == 'joined';
  }

  Widget _statusPill(String status) {
    final s = status.trim();
    if (s.isEmpty) return const SizedBox.shrink();

    final lower = s.toLowerCase();

    final bg = lower == 'joined'
        ? Colors.green.withOpacity(0.12)
        : (lower == 'requested' || lower == 'pending')
            ? Colors.orange.withOpacity(0.12)
            : Colors.grey.withOpacity(0.12);

    final border = lower == 'joined'
        ? Colors.green.withOpacity(0.35)
        : (lower == 'requested' || lower == 'pending')
            ? Colors.orange.withOpacity(0.35)
            : Colors.grey.withOpacity(0.35);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        s,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final me = Supabase.instance.client.auth.currentUser?.id;

    final canHostActionsByStatus = _eventStatus == 'Open' || _eventStatus == 'Full';
    final canHostActions = _isHost && !_loadingHost && !_busy && canHostActionsByStatus;

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _changed);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Attendees'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _changed),
          ),
          actions: [
            if (_busy || _loadingHost)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Center(
                  child: SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_isHost)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Center(child: Text('Host')),
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _reload,
          child: FutureBuilder<List<_Attendee>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 120),
                    Center(child: Text('Error: ${snapshot.error}')),
                  ],
                );
              }

              final attendees = snapshot.data ?? [];
              if (attendees.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 120),
                    Center(child: Text('No attendees yet')),
                  ],
                );
              }

              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: attendees.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final a = attendees[i];
                  final isMe = me != null && a.userId == me;

                  // REAL status: only used for host button logic
                  final isRequested = _isRequestedStatus(a.status);
                  final isJoined = _isJoinedStatus(a.status);

                  // UI status: comes from SQL (already hidden for third parties)
                  // ✅ IMPORTANT: DO NOT show "joined" pill in attendees list.
                  final uiStatus = (a.visibleStatus ?? '').trim();
                  final showStatusPill = uiStatus.isNotEmpty && !_isJoinedStatus(uiStatus);
                  final showYou = isMe;

                  Widget? trailing;
                  if (canHostActions && !isMe) {
                    if (isRequested) {
                      trailing = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Reject (10m)',
                            icon: const Icon(Icons.close),
                            onPressed: () => _doHostAction(
                              run: () => _rejectUser(a.userId, cooldownMinutes: 10),
                              okMessage:
                                  '${a.nickname.isNotEmpty ? a.nickname : 'Player'} rejected (10 min cooldown)',
                              actionName: 'Reject',
                            ),
                          ),
                          IconButton(
                            tooltip: 'Accept',
                            icon: const Icon(Icons.check),
                            onPressed: () => _doHostAction(
                              run: () => _acceptUser(a.userId),
                              okMessage:
                                  '${a.nickname.isNotEmpty ? a.nickname : 'Player'} accepted',
                              actionName: 'Accept',
                            ),
                          ),
                        ],
                      );
                    } else if (isJoined) {
                      trailing = IconButton(
                        tooltip: 'Kick',
                        onPressed: () => _confirmKick(context, a),
                        icon: const Icon(Icons.person_remove_outlined),
                      );
                    }
                  }

                  final initial =
                      (a.nickname.isNotEmpty ? a.nickname[0] : '?').toUpperCase();

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: (a.avatarUrl != null && a.avatarUrl!.isNotEmpty)
                          ? NetworkImage(a.avatarUrl!)
                          : null,
                      child: (a.avatarUrl == null || a.avatarUrl!.isEmpty)
                          ? Text(initial)
                          : null,
                    ),
                    title: Row(
                      children: [
                        Text(a.nickname.isNotEmpty ? a.nickname : 'Player'),
                        if (showYou) ...[
                          const SizedBox(width: 6),
                          Text(
                            '(You)',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.black54,
                                  fontStyle: FontStyle.italic,
                                ),
                          ),
                        ],
                      ],
                    ),
                    trailing: showStatusPill ? _statusPill(uiStatus) : trailing,
                    onTap: () => _openProfile(context, a.userId),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────

class _Attendee {
  final String userId;
  final String nickname;
  final String? avatarUrl;

  final String? status; // REAL: para botones host
  final String? visibleStatus; // UI: lo que se enseña a terceros

  _Attendee({
    required this.userId,
    required this.nickname,
    this.avatarUrl,
    this.status,
    this.visibleStatus,
  });

  factory _Attendee.fromJson(Map<String, dynamic> json) {
    return _Attendee(
      userId: (json['id'] ?? json['user_id']).toString(),
      nickname: (json['nickname'] ?? '').toString(),
      avatarUrl: json['avatar_url']?.toString(),
      status: json['status']?.toString(),
      visibleStatus: json['visible_status']?.toString(),
    );
  }
}
