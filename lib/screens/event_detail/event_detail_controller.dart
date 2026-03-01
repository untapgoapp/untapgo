import 'dart:async';
import '../../models/event.dart';
import '../../services/event_service.dart';

class EventDetailController {
  Event event;
  final EventService svc;

  bool busy = false;
  String? error;

  DateTime? _joinCooldownUntil;
  int _joinCooldownTotalSecs = 0;
  Timer? _joinCooldownTimer;

  EventDetailController({
    required this.event,
    required this.svc,
  });

  void dispose() {
    _joinCooldownTimer?.cancel();
  }

  // ─────────────────────────────────────────
  // Cooldown
  // ─────────────────────────────────────────

  bool get inJoinCooldown =>
      _joinCooldownUntil != null &&
      DateTime.now().isBefore(_joinCooldownUntil!);

  int get joinCooldownSecs {
    if (!inJoinCooldown) return 0;
    return _joinCooldownUntil!
            .difference(DateTime.now())
            .inSeconds +
        1;
  }

  int get joinCooldownTotalSecs => _joinCooldownTotalSecs;

  void _startJoinCooldown(int seconds) {
    final now = DateTime.now();
    _joinCooldownUntil = now.add(Duration(seconds: seconds));
    _joinCooldownTotalSecs = seconds;

    _joinCooldownTimer?.cancel();
    _joinCooldownTimer =
        Timer.periodic(const Duration(seconds: 1), (t) {
      if (!inJoinCooldown) {
        t.cancel();
      }
    });
  }

  int? _cooldownSecondsFromError(Object e) {
    final raw = e.toString();

    final m1 = RegExp(r'seconds=(\d+)').firstMatch(raw);
    final m2 =
        RegExp(r'cooldown_seconds["=: ]+(\d+)').firstMatch(raw);

    final match = m1 ?? m2;
    if (match == null) return null;

    final s = int.tryParse(match.group(1) ?? '');
    if (s == null || s <= 0) return null;
    return s;
  }

  // ─────────────────────────────────────────
  // Actions
  // ─────────────────────────────────────────

  Future<void> join() async {
    if (busy) return;

    busy = true;
    error = null;

    try {
      await svc.joinEvent(event.id);
    } catch (e) {
      final secs = _cooldownSecondsFromError(e);
      if (secs != null) {
        _startJoinCooldown(secs);
      }

      error = _humanizeError(e);
      rethrow;
    } finally {
      busy = false;
    }
  }

  Future<void> leave() async {
    if (busy) return;

    busy = true;
    error = null;

    try {
      await svc.leaveEvent(event.id);
    } catch (e) {
      error = _humanizeError(e);
      rethrow;
    } finally {
      busy = false;
    }
  }

  Future<void> cancelEvent() async {
    if (busy) return;

    busy = true;
    error = null;

    try {
      await svc.cancelEvent(event.id);
    } catch (e) {
      error = _humanizeError(e);
      rethrow;
    } finally {
      busy = false;
    }
  }

  String _humanizeError(Object e) {
    final raw = e.toString();

    if (raw.contains('KICK_COOLDOWN_ACTIVE') ||
        raw.contains('JOIN_COOLDOWN_ACTIVE')) {
      final m1 = RegExp(r'seconds=(\d+)').firstMatch(raw);
      final m2 =
          RegExp(r'cooldown_seconds["=: ]+(\d+)').firstMatch(raw);

      final match = m1 ?? m2;
      if (match != null) {
        final mins =
            (int.parse(match.group(1)!) / 60).ceil();
        return 'You phased out. Try to rejoin in $mins minutes';
      }
      return 'You phased out. Try to rejoin later';
    }

    return raw.replaceFirst('Exception: ', '');
  }
}