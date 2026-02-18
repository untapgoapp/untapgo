import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class SafetyScreen extends StatelessWidget {
  const SafetyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety'),
      ),
      body: SafeArea(
        bottom: true,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ─────────────────────────
            // Header
            // ─────────────────────────
            Text(
              'Stay safe while you play.',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'UntapGo connects real players in real places. '
              'These simple guidelines help keep events welcoming and safe.',
              style: TextStyle(
                color: Colors.grey.shade700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),

            // ─────────────────────────
            // Guidelines
            // ─────────────────────────
            const _SafetyCard(
              icon: Icons.storefront_outlined,
              title: 'Choose public venues',
              description:
                  'Prefer game stores, cafés, or other public locations. '
                  'Avoid hosting events at your home when meeting new players.',
            ),
            const _SafetyCard(
              icon: Icons.rule_outlined,
              title: 'Respect venue rules',
              description:
                  'Follow the policies of the location hosting the event.',
            ),
            const _SafetyCard(
              icon: Icons.lock_outline,
              title: 'Protect your information',
              description:
                  'Avoid sharing sensitive personal details with people you do not know well.',
            ),
            const _SafetyCard(
              icon: Icons.report_problem_outlined,
              title: 'Report misconduct',
              description:
                  'If someone behaves inappropriately, contact us through the Support section.',
            ),

            const SizedBox(height: 24),

            // ─────────────────────────
            // Emergency
            // ─────────────────────────
            Container(
              margin: const EdgeInsets.only(bottom: 18),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.coolGray.withOpacity(0.3),
                ),
                color: Colors.transparent,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(
                    Icons.phone_in_talk_outlined,
                    size: 22,
                    color: AppColors.coolGray,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'If you ever feel unsafe, contact local emergency services immediately.',
                      style: TextStyle(
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // ─────────────────────────
            // Disclaimer
            // ─────────────────────────
            const Text(
              'UntapGo does not verify users and is not responsible for interactions between players. '
              'Users participate in events at their own discretion.',
              style: TextStyle(
                color: AppColors.coolGray,
                fontSize: 12,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SafetyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _SafetyCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.softLavender.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 22,
            color: AppColors.depth,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
