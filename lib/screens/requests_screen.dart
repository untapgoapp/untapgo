import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/event_service.dart';
import 'profile_screen.dart';
import 'event_detail_screen.dart';

/// 🔥 Overlay real (idéntica arquitectura que Attendees)
class RequestsOverlay extends StatelessWidget {
  final String eventId;

  const RequestsOverlay({super.key, required this.eventId});

  @override
  Widget build(BuildContext context) {
    debugPrint('REQUESTS OVERLAY BUILD');
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 🔥 Blur + tap to close
          UntapCircleButton(
            icon: Icons.close,
            onTap: () => Navigator.pop(context),
          ),

          // 🔥 Draggable sheet
          DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder: (context, controller) {
              return RequestsSheet(
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

/// 🔥 Sheet real
class RequestsSheet extends StatefulWidget {
  final String eventId;
  final ScrollController scrollController;

  const RequestsSheet({
    super.key,
    required this.eventId,
    required this.scrollController,
  });

  @override
  State<RequestsSheet> createState() => _RequestsSheetState();
}

class _RequestsSheetState extends State<RequestsSheet> {
  final EventService _svc = EventService();

  final Set<String> _processing = {};
  List<Map<String, dynamic>> _requests = [];

  bool _loading = true;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Map<String, String> _headers() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _loadRequests() async {
    try {
      final res = await http.get(
        Uri.parse(
          '${EventService.backendBaseUrl}/events/${widget.eventId}/requests',
        ),
        headers: _headers(),
      );

      if (res.statusCode != 200) {
        throw Exception(res.body);
      }

      final data = jsonDecode(res.body) as List<dynamic>;
      _requests = data.cast<Map<String, dynamic>>();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _accept(String userId) async {
    if (_processing.contains(userId)) return;
    setState(() => _processing.add(userId));

    try {
      await _svc.acceptEventRequest(
        eventId: widget.eventId,
        userId: userId,
      );
      _requests.removeWhere((r) => _reqUserId(r) == userId);
      _changed = true;
    } catch (e) {
      _snack(e.toString());
    }

    _processing.remove(userId);
    if (mounted) setState(() {});
  }

  Future<void> _reject(String userId) async {
    if (_processing.contains(userId)) return;
    setState(() => _processing.add(userId));

    try {
      await _svc.rejectEventRequest(
        eventId: widget.eventId,
        userId: userId,
      );
      _requests.removeWhere((r) => _reqUserId(r) == userId);
      _changed = true;
    } catch (e) {
      _snack(e.toString());
    }

    _processing.remove(userId);
    if (mounted) setState(() {});
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg.replaceFirst('Exception: ', '')),
        backgroundColor: Colors.grey.shade900,
      ),
    );
  }

  String? _reqUserId(Map<String, dynamic> r) {
    final v = (r['user_id'] ?? r['id']);
    return v?.toString();
  }

  String _nickname(Map<String, dynamic> r) {
    final v = (r['nickname'] ?? '').toString().trim();
    return v.isEmpty ? 'Player' : v;
  }

  void _openProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Spacer(),
                const Text(
                  'Join Requests',
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
                      onTap: () => Navigator.pop(context, _changed),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _requests.isEmpty
                        ? const Center(
                            child: Text('No pending requests'),
                          )
                        : ListView.builder(
                            controller: widget.scrollController,
                            itemCount: _requests.length,
                            itemBuilder: (context, index) {
                              final r = _requests[index];
                              final userId = _reqUserId(r);
                              if (userId == null) {
                                return const SizedBox.shrink();
                              }

                              final nickname = _nickname(r);
                              final busy =
                                  _processing.contains(userId);

                              return ListTile(
                                title: Text(nickname),
                                onTap: () =>
                                    _openProfile(userId),
                                trailing: Row(
                                  mainAxisSize:
                                      MainAxisSize.min,
                                  children: [
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () =>
                                              _reject(userId),
                                      child:
                                          const Text('Decline'),
                                    ),
                                    ElevatedButton(
                                      onPressed: busy
                                          ? null
                                          : () =>
                                              _accept(userId),
                                      child:
                                          const Text('Approve'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

