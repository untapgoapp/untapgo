import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/event.dart';
import '../services/event_service.dart';
import 'attendees_screen.dart';
import 'edit_event_screen.dart';
import 'requests_screen.dart';

/// ✅ UI labels for format slugs.
/// Keep in sync with public.formats.slug
const Map<String, String> kFormatLabels = {
  'commander': 'Commander',
  'cube': 'Cube',
  'draft': 'Draft',
  'legacy': 'Legacy',
  'modern': 'Modern',
  'pauper': 'Pauper',
  'pioneer': 'Pioneer',
  'premodern': 'Premodern',
  'sealed': 'Sealed',
  'standard': 'Standard',
  'vintage': 'Vintage',
  'other': 'Other',
};

class EventDetailScreen extends StatefulWidget {
  final Event event;

  const EventDetailScreen({super.key, required this.event});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final EventService _svc = EventService();

  late Event _event;
  bool _busy = false;
  String? _error;
  bool _changed = false;

  // Players preview (joined only)
  List<Map<String, dynamic>> _attendeesPreview = [];
  bool _loadingAttendees = false;

  // Requests preview (host-only)
  List<Map<String, dynamic>> _requestsPreview = [];
  bool _loadingRequests = false;
  int _requestsCount = 0;

  // ─────────────────────────────────────────────────────────────
  // Join/Cancel-request anti-spam cooldown (local UX guard)
  // ─────────────────────────────────────────────────────────────

  DateTime? _joinCooldownUntil;

  // NEW: Keep a stable total so we can show a subtle progress indicator
  int _joinCooldownTotalSecs = 0;

  // NEW: Tick UI while cooldown is active (previously it only refreshed start/end)
  Timer? _joinCooldownTimer;

  bool get _inJoinCooldown =>
      _joinCooldownUntil != null &&
      DateTime.now().isBefore(_joinCooldownUntil!);

  int get _joinCooldownSecs {
    if (!_inJoinCooldown) return 0;
    return _joinCooldownUntil!.difference(DateTime.now()).inSeconds + 1;
  }

