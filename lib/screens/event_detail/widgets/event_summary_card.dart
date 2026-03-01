import 'package:flutter/material.dart';
import '../../../models/event.dart';

const Map<String, String> kFormatLabels = {
  'commander': 'Commander',
  'cube': 'Cube',
  'draft': 'Draft',
  'legacy': 'Legacy',
  'modern': 'Modern',
  'pauper': 'Pauper',
  'pioneer': 'Pioneer',
  'premodern': 'Premodern',
  'sealed': 'Sealed',
  'standard': 'Standard',
  'vintage': 'Vintage',
  'other': 'Other',
};

class EventSummaryCard extends StatelessWidget {
  final Event event;
  final VoidCallback? onLocationTap;

  const EventSummaryCard({
    super.key,
    required this.event,
    this.onLocationTap,
  });

  String? _proxiesLabel(String? rawValue) {
    final raw = (rawValue ?? '').toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return null;

    switch (raw) {
      case 'Yes':
        return 'Allowed';
      case 'No':
        return 'Not allowed';
      case 'Ask':
        return 'Ask host';
      default:
        return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hostName =
        event.hostNickname.trim().isEmpty ? 'Unknown' : event.hostNickname;

    final addr = (event.addressText ?? '').trim();
    final proxiesLabel = _proxiesLabel(event.proxies);

    final slug = (event.formatSlug ?? '').trim().toLowerCase();
    final fmtLabel = slug.isEmpty ? null : (kFormatLabels[slug] ?? slug);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _infoRow(
              context,
              icon: Icons.flag_outlined,
              title: 'Status',
              value: event.status,
            ),
            _infoRow(
              context,
              icon: Icons.person_outline,
              title: 'Host',
              value: hostName,
            ),
            _infoRow(
              context,
              icon: Icons.schedule,
              title: 'Starts',
              value: event.startsLabel(),
            ),
            _infoRow(
              context,
              icon: Icons.style_outlined,
              title: 'Format',
              value: fmtLabel ?? 'Other',
            ),
            if (proxiesLabel != null)
              _infoRow(
                context,
                icon: Icons.copy_all_outlined,
                title: 'Proxies',
                value: proxiesLabel,
              ),
            if ((event.powerLevel ?? '').trim().isNotEmpty)
              _infoRow(
                context,
                icon: Icons.bolt,
                title: 'Power level',
                value: event.powerLevel!.trim(),
              ),
            if (addr.isNotEmpty)
              _infoRow(
                context,
                icon: Icons.place_outlined,
                title: 'Location',
                value: addr,
                onTap: onLocationTap,
              ),
            if ((event.hostNotes ?? '').trim().isNotEmpty) ...[
              const Divider(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Host notes',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(event.hostNotes!),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value),
      trailing:
          onTap == null ? null : const Icon(Icons.open_in_new, size: 18),
      onTap: onTap,
    );
  }
}