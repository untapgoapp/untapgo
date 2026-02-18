import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/event_service.dart';
import 'profile_screen.dart';

class RequestsScreen extends StatefulWidget {
  final String eventId;

  const RequestsScreen({super.key, required this.eventId});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  final EventService _svc = EventService();

  final Set<String> _processing = {}; // per-user guard
  bool _loading = true;
  String? _error;

  bool _changed = false; // ✅ tells caller to refresh counts
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  // ─────────────────────────────────────────────────────────────
  // Data
  // ─────────────────────────────────────────────────────────────

  Map<String, String> _headers() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _loadRequests() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await http.get(
        Uri.parse('${EventService.backendBaseUrl}/events/${widget.eventId}/requests'),
        headers: _headers(),
      );

      if (res.statusCode != 200) {
        throw Exception(res.body);
      }

      final data = jsonDecode(res.body) as List<dynamic>;
      final rows = data.cast<Map<String, dynamic>>();

      if (!mounted) return;
      setState(() => _requests = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Actions
  // ─────────────────────────────────────────────────────────────

  Future<void> _accept(String userId) async {
    if (_processing.contains(userId)) return;

    setState(() => _processing.add(userId));

    try {
      await _svc.acceptEventRequest(eventId: widget.eventId, userId: userId);

      _requests.removeWhere((r) => (_reqUserId(r) == userId));
      _changed = true;

      if (mounted) setState(() {});
    } catch (e) {
      _snack(e.toString());
    } finally {
      _processing.remove(userId);
      if (mounted) setState(() {});
    }
  }

  Future<void> _reject(String userId) async {
    if (_processing.contains(userId)) return;

    setState(() => _processing.add(userId));

    try {
      await _svc.rejectEventRequest(eventId: widget.eventId, userId: userId);

      _requests.removeWhere((r) => (_reqUserId(r) == userId));
      _changed = true;

      if (mounted) setState(() {});
    } catch (e) {
      _snack(e.toString());
    } finally {
      _processing.remove(userId);
      if (mounted) setState(() {});
    }
  }

  // ─────────────────────────────────────────────────────────────
  // UI helpers
  // ─────────────────────────────────────────────────────────────

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg.replaceFirst('Exception: ', '')),
        backgroundColor: Colors.grey.shade900,
      ),
    );
  }

  void _openProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)),
    );
  }

  String _initials(String name) {
    final s = name.trim();
    if (s.isEmpty) return '?';
    return s[0].toUpperCase();
  }

  String? _reqUserId(Map<String, dynamic> r) {
    final v = (r['user_id'] ?? r['id']);
    if (v == null) return null;
    return v.toString();
  }

  String _nickname(Map<String, dynamic> r) {
    final v = (r['nickname'] ?? '').toString().trim();
    return v.isEmpty ? 'Player' : v;
  }

  // ─────────────────────────────────────────────────────────────
  // Widgets
  // ─────────────────────────────────────────────────────────────

  Widget _requestTile(Map<String, dynamic> r) {
    final userId = _reqUserId(r);
    if (userId == null) return const SizedBox.shrink();

    final nickname = _nickname(r);
    final busy = _processing.contains(userId);

    final primary = Theme.of(context).colorScheme.primary;

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: ListTile(
        leading: GestureDetector(
          onTap: () => _openProfile(userId),
          child: CircleAvatar(child: Text(_initials(nickname))),
        ),
        title: Text(nickname),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Accept',
              icon: Icon(Icons.check, color: primary),
              onPressed: busy ? null : () => _accept(userId),
            ),
            IconButton(
              tooltip: 'Reject',
              icon: Icon(Icons.close, color: primary),
              onPressed: busy ? null : () => _reject(userId),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Text(_error!))
            : _requests.isEmpty
                ? const Center(
                    child: Text(
                      'No pending requests.',
                      style: TextStyle(fontSize: 16),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadRequests,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: _requests.length,
                      itemBuilder: (context, index) => _requestTile(_requests[index]),
                    ),
                  );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Requests'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, _changed),
        ),
      ),
      body: body,
    );
  }
}