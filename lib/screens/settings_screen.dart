import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/settings_store.dart';
import '../services/profile_service.dart';
import '../utils/zip_geocoding.dart';

// TODO: mueve esto a config central cuando deje de ser alpha
const String _googleMapsApiKey = 'AIzaSyDOEmRGIwDF3WEvbouSeIBL7JloiW78GzA';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Account
                  if (user != null) ...[
                    Text(
                      'Account',
                      style:
                          Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(user.email ?? '-'),
                    const SizedBox(height: 4),
                    Text(
                      user.id,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.black54),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Location
                  Text(
                    'Location',
                    style:
                        Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<LocationSource>(
                    valueListenable:
                        SettingsStore.locationSource,
                    builder: (context, source, _) {
                      final subtitle =
                          source == LocationSource.zip
                              ? 'Using ZIP ${SettingsStore.currentManualZip ?? ''}'
                              : 'Using device location';

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Location source'),
                        subtitle: Text(subtitle),
                        trailing: TextButton(
                          onPressed: () =>
                              _openLocationPicker(context),
                          child: const Text('Change'),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Distance units
                  Text(
                    'Distance units',
                    style:
                        Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<DistanceUnit>(
                    valueListenable:
                        SettingsStore.distanceUnit,
                    builder: (context, unit, _) {
                      return DropdownButtonFormField<
                          DistanceUnit>(
                        initialValue: unit,
                        decoration:
                            const InputDecoration(
                          border:
                              OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: DistanceUnit.km,
                            child: Text(
                                'Kilometers (km)'),
                          ),
                          DropdownMenuItem(
                            value: DistanceUnit.mi,
                            child:
                                Text('Miles (mi)'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          SettingsStore
                              .setDistanceUnit(v);
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Feed
                  Text(
                    'Feed',
                    style:
                        Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<bool>(
                    valueListenable:
                        SettingsStore.sortByDistance,
                    builder: (context, enabled, _) {
                      return SwitchListTile(
                        contentPadding:
                            EdgeInsets.zero,
                        title: const Text(
                            'Sort events by distance'),
                        subtitle: const Text(
                          'When location is available, closer events appear first.',
                        ),
                        value: enabled,
                        onChanged: (v) =>
                            SettingsStore
                                .setSortByDistance(v),
                      );
                    },
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            Padding(
              padding: const EdgeInsets.only(
                  top: 12, bottom: 16),
              child: ListTile(
                dense: true,
                contentPadding:
                    const EdgeInsets.symmetric(
                        horizontal: 16),
                leading:
                    const Icon(Icons.delete_outline),
                title:
                    const Text('Delete Account'),
                subtitle: const Text(
                  'Permanently remove your account and all data.',
                ),
                onTap: _loading
                    ? null
                    : () =>
                        _startDeleteFlow(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- DELETE FLOW ----------------

  Future<void> _startDeleteFlow(
      BuildContext context) async {
    final first = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete account'),
        content: const Text(
          'Do you want to permanently delete your account?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (first != true) return;

    final controller = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title:
            const Text('Final confirmation'),
        content: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            const Text(
              'Type DELETE to confirm.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration:
                  const InputDecoration(
                      hintText: 'DELETE'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, false),
            child:
                const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text
                      .trim() ==
                  'DELETE') {
                Navigator.pop(
                    context, true);
              }
            },
            child:
                const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteAccount(context);
    }
  }

  Future<void> _deleteAccount(
      BuildContext context) async {
    setState(() => _loading = true);

    try {
      final session =
          Supabase.instance.client.auth.currentSession;
      if (session == null) {
        throw Exception('AUTH_REQUIRED');
      }

      final response = await http.delete(
        Uri.parse(
            '${ProfileService.backendBaseUrl}/me'),
        headers: {
          'Authorization':
              'Bearer ${session.accessToken}',
        },
      );

      if (response.statusCode != 200) {
        throw Exception(response.body);
      }

      await Supabase.instance.client.auth
          .signOut();

      if (!mounted) return;

      Navigator.of(context)
          .popUntil((route) =>
              route.isFirst);
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content:
              Text('Failed to delete account'),
        ),
      );
    } finally {
      if (mounted)
        setState(() => _loading = false);
    }
  }

  // ---------------- LOCATION HELPERS ----------------

  void _openLocationPicker(
      BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              ListTile(
                title: const Text(
                    'Use device location'),
                onTap: () {
                  Navigator.pop(context);
                  if (SettingsStore
                      .hasLocation) {
                    SettingsStore
                        .setGpsLocation(
                      lat: SettingsStore
                          .currentLat!,
                      lng: SettingsStore
                          .currentLng!,
                    );
                  }
                },
              ),
              ListTile(
                title: const Text(
                    'Enter ZIP manually'),
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

  void _openZipInput(
      BuildContext context) {
    final controller =
        TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context)
                .viewInsets
                .bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const Text(
                'Enter ZIP code',
                style:
                    TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType:
                    TextInputType.number,
                decoration:
                    const InputDecoration(
                        hintText:
                            'ZIP code'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () async {
                  final zip =
                      controller.text
                          .trim();
                  if (zip.isEmpty) return;

                  final result =
                      await ZipGeocoding
                          .geocodeZip(
                    zip,
                    apiKey:
                        _googleMapsApiKey,
                  );

                  if (result == null) {
                    ScaffoldMessenger.of(
                            context)
                        .showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Invalid ZIP code'),
                      ),
                    );
                    return;
                  }

                  await SettingsStore
                      .setZipLocation(
                    zip: zip,
                    lat: result.lat,
                    lng: result.lng,
                  );

                  Navigator.pop(
                      context);
                },
                child:
                    const Text('Save'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}
