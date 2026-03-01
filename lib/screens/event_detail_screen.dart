import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'profile_screen.dart';
import '../models/event.dart';
import '../services/event_service.dart';
import 'attendees_sheet.dart';
import 'edit_event_screen.dart';
import 'requests_screen.dart';
import 'event_detail/widgets/event_action_bar.dart';
import 'event_detail/widgets/event_players_preview_card.dart';
import 'event_detail/widgets/event_requests_preview_card.dart';
import 'event_detail/event_detail_controller.dart';
import 'event_detail/widgets/event_map_preview.dart';
import 'event_detail/widgets/event_info_section.dart';

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

  static const Color _untapPurple = Color(0xFF6E5AA7);

  late EventDetailController _controller;

  late Event _event;
  bool _changed = false;

  // Players preview (joined only)
  List<Map<String, dynamic>> _attendeesPreview = [];
  bool _loadingAttendees = false;

  // Requests preview (host-only)
  List<Map<String, dynamic>> _requestsPreview = [];
  bool _loadingRequests = false;
  int _requestsCount = 0;

  bool _inWatchlist = false;


  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _controller = EventDetailController(
      event: _event,
      svc: _svc,
    );
    _loadAttendeesPreview();
    if (_isHost) {
      _loadRequestsPreview();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
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

  bool get _canEditEvent => _isHost && _isOpen;

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
  // Navigation
  // ─────────────────────────────────────────────────────────────

  Future<void> _openAttendees() async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withOpacity(0.4),
        pageBuilder: (_, __, ___) {
          return Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      color: Colors.black.withOpacity(0.2),
                    ),
                  ),
                ),
                AttendeesOverlay(eventId: _event.id),
              ],
            ),
          );
        },
      transitionBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
    );

    await _refreshEventById();
    _loadAttendeesPreview();
    if (_isHost) _loadRequestsPreview();
  }

  Future<void> _openRequests() async {
    debugPrint('OPEN REQUESTS CALLED');
    await Future.delayed(Duration.zero);

    final changed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withOpacity(0.4),
        pageBuilder: (_, __, ___) {
          return Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      color: Colors.black.withOpacity(0.2),
                    ),
                  ),
                ),
                RequestsOverlay(eventId: _event.id),
              ],
            ),
          );

      },
    );

    if (changed == true) {
      _changed = true;
      await _refreshEventById();
      _loadAttendeesPreview();
    }

    if (_isHost) {
      _loadRequestsPreview();
    }
  }

  // ✅ CHANGE: EditEvent now returns Event? (not bool)
  Future<void> _openEditEvent() async {
    if (!_canEditEvent) return;
    
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
 
  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.day}/${dt.month}/${dt.year} '
         '${dt.hour.toString().padLeft(2, '0')}:'
         '${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatBackgroundAsset() {
    switch (_event.formatSlug) {
      case 'commander':
        return 'assets/covers/commander.png';
      case 'modern':
        return 'assets/covers/modern.png';
      case 'legacy':
        return 'assets/covers/legacy.png';
      case 'pioneer':
        return 'assets/covers/pioneer.png';
      case 'standard':
        return 'assets/covers/standard.png';
      case 'vintage':
        return 'assets/covers/vintage.png';
      case 'draft':
        return 'assets/covers/draft.png';
      case 'cube':
        return 'assets/covers/cube.png';
      case 'premodern':
        return 'assets/covers/premodern.png';
      case 'sealed':
        return 'assets/covers/sealed.png';
      default:
        return 'assets/covers/other.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
       body: CustomScrollView(
        slivers: [

          /// ─────────────────────────────────────────────
          /// HERO
          /// ─────────────────────────────────────────────

          SliverAppBar(
            pinned: true,
            expandedHeight: 200,
            collapsedHeight: kToolbarHeight,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            leadingWidth: 72,

            leading: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: UntapCircleButton(
                  icon: Icons.arrow_back_outlined,
                  onTap: () => Navigator.pop(context, _changed),
                ),
              ),
            ),

            actions: [
              UntapCircleButton(
                icon: Icons.visibility_outlined,
                active: _inWatchlist,
                onTap: () {
                  setState(() {
                    _inWatchlist = !_inWatchlist;
                  });
                },
              ),
              UntapCircleButton(
                icon: Icons.share,
                onTap: () {
                  const playStoreUrl = 'https://untapgo.com';
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
              if (_canEditEvent)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: UntapCircleButton(
                    icon: Icons.edit,
                    onTap: _openEditEvent,
                  ),
                ),
            ],

            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    _formatBackgroundAsset(),
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.35, 1.0],
                        colors: [
                          Colors.transparent,
                          Color(0x4D000000),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(
                        _event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          /// ─────────────────────────────────────────────
          /// COUNTDOWN BANNER (FIJA)
          /// ─────────────────────────────────────────────

          if (_event.startsAt != null && !_isEnded)
            SliverPersistentHeader(
              pinned: true,
              delegate: _CountdownHeaderDelegate(
                startsAt: _event.startsAt!,
              ),
            ),

          /// ─────────────────────────────────────────────
          /// CONTENT
          /// ─────────────────────────────────────────────

          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -32),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.background,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [

                    EventInfoSection(
                      event: _event,
                      formatDate: _formatDate,
                      proxiesLabel: _proxiesLabel,
                      formatLabels: kFormatLabels,
                      onHostTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProfileScreen(
                              userId: _event.hostUserId,
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    EventPlayersPreviewCard(
                      attendeesCount: _event.attendeesCount,
                      maxPlayers: _event.maxPlayers,
                      attendeesPreview: _attendeesPreview,
                      loading: _loadingAttendees,
                      onSeeAll: _openAttendees,
                    ),

                    const SizedBox(height: 12),

                    EventRequestsPreviewCard(
                      isHost: _isHost,
                      requestsCount: _requestsCount,
                      requestsPreview: _requestsPreview,
                      loading: _loadingRequests,
                      onSeeAll: _openRequests,
                    ),

                    const SizedBox(height: 32),

                    EventActionBar(
                      event: _event,
                      isHost: _isHost,
                      isJoined: _isJoined,
                      isRequested: _isRequested,
                      isEventFull: _isEventFull,
                      canLeave: _canLeave,
                      canJoin: _canJoin,
                      canCancelRequest: _canCancelRequest,
                      canCancelEvent: _canCancelEvent,
                      busy: _controller.busy,
                      inJoinCooldown: _controller.inJoinCooldown,
                      joinCooldownSecs: _controller.joinCooldownSecs,
                      joinCooldownTotalSecs:
                          _controller.joinCooldownTotalSecs,
                      error: _controller.error,
                      onJoin: () async {
                        try {
                          await _controller.join();
                          setState(() {});
                        } catch (_) {
                          setState(() {});
                        }
                      },
                      onLeave: () async {
                        try {
                          await _controller.leave();
                          setState(() {});
                        } catch (_) {
                          setState(() {});
                        }
                      },
                      onCancelRequest: () async {
                        try {
                          await _controller.leave();
                          setState(() {});
                        } catch (_) {
                          setState(() {});
                        }
                      },
                      onCancelEvent: () async {
                        final ok = await _confirm(
                          title: 'Cancel event?',
                          message:
                              'This will cancel the event for everyone. This can’t be undone.',
                          confirmText: 'Cancel',
                        );
                        if (!ok) return;

                        try {
                          await _controller.cancelEvent();
                          setState(() {});
                        } catch (_) {
                          setState(() {});
                        }
                      },
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
  class UntapCircleButton extends StatefulWidget {
    final IconData icon;
    final VoidCallback onTap;
    final bool active;

    const UntapCircleButton({
      super.key,
      required this.icon,
      required this.onTap,
      this.active = false,
    });

    @override
    State<UntapCircleButton> createState() => _UntapCircleButtonState();
  }

class _UntapCircleButtonState extends State<UntapCircleButton>
    with SingleTickerProviderStateMixin {

  static const Color _untapPurple = Color(0xFF6E5AA7);

  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );

    _animation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.92),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.92, end: 1.05),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.05, end: 1.0),
        weight: 30,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedBuilder(
          animation: _animation,
          builder: (_, child) {
            return Transform.scale(
              scale: _animation.value,
              child: child,
            );
          },
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.active ? _untapPurple : Colors.white,
              border: Border.all(
                color: _untapPurple,
                width: 1.5,
              ),
            ),
            child: Icon(
              widget.icon,
              size: 22,
              color: widget.active ? Colors.white : _untapPurple,
            ),
          ),
        ),
      ),
    );
  }
}
class _CountdownHeaderDelegate extends SliverPersistentHeaderDelegate {
  final DateTime startsAt;

  _CountdownHeaderDelegate({
    required this.startsAt,
  });

  @override
  Widget build(
      BuildContext context,
      double shrinkOffset,
      bool overlapsContent,
      ) {
    final now = DateTime.now();
    final diff = startsAt.toLocal().difference(now);

    // Mostrar solo si empieza en menos de 2h y aún no ha empezado
    if (diff <= Duration.zero || diff > const Duration(hours: 2)) {
      return Container(
        color: Colors.transparent,
      );
    }

    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);

    final label = hours > 0
        ? 'Starting in ${hours}h ${minutes}m'
        : 'Starting in ${minutes}m';

    return Container(
      color: const Color(0xFF6E5AA7),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          letterSpacing: 0.2,
          color: Color.fromARGB(255, 245, 245, 245),
        ),
      ),
    );
  }

  @override
  double get maxExtent => 44;

  @override
  double get minExtent => 44;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return true;
  }
}