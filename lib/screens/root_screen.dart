import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../models/public_profile.dart' as models;
import '../services/event_service.dart';

import 'events_list_screen.dart';
import 'my_events_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import 'about_screen.dart';
import 'event_detail_screen.dart';
import 'support_screen.dart';
import 'safety_screen.dart';


class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  RealtimeChannel? _notifChannel;
  StreamSubscription<AuthState>? _authSub;

  int _unreadCount = 0;
  List<Map<String, dynamic>> _notifications = [];

  models.PublicProfile? _profile;
  bool _profileLoading = false;

  // ─────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    final session = supabase.auth.currentSession;
    print('INITIAL SESSION: ${session != null}');

    if (session != null) {
      _initUser(session.user.id);
    }

    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      print('AUTH CHANGE: ${data.session != null}');
      print('SESSION USER ID: ${data.session?.user.id}');
      print('CURRENT USER: ${supabase.auth.currentUser?.id}');

      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        _initUser(userId);
      }
    });

    final userId = supabase.auth.currentUser?.id;
    if (userId != null) {
      _initUser(userId);
    }
  }

  void _initUser(String userId) {
    print('INIT USER CALLED WITH: $userId');
    _loadInitialNotifications(userId);
    _listenNotifications(userId);
    _loadProfile(userId);
  }

  @override
  void dispose() {
    _notifChannel?.unsubscribe();
    _authSub?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // Profile (backend source of truth)
  // ─────────────────────────────────────────────

  Future<void> _loadProfile(String userId) async {
    setState(() {
      _profileLoading = true;
    });

    try {
      final p = await _fetchProfile(userId);
      if (!mounted) return;

      setState(() {
        _profile = p;
        _profileLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _profileLoading = false;
      });
    }
  }

  Future<models.PublicProfile> _fetchProfile(String userId) async {
    final token = supabase.auth.currentSession?.accessToken;

    print('FETCH PROFILE USER ID: $userId');
    print('TOKEN NULL? ${token == null}');

    final res = await http.get(
      Uri.parse('${EventService.backendBaseUrl}/profiles/$userId'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );

    if (res.statusCode != 200) {
      throw Exception(res.body);
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return models.PublicProfile.fromJson(data);
  }

  // ─────────────────────────────────────────────
  // Notifications
  // ─────────────────────────────────────────────

  Future<void> _loadInitialNotifications(String userId) async {
    final data = await supabase
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .eq('is_read', false)
        .order('created_at', ascending: false);

    if (!mounted) return;

    setState(() {
      _notifications = List<Map<String, dynamic>>.from(data);
      _unreadCount = _notifications.length;
    });
  }

  void _listenNotifications(String userId) {
    _notifChannel?.unsubscribe();

    _notifChannel = supabase
        .channel('notifications:user_id=eq.$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          callback: (payload) {
            if (!mounted) return;

            final row = payload.newRecord;
            if (row.isEmpty) return;

            setState(() {
              _notifications.insert(0, row);
              _unreadCount++;
            });
          },
        )
        .subscribe();
  }

  Future<void> _markAllRead() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);

    if (!mounted) return;

    setState(() {
      _notifications.clear();
      _unreadCount = 0;
    });
  }

  Future<void> _markOneRead(String id) async {
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('id', id);

    if (!mounted) return;

    setState(() {
      _notifications.removeWhere((n) => n['id'] == id);
      _unreadCount = _notifications.length;
    });
  }

  // ─────────────────────────────────────────────
  // Auth
  // ─────────────────────────────────────────────

  Future<void> _logout(BuildContext context) async {
    await supabase.auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  // ─────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        drawer: _buildDrawer(context),
        appBar: AppBar(
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          title: const Text(''),
          centerTitle: true,
          actions: [
            _buildNotificationsButton(),
          ],
        ),
        body: const SafeArea(
          bottom: true,
          child: TabBarView(
            children: [
              EventsListScreen(),
              MyEventsScreen(),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Drawer
  // ─────────────────────────────────────────────

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),

            if (_profileLoading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  height: 56,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_profile != null)
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(userId: _profile!.id),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      _drawerAvatar(
                        (_profile!.avatarUrl ?? '').isNotEmpty
                            ? NetworkImage(_profile!.avatarUrl!)
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _profile!.nickname.isNotEmpty
                                  ? _profile!.nickname
                                  : 'Player',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppColors.charcoal,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: const [
                                Text(
                                  'View profile',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.untapPurple,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 12,
                                  color: AppColors.untapPurple,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),
            const Divider(),

            ListTile(
              leading: const Icon(Icons.settings, color: AppColors.coolGray),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              },
            ),


            ListTile(
              leading: const Icon(Icons.shield_outlined,
                color: AppColors.coolGray),
              title: const Text('Safety'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SafetyScreen(),
                  ),
                );
              },
            ),


            ListTile(
              leading: const Icon(Icons.info_outline, color: AppColors.coolGray),
              title: const Text('About'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AboutScreen(),
                  ),
                );
              },
            ),

            ListTile(
              leading: const Icon(Icons.handyman_outlined,
                color: AppColors.coolGray),
              title: const Text('Support'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SupportScreen(),
                  ),
                );
              },
            ),

            const Spacer(),
            const Divider(),

            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.coolGray),
              title: const Text(
                'Log out',
                style: TextStyle(
                  color: AppColors.coolGray,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _logout(context);
              },
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _drawerAvatar(ImageProvider? avatar) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 56,
        height: 56,
        color: AppColors.softLavender,
        child: avatar != null
            ? Image(image: avatar, fit: BoxFit.cover)
            : const Icon(Icons.person, color: AppColors.depth, size: 28),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Notifications
  // ─────────────────────────────────────────────

  Widget _buildNotificationsButton() {
    return PopupMenuButton<Object?>(
      tooltip: 'Notifications',
      itemBuilder: (context) => <PopupMenuEntry<Object?>>[
        if (_notifications.isNotEmpty)
          PopupMenuItem<Object?>(
            enabled: false,
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _markAllRead();
                },
                child: const Text('Clear'),
              ),
            ),
          ),
        if (_notifications.isNotEmpty) const PopupMenuDivider(),
        if (_notifications.isEmpty)
          const PopupMenuItem<Object?>(
            enabled: false,
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('No notifications'),
            ),
          ),
        ..._notifications.map(
          (n) => PopupMenuItem<Object?>(
            value: n,
            child: ListTile(
              title: Text(n['title'] ?? 'New notification'),
              subtitle: n['body'] != null ? Text(n['body']) : null,
              onTap: () async {
                Navigator.pop(context);

                final eventId = n['event_id'];
                if (eventId == null) return;

                await _markOneRead(n['id']);
                final event = await EventService().getEvent(eventId);

                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EventDetailScreen(event: event),
                  ),
                );
              },
            ),
          ),
        ),
      ],
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Icon(Icons.notifications_outlined),
          ),
          if (_unreadCount > 0)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$_unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
