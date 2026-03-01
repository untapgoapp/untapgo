import 'package:flutter/material.dart';
import '../../../models/event.dart';
import 'event_map_preview.dart';

class EventInfoSection extends StatelessWidget {
  final Event event;
  final String Function(DateTime?) formatDate;
  final String? Function() proxiesLabel;
  final Map<String, String> formatLabels;
  final VoidCallback? onHostTap;

  const EventInfoSection({
    super.key,
    required this.event,
    required this.formatDate,
    required this.proxiesLabel,
    required this.formatLabels,
    this.onHostTap,
  });

  Widget _detailItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final proxies = proxiesLabel();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        /// HOST (clickable)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onHostTap,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.grey.shade300,
                  child: Text(
                    (event.hostNickname.isNotEmpty
                            ? event.hostNickname[0]
                            : '?')
                        .toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Host',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        event.hostNickname,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),

        _detailItem(
          icon: Icons.access_time_rounded,
          label: 'Starts',
          value: formatDate(event.startsAt),
        ),
        _detailItem(
          icon: Icons.style_outlined,
          label: 'Format',
          value: formatLabels[event.formatSlug] ??
              event.format ??
              '',
        ),
        if (proxies != null)
          _detailItem(
            icon: Icons.copy_outlined,
            label: 'Proxies',
            value: proxies,
          ),
        if (event.powerLevel != null)
          _detailItem(
            icon: Icons.flash_on_outlined,
            label: 'Power level',
            value: event.powerLevel!,
          ),
        if ((event.addressText ?? '').isNotEmpty)
          _detailItem(
            icon: Icons.location_on_outlined,
            label: 'Location',
            value: event.addressText!,
          ),
        if (event.lat != null && event.lng != null) ...[
          const SizedBox(height: 16),
          EventMapPreview(
            lat: event.lat!,
            lng: event.lng!,
          ),
        ],
      ],
    );
  }
}