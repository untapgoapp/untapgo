import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/event.dart';
import '../services/event_service.dart';
import 'attendees_screen.dart';
import 'event_detail_screen.dart';

class MyEventsScreen extends StatefulWidget {
  const MyEventsScreen({super.key});

  @override
  State<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends State<MyEventsScreen>
    with SingleTickerProviderStateMixin {
  final EventService _service = EventService();
  late Future<List<Event>> _future;
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _future = _service.fetchMyEvents(); // GET /events/mine
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _future = _service.fetchMyEvents());
    await _future;
  }

  // ---------------------------
  // Status logic (FINAL)
  // ---------------------------

  String _normStatus(String? s) => (s ?? '').trim().toLowerCase();

  bool _isUpcoming(Event e) {
    final s = _normStatus(e.status);
    return s == 'open' || s == 'full' || s == 'started';
  }

  bool _isHistory(Event e) {
    final s = _normStatus(e.status);
    return s == 'ended';
  }

  // ---------------------------
  // Navigation
  // ---------------------------

  Future<void> _openEvent(Event e) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EventDetailScreen(event: e)),
    );

    if (changed == true && mounted) {
      await _reload();
    }
  }

  Future<void> _openAttendees(String eventId) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AttendeesScreen(eventId: eventId)),
    );

    if (mounted) {
      await _reload();
    }
  }

  String _prettyError(Object err) {
    final s = err.toString();
    if (s.contains('PGRST203')) {
      return "Backend function overload (PGRST203). Your /events/mine route must call the right RPC explicitly.";
    }
    if (s.length > 180) return s.substring(0, 180);
    return s;
  }

  // ---------------------------
  // UI
  // ---------------------------

  @override
  Widget build(BuildContext context) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) {
      return const Center(child: Text('No active session'));
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: _Header(title: 'My Events'),
          ),
          TabBar(
            controller: _tab,
            tabs: const [
              Tab(text: 'Upcoming'),
              Tab(text: 'History'),
            ],
          ),
          Expanded(
            child: FutureBuilder<List<Event>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  final msg = _prettyError(snapshot.error!);
                  return RefreshIndicator(
                    onRefresh: _reload,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        const SizedBox(height: 120),
                        Center(child: Text('Error: $msg')),
                        const SizedBox(height: 12),
                        const Center(child: Text('Pull down to retry')),
                      ],
                    ),
                  );
                }

                final mine = snapshot.data ?? const <Event>[];

                final upcoming = mine.where(_isUpcoming).toList();
                final history = mine.where(_isHistory).toList();

                // Order: Upcoming soonest first, History newest first
                upcoming.sort((a, b) => a.startsAt.compareTo(b.startsAt));
                history.sort((a, b) => b.startsAt.compareTo(a.startsAt));

                Widget buildList(List<Event> items, String emptyText) {
                  if (items.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: [
                          const SizedBox(height: 120),
                          Center(child: Text(emptyText)),
                          const SizedBox(height: 12),
                          const Center(child: Text('Pull down to refresh')),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: _reload,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final e = items[i];

                        return ListTile(
                          title: Text(e.title),
                          subtitle: Text(e.status),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${e.playerCount}/${e.maxPlayers}'),
                              IconButton(
                                icon: const Icon(Icons.group_outlined),
                                tooltip: 'Attendees',
                                onPressed: () => _openAttendees(e.id),
                              ),
                            ],
                          ),
                          onTap: () => _openEvent(e),
                        );
                      },
                    ),
                  );
                }

                return TabBarView(
                  controller: _tab,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    buildList(upcoming, 'You have no upcoming events'),
                    buildList(history, 'You have no past events'),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  const _Header({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }
}
