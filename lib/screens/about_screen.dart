import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import 'legal_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  // What is UntapGo?
                  Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      childrenPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      leading: const Icon(Icons.info_outline),
                      title: const Text(
                        'What is UntapGo?',
                        style:
                            TextStyle(fontWeight: FontWeight.w600),
                      ),
                      children: const [
                        Padding(
                          padding:
                              EdgeInsets.only(bottom: 12),
                          child: Text(
                            'UntapGo helps players organize and discover in-person tabletop events. '
                            'Create games, join events, and connect with your local community.',
                            style: TextStyle(height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // How it works
                  Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      childrenPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      leading:
                          const Icon(Icons.play_circle_outline),
                      title: const Text(
                        'How it works',
                        style:
                            TextStyle(fontWeight: FontWeight.w600),
                      ),
                      children: const [
                        _HowItem(
                          title: 'Create an event',
                          description:
                              'Host a game by setting the location, format, and time.',
                        ),
                        _Separator(),
                        _HowItem(
                          title: 'Edit your event',
                          description:
                              'Update details, manage players, or cancel if needed.',
                        ),
                        _Separator(),
                        _HowItem(
                          title: 'Find events near you',
                          description:
                              'Browse and join events that fit your schedule.',
                        ),
                        _Separator(),
                        _HowItem(
                          title: 'Share your event',
                          description:
                              "Don't forget to share it with your community to fill your table.",
                        ),
                        SizedBox(height: 12),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Legal
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    leading:
                        const Icon(Icons.gavel_outlined),
                    title: const Text(
                      'Legal',
                      style:
                          TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const LegalScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Footer
            Padding(
              padding:
                  const EdgeInsets.only(bottom: 24, top: 8),
              child: Column(
                children: const [
                  Text(
                    'By players, for players.',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Built independently with 💜',
                    style: TextStyle(
                      color: AppColors.coolGray,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HowItem extends StatelessWidget {
  final String title;
  final String description;

  const _HowItem({
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 42, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style:
                const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style:
                const TextStyle(height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 20,
      thickness: 0.6,
      color: Colors.grey.withOpacity(0.25),
    );
  }
}