  void _startJoinCooldown([int seconds = 10]) {
    // Make sure we never shrink an existing cooldown accidentally.
    final now = DateTime.now();
    final currentLeft = _inJoinCooldown ? _joinCooldownSecs : 0;
    final target = seconds > currentLeft ? seconds : currentLeft;

    _joinCooldownUntil = now.add(Duration(seconds: target));
    _joinCooldownTotalSecs = target;

    _joinCooldownTimer?.cancel();

    if (mounted) setState(() {}); // refresca label/disabled

    // Tick once per second to update button label + indicator
    _joinCooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (!_inJoinCooldown) {
        t.cancel();
        setState(() {}); // final refresh
        return;
      }
      setState(() {}); // keep countdown moving
    });

    // Keep the original delayed refresh too (no harm, no refactor)
    Future.delayed(Duration(seconds: target + 1), () {
      if (!mounted) return;
      setState(() {}); // refresca al terminar
    });
  }

  // NEW: Try to extract server cooldown seconds from error object.
  // We keep regex fallback because humans love fragile string parsing.
  int? _cooldownSecondsFromError(Object e) {
    final raw = e.toString();

    // supports "seconds=123"
    final m1 = RegExp(r'seconds=(\d+)').firstMatch(raw);
    // supports '"cooldown_seconds": 123' OR 'cooldown_seconds=123'
    final m2 = RegExp(r'cooldown_seconds["=: ]+(\d+)').firstMatch(raw);

    final match = m1 ?? m2;
    if (match == null) return null;

    final s = int.tryParse(match.group(1) ?? '');
    if (s == null) return null;
    if (s <= 0) return null;
    return s;
  }

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _loadAttendeesPreview();
    if (_isHost) {
      _loadRequestsPreview();
    }
  }

  @override
  void dispose() {
    _joinCooldownTimer?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // Auth helpers
  // ─────────────────────────────────────────────────────────────

  String? get _me => Supabase.instance.client.auth.currentUser?.id;
  bool get _isHost => _me != null && _event.hostUserId == _me;

  Map<String, String> _headers() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ─────────────────────────────────────────────────────────────
  // Status (normalized once, used everywhere)
  // ─────────────────────────────────────────────────────────────

  String get _status => (_event.status).trim().toLowerCase();

  bool get _isOpen => _status == 'open';
  bool get _isFull => _status == 'full';
  bool get _isStarted => _status == 'started';
  bool get _isEnded => _status == 'ended';
  bool get _isCancelled => _status == 'cancelled';

  // ─────────────────────────────────────────────────────────────
  // Membership state (my_status is source of truth)
  // ─────────────────────────────────────────────────────────────

  String get _myStatus => (_event.myStatus ?? '').trim().toLowerCase();
  bool get _isJoined => _myStatus == 'joined';

  bool get _isRequested =>
      _myStatus == 'pending' ||
      _myStatus == 'requested' ||
      _myStatus.contains('pend') ||
      _myStatus.contains('request');

  bool get _canJoin => _isOpen && !_isJoined && !_isRequested;

  bool get _canLeave => _isJoined && !_isEnded && !_isCancelled;
  bool get _canCancelRequest => _isRequested && (_isOpen || _isFull);

  bool get _canCancelEvent => _isHost && (_isOpen || _isFull);

  bool get _isEventFull => _isFull;

  // ─────────────────────────────────────────────────────────────
  // Proxies display helpers
  // DB: CHECK (proxies_policy IN ('Yes','No','Ask'))
  // UI: show friendly labels
  // ─────────────────────────────────────────────────────────────

  String? _proxiesLabel() {
    final raw = (_event.proxies ?? '').toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return null;

    switch (raw) {
      case 'Yes':
        return 'Allowed';
      case 'No':
        return 'Not allowed';
      case 'Ask':
        return 'Ask host';
      default:
        return raw;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Backend refresh
  // ─────────────────────────────────────────────────────────────

  Future<void> _refreshEventById() async {
    final res = await http.get(
      Uri.parse('${EventService.backendBaseUrl}/events/${_event.id}'),
      headers: _headers(),
    );

    if (res.statusCode != 200) {
      throw Exception(res.body);
    }

    // 🔍 DEBUG: raw backend JSON
    debugPrint('EVENT DETAIL RAW JSON → ${res.body}');

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final updated = Event.fromJson(data);

    // 🔍 DEBUG: parsed model
    debugPrint(
      'PARSED EVENT → formatSlug=${updated.formatSlug} | format=${updated.format} | proxies=${updated.proxies}',
    );

    // ✅ Preserve proxies if backend response comes back empty/null transiently
    final prevProxies = (_event.proxies ?? '').toString().trim();
    final nextProxies = (updated.proxies ?? '').toString().trim();

    final merged = (nextProxies.isEmpty && prevProxies.isNotEmpty)
        ? updated.copyWith(proxies: prevProxies)
        : updated;

    if (!mounted) return;
    setState(() => _event = merged);
  }

  Future<void> _refreshEventByIdWithRetry({
    int attempts = 3,
    Duration delay = const Duration(milliseconds: 250),
  }) async {
    for (var i = 0; i < attempts; i++) {
      await _refreshEventById();
      if ((_event.myStatus ?? '').trim().isNotEmpty) return;
      if (i < attempts - 1) await Future.delayed(delay);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Players preview
  // ─────────────────────────────────────────────────────────────

  Future<void> _loadAttendeesPreview() async {
    if (!mounted) return;
    setState(() => _loadingAttendees = true);

    try {
      final res = await http.get(
        Uri.parse('${EventService.backendBaseUrl}/events/${_event.id}/attendees'),
        headers: _headers(),
      );

      if (res.statusCode != 200) {
        throw Exception(res.body);
      }

      final data = jsonDecode(res.body) as List<dynamic>;
      final rows = data.cast<Map<String, dynamic>>();
      final preview = rows.take(4).toList();

      if (!mounted) return;
      setState(() => _attendeesPreview = preview);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingAttendees = false);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Requests preview (host-only)
  // ─────────────────────────────────────────────────────────────

  Future<void> _loadRequestsPreview() async {
    if (!mounted) return;
    setState(() => _loadingRequests = true);

    try {
      final res = await http.get(
        Uri.parse('${EventService.backendBaseUrl}/events/${_event.id}/requests'),
        headers: _headers(),
      );

      if (res.statusCode != 200) {
        throw Exception(res.body);
      }

      final data = jsonDecode(res.body) as List<dynamic>;
      final rows = data.cast<Map<String, dynamic>>();
      final preview = rows.take(4).toList();

      if (!mounted) return;
      setState(() {
        _requestsCount = rows.length;
        _requestsPreview = preview;
      });
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingRequests = false);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Display helpers
  // ─────────────────────────────────────────────────────────────

  String _displayName(Map<String, dynamic> a) {
    final nick = (a['nickname'] ?? a['host_nickname'] ?? '').toString().trim();
    if (nick.isNotEmpty) return nick;

    final id = (a['user_id'] ?? a['id'] ?? '').toString();
    if (id.isNotEmpty && id.length >= 4) return 'Player ${id.substring(0, 4)}';

    return 'Player';
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  void _toastError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.grey.shade900,
      ),
    );
  }

  String _humanizeError(Object e) {
    final raw = e.toString();

    if (raw.contains('KICK_COOLDOWN_ACTIVE') ||
        raw.contains('JOIN_COOLDOWN_ACTIVE')) {
      // supports "seconds=123"
      final m1 = RegExp(r'seconds=(\d+)').firstMatch(raw);
      // supports '"cooldown_seconds": 123' OR 'cooldown_seconds=123'
      final m2 = RegExp(r'cooldown_seconds["=: ]+(\d+)').firstMatch(raw);

      final match = m1 ?? m2;
      if (match != null) {
        final mins = (int.parse(match.group(1)!) / 60).ceil();
        return 'You phased out. Try to rejoin in $mins minutes';
      }
      return 'You phased out. Try to rejoin later';
    }

    return raw.replaceFirst('Exception: ', '');
  }

  // ─────────────────────────────────────────────────────────────
  // Maps
  // ─────────────────────────────────────────────────────────────

  Future<void> _openMaps(String query) async {
    final q = Uri.encodeComponent(query);
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      _toastError('Could not open Maps');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Confirm dialog
  // ─────────────────────────────────────────────────────────────

  Future<bool> _confirm({
    required String title,
    required String message,
    String confirmText = 'Confirm',
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return res == true;
  }

  // ─────────────────────────────────────────────────────────────
  // Actions
  // ─────────────────────────────────────────────────────────────

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    // ✅ Local anti-spam cooldown for request loop
    // Keep for Cancel request. For Join, prefer server cooldown if it triggers.
    if (label == 'Cancel request') {
      _startJoinCooldown(10);
    }

    if (label == 'Join') {
      setState(() => _event = _event.copyWith(myStatus: 'pending'));
    } else if (label == 'Leave' || label == 'Cancel request') {
      setState(() => _event = _event.copyWith(myStatus: null));
    }

    try {
      await action();
      await _refreshEventByIdWithRetry();

      _changed = true;
      _toast('$label OK');

      _loadAttendeesPreview();
      if (_isHost) _loadRequestsPreview();
    } catch (e) {
      // NEW: if server says cooldown, start local cooldown with real seconds
      if (label == 'Join' || label == 'Cancel request') {
        final secs = _cooldownSecondsFromError(e);
        if (secs != null) {
          _startJoinCooldown(secs);
        }
      }

      final msg = _humanizeError(e);
      setState(() => _error = msg);
      _toastError(msg);

      try {
        await _refreshEventById();
        _loadAttendeesPreview();
        if (_isHost) _loadRequestsPreview();
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Navigation
  // ─────────────────────────────────────────────────────────────

  Future<void> _openAttendees() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AttendeesScreen(eventId: _event.id),
      ),
    );

    if (changed == true) {
      _changed = true;
      await _refreshEventById();
      _loadAttendeesPreview();
      if (_isHost) _loadRequestsPreview();
    }
  }

  Future<void> _openRequests() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RequestsScreen(eventId: _event.id),
      ),
    );
    if (changed == true) {
      _changed = true;
      await _refreshEventById();
      _loadAttendeesPreview();
    }
    if (_isHost) _loadRequestsPreview();
  }

  // ✅ CHANGE: EditEvent now returns Event? (not bool)
  Future<void> _openEditEvent() async {
    final updated = await Navigator.push<Event?>(
      context,
      MaterialPageRoute(
        builder: (_) => EditEventScreen(event: _event),
      ),
    );

    if (!mounted || updated == null) return;

    // ✅ UI instant update (no waiting for backend)
    setState(() => _event = updated);
    _changed = true;

    // ✅ Then confirm with backend truth
    await _refreshEventById();
    _loadAttendeesPreview();
    if (_isHost) _loadRequestsPreview();
  }

  Future<bool> _onWillPop() async {
    Navigator.pop(context, _changed);
    return false;
  }

  // ─────────────────────────────────────────────────────────────
  // UI helpers
  // ─────────────────────────────────────────────────────────────

  Widget _infoRow({
    required IconData icon,
    required String title,
    required String value,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value),
      trailing: onTap == null ? null : const Icon(Icons.open_in_new, size: 18),
      onTap: onTap,
    );
  }

  Widget _summaryCard() {
    final hostName =
        _event.hostNickname.trim().isEmpty ? 'Unknown' : _event.hostNickname;
    final addr = (_event.addressText ?? '').trim();

    final proxiesLabel = _proxiesLabel();

    // ✅ Format: use ONLY formatSlug (backend truth)
    final slug = (_event.formatSlug ?? '').trim().toLowerCase();
    final fmtLabel = slug.isEmpty ? null : (kFormatLabels[slug] ?? slug);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _infoRow(
              icon: Icons.flag_outlined,
              title: 'Status',
              value: _event.status,
            ),
            _infoRow(icon: Icons.person_outline, title: 'Host', value: hostName),
            _infoRow(
              icon: Icons.schedule,
              title: 'Starts',
              value: _event.startsLabel(),
            ),
            _infoRow(
              icon: Icons.style_outlined,
              title: 'Format',
              value: fmtLabel ?? 'Other',
            ),
            if (proxiesLabel != null)
              _infoRow(
                icon: Icons.copy_all_outlined,
                title: 'Proxies',
                value: proxiesLabel,
              ),
            if ((_event.powerLevel ?? '').trim().isNotEmpty)
              _infoRow(
                icon: Icons.bolt,
                title: 'Power level',
                value: _event.powerLevel!.trim(),
              ),
            if (addr.isNotEmpty)
              _infoRow(
                icon: Icons.place_outlined,
                title: 'Location',
                value: addr,
                onTap: () => _openMaps(addr),
              ),
            if ((_event.hostNotes ?? '').trim().isNotEmpty) ...[
              const Divider(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Host notes',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_event.hostNotes!),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _playersPreviewCard() {
    final countLabel = '${_event.attendeesCount}/${_event.maxPlayers}';
    final showNames = _attendeesPreview.isNotEmpty;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Players', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Text(countLabel, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _openAttendees,
                  child: const Text('See all'),
                ),
              ],
            ),
            if (_loadingAttendees) ...[
              const SizedBox(height: 6),
              const LinearProgressIndicator(minHeight: 2),
            ] else if (showNames) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _attendeesPreview.map((a) {
                  final name = _displayName(a);
                  final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(radius: 12, child: Text(initials)),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(name, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _requestsPreviewCard() {
    if (!_isHost) return const SizedBox.shrink();

    final showNames = _requestsPreview.isNotEmpty;
    final label = _loadingRequests ? '…' : '$_requestsCount';

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Requests', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _openRequests,
                  child: const Text('See all'),
                ),
              ],
            ),
            if (_loadingRequests) ...[
              const SizedBox(height: 6),
              const LinearProgressIndicator(minHeight: 2),
            ] else if (!showNames) ...[
              const SizedBox(height: 6),
              Text('No requests', style: Theme.of(context).textTheme.bodySmall),
            ] else ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _requestsPreview.map((a) {
                  final name = _displayName(a);
                  final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(radius: 12, child: Text(initials)),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(name, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bottomActionBar() {
    String headline;
    if (_isHost) {
      headline = "You're hosting";
    } else if (_isJoined) {
      headline = "You're in";
    } else if (_isRequested) {
      headline = "Request pending";
    } else if (_isEventFull) {
      headline = "Event is full";
    } else {
      headline = "Slots available";
    }

    String primaryLabel;
    VoidCallback? primaryOnPressed;

    String? secondaryLabel;
    VoidCallback? secondaryOnPressed;

    if (_isJoined) {
      primaryLabel = 'Leave';
      primaryOnPressed = _busy || !_canLeave
          ? null
          : () => _run('Leave', () async {
                await _svc.leaveEvent(_event.id);
              });
    } else if (_isRequested) {
      primaryLabel = _inJoinCooldown
          ? 'Cancel request (${_joinCooldownSecs}s)'
          : 'Cancel request';
      primaryOnPressed =
          _busy || _inJoinCooldown || !_canCancelRequest ? null : () => _run(
                'Cancel request',
                () async {
                  await _svc.leaveEvent(_event.id);
                },
              );
    } else if (_isEventFull) {
      primaryLabel = 'No slots available';
      primaryOnPressed = null;
    } else {
      primaryLabel = _inJoinCooldown ? 'Join (${_joinCooldownSecs}s)' : 'Join';
      primaryOnPressed = _busy || _inJoinCooldown || !_canJoin
          ? null
          : () => _run('Join', () async {
                await _svc.joinEvent(_event.id);
              });
    }

    if (_canCancelEvent) {
      secondaryLabel = 'Cancel event';
      secondaryOnPressed = _busy
          ? null
          : () async {
              final ok = await _confirm(
                title: 'Cancel event?',
                message:
                    'This will cancel the event for everyone. This can’t be undone.',
                confirmText: 'Cancel',
              );
              if (!ok) return;
              await _run('Cancel', () async {
                await _svc.cancelEvent(_event.id);
              });
            };
    }

    // NEW: subtle cooldown indicator (thin, low-noise)
    final showCooldownIndicator = _inJoinCooldown && _joinCooldownTotalSecs > 0;
    final progress = showCooldownIndicator
        ? (_joinCooldownSecs / _joinCooldownTotalSecs).clamp(0.0, 1.0)
        : 0.0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _error!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: primaryOnPressed,
                        child: Text(primaryLabel),
                      ),
                    ),
                    if (secondaryLabel != null) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: secondaryOnPressed,
                          child: Text(secondaryLabel),
                        ),
                      ),
                    ],
                  ],
                ),
                if (showCooldownIndicator) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_event.title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _changed),
          ),
          actions: [
            if (_isHost)
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: _busy ? null : _openEditEvent,
              ),
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () {
                const playStoreUrl =
                  'https://play.google.com/store/apps/details?id=com.untapgo.app';

                final address = (_event.addressText ?? '').trim();

                final text = StringBuffer()
                  ..writeln('Join my game on UntapGo!')
                  ..writeln()
                  ..writeln(_event.title)
                  ..writeln('Host: ${_event.hostNickname}');

                if (address.isNotEmpty) {
                  text.writeln(address);
                }

                text
                  ..writeln()
                  ..writeln('Get the app:')
                  ..writeln(playStoreUrl);

                Share.share(text.toString().trim());
              },
            ),
          ],
        ),
        bottomNavigationBar: _bottomActionBar(),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _summaryCard(),
            const SizedBox(height: 12),
            _playersPreviewCard(),
            const SizedBox(height: 12),
            _requestsPreviewCard(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}
