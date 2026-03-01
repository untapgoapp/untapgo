import 'package:flutter/material.dart';

class AttendeeCard extends StatelessWidget {
  final String userId;
  final String nickname;
  final String? avatarUrl;

  final bool isMe;
  final bool isHost;
  final Widget? trailing;
  final VoidCallback onTap;

  const AttendeeCard({
    super.key,
    required this.userId,
    required this.nickname,
    required this.avatarUrl,
    required this.isMe,
    required this.isHost,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial =
        (nickname.isNotEmpty ? nickname[0] : '?').toUpperCase();

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundImage:
                  (avatarUrl != null && avatarUrl!.isNotEmpty)
                      ? NetworkImage(avatarUrl!)
                      : null,
              child: (avatarUrl == null || avatarUrl!.isEmpty)
                  ? Text(initial)
                  : null,
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          nickname.isNotEmpty ? nickname : 'Player',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 6),
                        Text(
                          '(You)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.black54,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      if (isHost) ...[
                        const SizedBox(width: 6),
                        Text(
                          'Host',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}