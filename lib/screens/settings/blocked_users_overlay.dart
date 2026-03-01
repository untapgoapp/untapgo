import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/event_service.dart';
import '../event_detail_screen.dart'; // UntapCircleButton

/// 🔥 Overlay completo estilo UntapGo
class BlockedUsersOverlay extends StatelessWidget {
  const BlockedUsersOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [

          // 🔥 Blur + tap to close
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: 12,
                sigmaY: 12,
              ),
              child: Container(
                color: Colors.black.withOpacity(0.25),
              ),
            ),
          ),

          // 🔥 Draggable sheet
          DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (context, controller) {
              return BlockedUsersSheet(
                scrollController: controller,
              );
            },
          ),
        ],
      ),
    );
  }
}

class BlockedUsersSheet extends StatefulWidget {
  final ScrollController scrollController;

  const BlockedUsersSheet({
    super.key,
    required this.scrollController,
  });

  @override
  State<BlockedUsersSheet> createState() =>
      _BlockedUsersSheetState();
}

class _BlockedUsersSheetState
    extends State<BlockedUsersSheet> {
  List<Map<String, dynamic>> _blocked = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, String> _headers() {
    final token =
        Supabase.instance.client.auth.currentSession?.accessToken;

    return {
      'Content-Type': 'application/json',
      if (token != null)
        'Authorization': 'Bearer $token',
    };
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        Uri.parse(
          '${EventService.backendBaseUrl}/users/blocked',
        ),
        headers: _headers(),
      );

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        setState(() {
          _blocked =
              List<Map<String, dynamic>>.from(decoded);
        });
      }
    } catch (_) {
      // opcional: snackbar
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<bool> _confirmUnblock() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unblock user?'),
        content: const Text(
          'This user will be able to interact with you again.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );

    return res == true;
  }

  Future<void> _unblock(String userId) async {
    final confirm = await _confirmUnblock();
    if (!confirm) return;

    try {
      await http.delete(
        Uri.parse(
          '${EventService.backendBaseUrl}/users/$userId/block',
        ),
        headers: _headers(),
      );

      await _load();
    } catch (_) {
      // opcional: snackbar
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(28),
      ),
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
              borderRadius:
                  BorderRadius.circular(2),
            ),
          ),

          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 20),
            child: Row(
              children: [
                const Spacer(),
                const Text(
                  'Blocked Users',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
                const Spacer(),
                UntapCircleButton(
                  icon: Icons.close,
                  onTap: () =>
                      Navigator.pop(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Expanded(
            child: _loading
                ? const Center(
                    child:
                        CircularProgressIndicator(),
                  )
                : _blocked.isEmpty
                    ? const Center(
                        child: Text(
                            'No blocked users'),
                      )
                    : ListView.separated(
                        controller:
                            widget.scrollController,
                        itemCount:
                            _blocked.length,
                        separatorBuilder:
                            (_, __) => Divider(
                          height: 1,
                          color: Colors.black
                              .withOpacity(0.05),
                        ),
                        itemBuilder:
                            (context, index) {
                          final user =
                              _blocked[index];

                          final id =
                              user['id']
                                  as String;
                          final nickname =
                              user['nickname']
                                      as String? ??
                                  'Player';
                          final avatarUrl =
                              user['avatar_url']
                                  as String?;

                          return ListTile(
                            leading:
                                CircleAvatar(
                              backgroundImage:
                                  avatarUrl !=
                                          null
                                      ? NetworkImage(
                                          avatarUrl)
                                      : null,
                              child: avatarUrl ==
                                      null
                                  ? Text(
                                      nickname
                                              .isNotEmpty
                                          ? nickname[0]
                                              .toUpperCase()
                                          : '?',
                                    )
                                  : null,
                            ),
                            title:
                                Text(nickname),
                            trailing:
                                TextButton(
                              onPressed: () =>
                                  _unblock(id),
                              child: const Text(
                                  'Unblock'),
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