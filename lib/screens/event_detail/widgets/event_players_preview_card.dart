import 'package:flutter/material.dart';

class EventPlayersPreviewCard extends StatelessWidget {
  final int attendeesCount;
  final int maxPlayers;
  final List<Map<String, dynamic>> attendeesPreview;
  final bool loading;
  final VoidCallback onSeeAll;

  const EventPlayersPreviewCard({
    super.key,
    required this.attendeesCount,
    required this.maxPlayers,
    required this.attendeesPreview,
    required this.loading,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onSeeAll,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            /// Header
            Row(
              children: [
                Text(
                  'Players',
                  style: theme.textTheme.titleMedium,
                ),

                const Spacer(),

                Text(
                  '$attendeesCount/$maxPlayers',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(width: 12),

                Row(
                  children: [
                    Text(
                      'See all',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),

            if (loading)
              const LinearProgressIndicator(minHeight: 2)
            else
              SizedBox(
                height: 52,
                child: Stack(
                  children: [
                    for (int i = 0;
                        i < attendeesPreview.length && i < 4;
                        i++)
                      Positioned(
                        left: i * 30,
                        child: _avatar(
                          attendeesPreview[i]['avatar_url'] as String?,
                        ),
                      ),

                    if (attendeesPreview.length > 4)
                      Positioned(
                        left: 4 * 30,
                        child: _extraAvatar(
                          attendeesPreview.length - 4,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(String? url) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        image: (url != null && url.isNotEmpty)
            ? DecorationImage(
                image: NetworkImage(url),
                fit: BoxFit.cover,
              )
            : null,
        color: Colors.grey.shade300,
      ),
      child: (url == null || url.isEmpty)
          ? const Icon(Icons.person, size: 22)
          : null,
    );
  }

  Widget _extraAvatar(int count) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey.shade800,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '+$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}