import 'package:flutter/material.dart';

class EventCountdownBanner extends StatelessWidget {
  final DateTime startsAt;

  const EventCountdownBanner({
    super.key,
    required this.startsAt,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = startsAt.toLocal().difference(now);

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
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Color(0xFFFFE082), // amarillo suave arriba
          Color(0xFFFFD54F), // amarillo principal
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.bolt,
          size: 18,
          color: Colors.black87,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
      ],
    ),
  );
  }
}