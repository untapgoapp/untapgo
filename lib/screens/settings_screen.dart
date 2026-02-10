import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/settings_store.dart';
import '../utils/zip_geocoding.dart';

// TODO: mueve esto a config central cuando deje de ser alpha
const String _googleMapsApiKey = 'AIzaSyDOEmRGIwDF3WEvbouSeIBL7JloiW78GzA';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Session
          if (user != null) ...[
            Text(
              'Session',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Email: ${user.email ?? '-'}'),
            const SizedBox(height: 4),
            Text(
              'User ID: ${user.id}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 24),
          ],

          // Version
          Text(
            'Version',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text('0.1.0 (alpha)'),
          const SizedBox(height: 24),

          // Location
          Text(
            'Location',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<LocationSource>(
            valueListenable: SettingsStore.locationSource,
            builder: (context, source, _) {
              final subtitle = source == LocationSource.zip
                  ? 'Using ZIP ${SettingsStore.currentManualZip ?? ''}'
                  : 'Using device location';

              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Location source'),
                subtitle: Text(subtitle),
                trailing: TextButton(
                  onPressed: () => _openLocationPicker(context),
                  child: const Text('Change'),
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // Distance units
          Text(
            'Distance units',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<DistanceUnit>(
            valueListenable: SettingsStore.distanceUnit,
            builder: (context, unit, _) {
              return DropdownButtonFormField<DistanceUnit>(
                initialValue: unit,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: DistanceUnit.km,
                    child: Text('Kilometers (km)'),
                  ),
                  DropdownMenuItem(
                    value: DistanceUnit.mi,
                    child: Text('Miles (mi)'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  SettingsStore.setDistanceUnit(v);
                },
              );
            },
          ),
          const SizedBox(height: 16),

          // Feed
          Text(
            'Feed',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<bool>(
            valueListenable: SettingsStore.sortByDistance,
            builder: (context, enabled, _) {
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sort events by distance'),
                subtitle: const Text(
                  'When location is available, closer events appear first.',
                ),
                value: enabled,
                onChanged: (v) => SettingsStore.setSortByDistance(v),
              );
            },
          ),
          const SizedBox(height: 24),

          // Legal
          Text(
            'Legal',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Magic: The Gathering® is a trademark of Wizards of the Coast LLC.\n'
            'UntapGo is not affiliated with Wizards of the Coast.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: 24),

          // Support & feedback
          Text(
            'Support & feedback',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              launchUrl(
                Uri.parse('mailto:untapgoapp@gmail.com'),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text(
              'untapgoapp@gmail.com',
              style: TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Support UntapGo
          Text(
            'Support UntapGo',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              launchUrl(
                Uri.parse('https://buymeacoffee.com/untapgo'),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text(
              'Crack a booster ☕️',
              style: TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- helpers ----

  void _openLocationPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Use device location'),
                onTap: () {
                  Navigator.pop(context);
                  if (SettingsStore.hasLocation) {
                    SettingsStore.setGpsLocation(
                      lat: SettingsStore.currentLat!,
                      lng: SettingsStore.currentLng!,
                    );
                  }
                },
              ),
              ListTile(
                title: const Text('Enter ZIP manually'),
                onTap: () {
                  Navigator.pop(context);
                  _openZipInput(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openZipInput(BuildContext context) {
    final controller = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter ZIP code',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'ZIP code',
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () async {
                  final zip = controller.text.trim();
                  if (zip.isEmpty) return;

                  final result = await ZipGeocoding.geocodeZip(
                    zip,
                    apiKey: _googleMapsApiKey,
                  );

                  if (result == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Invalid ZIP code'),
                      ),
                    );
                    return;
                  }

                  await SettingsStore.setZipLocation(
                    zip: zip,
                    lat: result.lat,
                    lng: result.lng,
                  );

                  Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}
