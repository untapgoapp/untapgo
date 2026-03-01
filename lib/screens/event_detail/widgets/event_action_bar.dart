import 'package:flutter/material.dart';
import '../../../models/event.dart';

class EventActionBar extends StatelessWidget {
  final Event event;
  final bool isHost;
  final bool isJoined;
  final bool isRequested;
  final bool isEventFull;
  final bool canLeave;
  final bool canJoin;
  final bool canCancelRequest;
  final bool canCancelEvent;
  final bool busy;
  final bool inJoinCooldown;
  final int joinCooldownSecs;
  final int joinCooldownTotalSecs;
  final String? error;

  final VoidCallback? onJoin;
  final VoidCallback? onLeave;
  final VoidCallback? onCancelRequest;
  final VoidCallback? onCancelEvent;

  const EventActionBar({
    super.key,
    required this.event,
    required this.isHost,
    required this.isJoined,
    required this.isRequested,
    required this.isEventFull,
    required this.canLeave,
    required this.canJoin,
    required this.canCancelRequest,
    required this.canCancelEvent,
    required this.busy,
    required this.inJoinCooldown,
    required this.joinCooldownSecs,
    required this.joinCooldownTotalSecs,
    required this.error,
    this.onJoin,
    this.onLeave,
    this.onCancelRequest,
    this.onCancelEvent,
  });

  @override
  Widget build(BuildContext context) {

    String primaryLabel;
    VoidCallback? primaryOnPressed;

    String? secondaryLabel;
    VoidCallback? secondaryOnPressed;

    if (isJoined) {
      primaryLabel = 'Leave';
      primaryOnPressed = busy || !canLeave ? null : onLeave;
    } else if (isRequested) {
      primaryLabel = inJoinCooldown
          ? 'Cancel request (${joinCooldownSecs}s)'
          : 'Cancel request';
      primaryOnPressed =
          busy || inJoinCooldown || !canCancelRequest ? null : onCancelRequest;
    } else if (isEventFull) {
      primaryLabel = 'No slots available';
      primaryOnPressed = null;
    } else {
      primaryLabel =
          inJoinCooldown ? 'Join (${joinCooldownSecs}s)' : 'Join';
      primaryOnPressed =
          busy || inJoinCooldown || !canJoin ? null : onJoin;
    }

    if (canCancelEvent) {
      secondaryLabel = 'Cancel event';
      secondaryOnPressed = busy ? null : onCancelEvent;
    }

    final showCooldownIndicator =
        inJoinCooldown && joinCooldownTotalSecs > 0;

    final progress = showCooldownIndicator
        ? (joinCooldownSecs / joinCooldownTotalSecs).clamp(0.0, 1.0)
        : 0.0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 14, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            if (error != null) ...[
              const SizedBox(height: 6),
              Text(
                error!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      elevation: 6,
                      shadowColor: Colors.black.withValues(alpha: 0.2),
                    ),
                    onPressed: primaryOnPressed,
                    child: Text(primaryLabel),
                  ),
                ),
                if (secondaryLabel != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.grey.shade400,
                        ),
                      ),
                      onPressed: secondaryOnPressed,
                      child: Text(secondaryLabel),
                    ),
                  ),
                ],
              ],
            ),
            if (showCooldownIndicator) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: progress,
                minHeight: 3,
              ),
            ],
          ],
        ),
      ),
    );
  }
}