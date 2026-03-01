import 'package:flutter/material.dart';

class StatusPill extends StatelessWidget {
  final String status;

  const StatusPill({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final s = status.trim();
    if (s.isEmpty) return const SizedBox.shrink();

    final lower = s.toLowerCase();

    final bg = lower == 'joined'
        ? Colors.green.withOpacity(0.12)
        : (lower == 'requested' || lower == 'pending')
            ? Colors.orange.withOpacity(0.12)
            : Colors.grey.withOpacity(0.12);

    final border = lower == 'joined'
        ? Colors.green.withOpacity(0.35)
        : (lower == 'requested' || lower == 'pending')
            ? Colors.orange.withOpacity(0.35)
            : Colors.grey.withOpacity(0.35);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        s,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}