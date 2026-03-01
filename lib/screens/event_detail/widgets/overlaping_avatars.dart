import 'package:flutter/material.dart';

class OverlappingAvatars extends StatelessWidget {
  final List<String?> avatarUrls;
  final int maxVisible;
  final double radius;
  final double overlap;

  const OverlappingAvatars({
    super.key,
    required this.avatarUrls,
    this.maxVisible = 4,
    this.radius = 18,
    this.overlap = 14,
  });

  @override
  Widget build(BuildContext context) {
    final visible = avatarUrls.take(maxVisible).toList();
    final remaining = avatarUrls.length - visible.length;

    return SizedBox(
      height: radius * 2,
      width: (visible.length * overlap) + radius * 2,
      child: Stack(
        children: [
          for (int i = 0; i < visible.length; i++)
            Positioned(
              left: i * overlap,
              child: _avatar(visible[i]),
            ),
          if (remaining > 0)
            Positioned(
              left: visible.length * overlap,
              child: _extraAvatar(remaining),
            ),
        ],
      ),
    );
  }

  Widget _avatar(String? url) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        image: url != null && url.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(url),
                fit: BoxFit.cover,
              )
            : null,
        color: Colors.grey.shade300,
      ),
      child: (url == null || url.isEmpty)
          ? const Icon(Icons.person, size: 18)
          : null,
    );
  }

  Widget _extraAvatar(int count) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey.shade800,
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        '+$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}