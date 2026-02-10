import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'events_list_screen.dart';
import 'my_events_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';

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

  // ─────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // Escucha cambios de auth (móvil real necesita esto)
    _authSub = supabase.auth.onAuthStateChange.listen((_) {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null && _notifChannel == null) {
        _loadInitialNotifications(userId);
        _listenNotifications(userId);
      }
    });

    // Por si la sesión ya está lista (web / hot restart)
    final userId = supabase.auth.currentUser?.id;
    if (userId != null) {
      _loadInitialNotifications(userId);
      _listenNotifications(userId);
    }
  }

  @override
  void dispose() {
    _notifChannel?.unsubscribe();
    _authSub?.cancel();
    super.dispose();
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
        appBar: AppBar(
          title: const Text(''),
          actions: [
            // 🔔 Notifications
            PopupMenuButton<Object?>(
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
                    enabled: false,
                    child: ListTile(
                      title: Text(
                        n['payload']?['title'] ?? 'New notification',
                      ),
                      subtitle: n['payload']?['body'] != null
                          ? Text(n['payload']['body'])
                          : null,
                      onTap: () async {
                        Navigator.pop(context);
                        await _markOneRead(n['id']);
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
            ),

            // ☰ Menu
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'profile') {
                  final userId = supabase.auth.currentUser?.id;
                  if (userId == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(userId: userId),
                    ),
                  );
                }
                if (v == 'settings') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SettingsScreen(),
                    ),
                  );
                }
                if (v == 'logout') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Log out'),
                      content: const Text('Logging out?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Log out'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await _logout(context);
                  }
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'profile', child: Text('My profile')),
                PopupMenuItem(value: 'settings', child: Text('Settings')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'logout', child: Text('Log out')),
              ],
            ),
          ],
        ),
        body: const TabBarView(
          children: [
            EventsListScreen(),
            MyEventsScreen(),
          ],
        ),
      ),
    );
  }
}
