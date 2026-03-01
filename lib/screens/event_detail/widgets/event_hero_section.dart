import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../models/event.dart';

class EventHeroSection extends StatelessWidget {
  final Event event;
  final VoidCallback onBack;
  final VoidCallback onShare;
  final VoidCallback onWatchlist;
  final VoidCallback? onEdit;
  final bool showEdit;

  const EventHeroSection({
    super.key,
    required this.event,
    required this.onBack,
    required this.onShare,
    required this.onWatchlist,
    required this.onEdit,
    required this.showEdit,
  });

  String _coverForFormat(String? slug) {
    switch ((slug ?? '').toLowerCase()) {
      case 'modern':
        return 'assets/covers/modern.jpg';
      case 'standard':
        return 'assets/covers/standard.jpg';
      case 'commander':
        return 'assets/covers/commander.png';
      default:
        return 'assets/covers/commander.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cover = _coverForFormat(event.formatSlug);

    return SizedBox(
      height: 260,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            cover,
            fit: BoxFit.cover,
          ),

          // Gradient fade
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.35),
                ],
              ),
            ),
          ),

          // Top controls
          Positioned(
            top: 48,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _glassIconButton(Icons.arrow_back_ios_new_rounded, onBack),
                Row(
                  children: [
                    _glassIconButton(
                        Icons.bookmark_border_rounded, onWatchlist),
                    const SizedBox(width: 8),
                    _glassIconButton(Icons.ios_share_rounded, onShare),
                    if (showEdit) ...[
                      const SizedBox(width: 8),
                      _glassIconButton(Icons.edit_outlined, onEdit!),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Title block
          Positioned(
            left: 20,
            right: 20,
            bottom: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                if (event.hostNickname != null &&
                    event.hostNickname!.isNotEmpty)
                  Text(
                    "Hosted by ${event.hostNickname}",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassIconButton(IconData icon, VoidCallback onTap) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Material(
          color: Colors.black.withValues(alpha: 0.28),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                icon,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}