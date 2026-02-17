import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // puedes añadir snackbar si quieres
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ───────────────
          // HELP
          // ───────────────
          Text(
            'Help',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),

          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Report a bug'),
            onTap: () {
              _openUrl('mailto:untapgoapp@gmail.com');
            },
          ),

          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('Contact'),
            onTap: () {
              _openUrl('mailto:untapgoapp@gmail.com');
            },
          ),

          const SizedBox(height: 24),

          // ───────────────
          // SUPPORT THE APP
          // ───────────────
          Text(
            'Support UntapGo',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),

          ListTile(
            leading: const Icon(Icons.star_border),
            title: const Text('Rate UntapGo'),
            onTap: () {
              // TODO: add store link
            },
          ),

          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppColors.softLavender,
            ),
            child: ListTile(
              leading: const Icon(
                Icons.auto_awesome,
                color: AppColors.untapPurple,
              ),
              title: const Text(
                'Crack a Booster',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.untapPurple,
                ),
              ),
              subtitle: const Text('Support development'),
              onTap: () {
                _openUrl('https://ko-fi.com/untapgo');
              },
            ),
          ),

        ],
      ),
    );
  }
}
