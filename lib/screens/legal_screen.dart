import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);

    if (!await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    )) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Legal'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [

          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text(
              'Privacy Policy',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            onTap: () => _openUrl(
              'https://untapgo.com/privacy.html',
            ),
          ),

          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text(
              'Terms of Use',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            onTap: () => _openUrl(
              'https://untapgo.com/terms.html',
            ),
          ),

          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text(
              'Liability Disclaimer',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            onTap: () => _openUrl(
              'https://untapgo.com/disclaimer.html',
            ),
          ),
        ],
      ),
    );
  }
}
