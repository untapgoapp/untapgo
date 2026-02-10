import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/event.dart';
import '../screens/create_event_screen.dart';
import '../screens/event_detail_screen.dart';
import '../services/event_service.dart';
import '../services/settings_store.dart';

class EventsListScreen extends StatefulWidget {
  const EventsListScreen({super.key});

  @override
  State<EventsListScreen> createState() => _EventsListScreenState();
}

class _EventsListScreenState extends State<EventsListScreen>
    with SingleTickerProviderStateMixin {
  final EventService _service = EventService();

  late final TabController _tabController;

  List<Event> _allSorted = const [];
  List<Event> _nearbySorted = const [];

  bool _checkingLocation = false;
  LocationPermission? _permission;
  Position? _position;
  bool? _locationServicesEnabled;

  bool _didLoadAll = false;
  bool _didLoadNearby = false;

  static const int _nearbyRadiusKm = 50;

  Timer? _autoRefreshTimer;
  static const Duration _autoRefreshInterval = Duration(seconds: 30);

  StreamSubscription<AuthState>? _authSub;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<Event> _filterActive(List<Event> events) {
    return events
        .where((e) =>
            e.status == 'Open' || e.status == 'Full' || e.status == 'Started')
        .toList();
  }

  int _statusRank(String status) {
    switch (status) {
      case 'Open':
        return 0;
      case 'Full':
        return 1;
      case 'Started':
        return 2;
      default:
        return 9;
    }
  }

  int _compareStarts(Event a, Event b) {
    final aBad = a.startsAt.year <= 1971;
    final bBad = b.startsAt.year <= 1971;
    if (aBad != bBad) return aBad ? 1 : -1;
    return a.startsAt.compareTo(b.startsAt);
  }

  int _compareAll(Event a, Event b) {
    final s = _statusRank(a.status).compareTo(_statusRank(b.status));
    if (s != 0) return s;

    final t = _compareStarts(a, b);
    if (t != 0) return t;

    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  double _distanceKm(Event e, Position? pos) {
    if (e.distanceKm != null) return e.distanceKm!;
    if (pos == null || e.lat == null || e.lng == null) {
      return double.infinity;
    }

    return Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          e.lat!,
          e.lng!,
        ) /
        1000.0;
  }

  int _compareNearby(Event a, Event b, Position? pos) {
    final da = _distanceKm(a, pos);
    final db = _distanceKm(b, pos);
    if (da != db) return da.compareTo(db);
    return _compareAll(a, b);
  }

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this);

    _authSub =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      if (!mounted) return;
      if (data.session == null) return;

      await _reloadAll(showErrors: false);

      if (_position != null) {
        await _reloadNearby(showErrors: false);
        await _reloadAll(showErrors: false);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _reloadAll(showErrors: false);
      await _ensureLocationForNearby();
      if (_position != null) {
        await _reloadNearby(showErrors: false);
        await _reloadAll(showErrors: false);
      }
      _startAutoRefresh();
    });

    SettingsStore.sortByDistance.addListener(_resortAllIfPossible);
    SettingsStore.distanceUnit.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _authSub?.cancel();
    SettingsStore.sortByDistance.removeListener(_resortAllIfPossible);
    _tabController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer =
        Timer.periodic(_autoRefreshInterval, (_) => _refreshActiveTab());
  }

  Future<void> _refreshActiveTab() async {
    if (_tabController.index == 0) {
      if (_position == null) {
        await _ensureLocationForNearby();
        if (_position != null) {
          await _reloadNearby(showErrors: false);
          await _reloadAll(showErrors: false);
        }
        return;
      }
      await _reloadNearby(showErrors: false);
    } else {
      await _reloadAll(showErrors: false);
    }
  }

  void _resortAllIfPossible() {
    if (_allSorted.isEmpty || _position == null) return;

    final sorted = List<Event>.from(_allSorted);
    if (SettingsStore.currentSortByDistance) {
      sorted.sort((a, b) => _compareNearby(a, b, _position));
    } else {
      sorted.sort(_compareAll);
    }

    setState(() => _allSorted = sorted);
  }

  Future<void> _reloadAll({bool showErrors = true}) async {
    try {
      final data = await _service.fetchEvents(
        lat: _position?.latitude,
        lng: _position?.longitude,
      );

      final active = _filterActive(data);
      final sorted = List<Event>.from(active);

      if (SettingsStore.currentSortByDistance && _position != null) {
        sorted.sort((a, b) => _compareNearby(a, b, _position));
      } else {
        sorted.sort(_compareAll);
      }

      if (!mounted) return;
      setState(() {
        _allSorted = sorted;
        _didLoadAll = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _didLoadAll = true);
      if (showErrors) _snack("Couldn't load events. Pull to refresh.");
    }
  }

  Future<void> _reloadNearby({bool showErrors = true}) async {
    if (_position == null) return;

    try {
      final data = await _service.fetchNearbyEvents(
        lat: _position!.latitude,
        lng: _position!.longitude,
        radiusKm: _nearbyRadiusKm,
      );

      final sorted = _filterActive(data)
        ..sort((a, b) => _compareNearby(a, b, _position));

      if (!mounted) return;
      setState(() {
        _nearbySorted = sorted;
        _didLoadNearby = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _didLoadNearby = true);
      if (showErrors) _snack("Couldn't load nearby events. Pull to refresh.");
    }
  }

  Future<void> _ensureLocationForNearby() async {
    if (_checkingLocation) return;
    if (!mounted) return;

    // ZIP MODE: use stored lat/lng, do NOT touch GPS
    if (SettingsStore.isUsingZip && SettingsStore.hasLocation) {
      setState(() {
        _position = Position(
          latitude: SettingsStore.currentLat!,
          longitude: SettingsStore.currentLng!,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
      });
      return;
    }

    setState(() => _checkingLocation = true);

    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return;

      setState(() => _locationServicesEnabled = enabled);

      if (!enabled) {
        setState(() => _position = null);
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      if (!mounted) return;
      setState(() => _permission = perm);

      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        setState(() => _position = null);
        return;
      }

      Position? pos;

      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 3),
        );
      } catch (_) {
        try {
          pos = await Geolocator.getLastKnownPosition();
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() => _position = pos);
    } finally {
      if (mounted) setState(() => _checkingLocation = false);
    }
  }

  Future<void> _openCreateEvent(BuildContext context) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateEventScreen()),
    );

    if (created == true) {
      await _refreshActiveTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16, right: 4),
        child: FloatingActionButton(
          onPressed: () => _openCreateEvent(context),
          backgroundColor: Theme.of(context).colorScheme.primary,
          shape: const CircleBorder(),
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Events',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Nearby'),
                Tab(text: 'All'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _eventsList(
                    events: _nearbySorted,
                    onRefresh: () async {
                      await _ensureLocationForNearby();
                      if (_position != null) {
                        await _reloadNearby();
                        await _reloadAll();
                      }
                    },
                    isNearby: true,
                  ),
                  _eventsList(
                    events: _allSorted,
                    onRefresh: () => _reloadAll(),
                    isNearby: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _eventsList({
    required List<Event> events,
    required Future<void> Function() onRefresh,
    required bool isNearby,
  }) {
    // ZIP selected but no coordinates available
    if (isNearby &&
        SettingsStore.isUsingZip &&
        !SettingsStore.hasLocation) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: [
            const SizedBox(height: 140),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Text(
                    'ZIP location not set',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pushNamed('/settings');
                    },
                    child: const Text('Change location'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ); 
    }
    // ZIP MODE: only show CTA if NOT using ZIP
    if (isNearby && _position == null && !SettingsStore.isUsingZip) {
      final perm = _permission;
      final servicesEnabled = _locationServicesEnabled;

      String title = 'Enable location to see nearby events';
      String buttonText = 'Enable location';

      VoidCallback? action = _checkingLocation
          ? null
          : () async {
              await _ensureLocationForNearby();
              if (_position != null) {
                await _reloadNearby();
                await _reloadAll();
              }
            };

      if (servicesEnabled == false) {
        title = 'Turn on Location Services to see nearby events';
        buttonText = 'Open Location Settings';
        action = () async {
          await Geolocator.openLocationSettings();
        };
      } else if (perm == LocationPermission.deniedForever) {
        title = 'Location permission is blocked in Settings';
        buttonText = 'Open Settings';
        action = () async {
          await Geolocator.openAppSettings();
        };
      }

      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: [
            const SizedBox(height: 140),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Text(title, textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  OutlinedButton(
                    onPressed: action,
                    child: Text(buttonText),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (!isNearby && !_didLoadAll) {
      return const Center(child: CircularProgressIndicator());
    }

    if (isNearby && _position != null && !_didLoadNearby) {
      return const Center(child: CircularProgressIndicator());
    }

    if (events.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text('No events')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        itemCount: events.length,
        itemBuilder: (_, i) => _EventCard(
          event: events[i],
          userPosition: _position,
          onBackRefresh: onRefresh,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// EVENT CARD (ALINEADA, MISMO DISEÑO)
// ─────────────────────────────────────────────────────────────

class _EventCard extends StatelessWidget {
  final Event event;
  final Position? userPosition;
  final Future<void> Function() onBackRefresh;

  const _EventCard({
    required this.event,
    required this.userPosition,
    required this.onBackRefresh,
  });

  static const double _rowH = 24;
  static const double _iconW = 22;
  static const double _rightColW = 120;

  String get _myStatus => (event.myStatus ?? '').trim().toLowerCase();

  bool get _isJoined =>
      _myStatus.isNotEmpty ? _myStatus == 'joined' : event.isJoined;

  bool get _isRequested =>
      _myStatus.contains('pend') || _myStatus.contains('request');

  bool get _isKicked => _myStatus == 'kicked';
  bool get _isRejected => _myStatus == 'rejected';

  bool get _isOpen => event.status.trim() == 'Open';
  bool get _isFull => event.status.trim() == 'Full';

  String _formatLabel() {
    final slug = (event.formatSlug ?? '').trim().toLowerCase();
    if (slug.isNotEmpty) {
      return slug[0].toUpperCase() + slug.substring(1);
    }
    return (event.format ?? 'Other').trim();
  }

  String _cityStateFromAddress() {
    final raw = (event.addressText ?? '').trim();
    if (raw.isEmpty) return '';
    final parts = raw.split(',').map((s) => s.trim()).toList();
    if (parts.length >= 3) {
      return '${parts[1]}, ${parts[2]}';
    }
    if (parts.length == 2) {
      return '${parts[0]}, ${parts[1]}';
    }
    return raw;
  }

  double _distanceKm() {
    if (event.distanceKm != null) return event.distanceKm!;
    if (userPosition == null || event.lat == null || event.lng == null) {
      return double.infinity;
    }
    return Geolocator.distanceBetween(
          userPosition!.latitude,
          userPosition!.longitude,
          event.lat!,
          event.lng!,
        ) /
        1000.0;
  }

  String _distanceLabel(double km) {
    if (!km.isFinite || km == double.infinity) return '';
    final unit = SettingsStore.distanceUnit.value;
    final useMiles = unit == DistanceUnit.mi;
    return useMiles
        ? '~${(km * 0.621371).toStringAsFixed(1)} mi'
        : '~${km.toStringAsFixed(1)} km';
  }

  Widget _pill(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.surfaceVariant,
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }

  Widget _metaRow(IconData icon, String text) {
    return SizedBox(
      height: _rowH,
      child: Row(
        children: [
          SizedBox(width: _iconW, child: Icon(icon, size: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _rightSlot(Widget? child) {
    if (child == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final host =
        event.hostNickname.trim().isEmpty ? 'Unknown' : event.hostNickname;
    final fmt = _formatLabel();
    final when = event.startsLabel();
    final where = _cityStateFromAddress();
    final players = '${event.attendeesCount}/${event.maxPlayers}';
    final dist = _distanceLabel(_distanceKm());

    Widget? personal;
    if (_isJoined) personal = _pill(context, 'Joined');
    else if (_isRequested) personal = _pill(context, 'Requested');
    else if (_isKicked) personal = _pill(context, 'Kicked');
    else if (_isRejected) personal = _pill(context, 'Rejected');

    Widget? status;
    if (_isOpen) status = _pill(context, 'Open');
    else if (_isFull) status = _pill(context, 'Full');

    return InkWell(
      onTap: () async {
        final changed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
        );
        if (changed == true) await onBackRefresh();
      },
      child: Card(
        margin: const EdgeInsets.all(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _metaRow(Icons.person_outline, host),
                        _metaRow(Icons.style_outlined, fmt),
                        _metaRow(Icons.schedule, when),
                        if (where.isNotEmpty)
                          _metaRow(Icons.place_outlined, where),
                      ],
                    ),
                  ),
                  const SizedBox(width: _rightColW),
                ],
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: SizedBox(
                  width: _rightColW,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (personal != null) _rightSlot(personal),
                      if (status != null) _rightSlot(status),
                      _rightSlot(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.people_outline, size: 16),
                            const SizedBox(width: 4),
                            Text(players,
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                      if (dist.isNotEmpty)
                        _rightSlot(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.near_me_outlined, size: 16),
                              const SizedBox(width: 4),
                              Text(dist),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
