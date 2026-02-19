import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/event_service.dart';
import '../models/event.dart';

const String kGoogleMapsApiKey = 'AIzaSyDOEmRGIwDF3WEvbouSeIBL7JloiW78GzA';

const List<String> kPowerLevels = [
  'Casual',
  'Competitive',
];

const List<String> kProxiesPolicies = [
  'Yes',
  'No',
  'Ask',
];

/// ✅ Formats are now SLUGS (DB-friendly).
/// UI label comes from the map below.
const List<String> kFormatSlugs = [
  'commander',
  'cube',
  'draft',
  'legacy',
  'modern',
  'pauper',
  'pioneer',
  'premodern',
  'sealed',
  'standard',
  'vintage',
  'other',
];

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

class _PlaceSuggestion {
  final String placeId;
  final String text;
  const _PlaceSuggestion({required this.placeId, required this.text});
}

class _PlaceDetails {
  final String placeId;
  final String formattedAddress;
  final double lat;
  final double lng;

  const _PlaceDetails({
    required this.placeId,
    required this.formattedAddress,
    required this.lat,
    required this.lng,
  });
}

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _eventService = EventService();

  // Form controllers
  final _titleCtrl = TextEditingController();
  final _durationCtrl = TextEditingController(text: '180');
  final _maxPlayersCtrl = TextEditingController(text: '4');
  final _placeCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // Form state
  DateTime _startsAt = DateTime.now().add(const Duration(hours: 2));
  String _powerLevel = kPowerLevels.first;
  String _proxiesPolicy = kProxiesPolicies.last;

  /// ✅ store format as SLUG (matches public.formats.slug)
  String _formatSlug = kFormatSlugs.first;

  bool _autoJoin = true;

  // Place selection (final)
  String? _placeId;
  String? _addressText;
  double? _lat;
  double? _lng;

  // Autocomplete UI state
  final List<_PlaceSuggestion> _suggestions = [];
  Timer? _debounce;
  String? _sessionToken;
  bool _isSearching = false;

  // Saving state
  bool _isSaving = false;
  String? _error;

  static const Duration _httpTimeout = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _placeCtrl.addListener(_onPlaceChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _placeCtrl.removeListener(_onPlaceChanged);

    _titleCtrl.dispose();
    _durationCtrl.dispose();
    _maxPlayersCtrl.dispose();
    _placeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // --------------------------
  // Date & time
  // --------------------------

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt.isAfter(now) ? _startsAt : now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (!mounted || date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt),
    );
    if (!mounted || time == null) return;

    setState(() {
      _startsAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  // --------------------------
  // Places (HTTP)
  // --------------------------

  void _ensureSessionToken() {
    _sessionToken ??= DateTime.now().microsecondsSinceEpoch.toString();
  }

  void _resetPlaceSelection() {
    _placeId = null;
    _addressText = null;
    _lat = null;
    _lng = null;
  }

  void _onPlaceChanged() {
    _resetPlaceSelection();

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final q = _placeCtrl.text.trim();
      if (!mounted) return;

      if (q.isEmpty) {
        setState(() => _suggestions.clear());
        return;
      }

      _ensureSessionToken();
      await _fetchSuggestions(q);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    final uri =
        Uri.parse('https://places.googleapis.com/v1/places:autocomplete');

    setState(() {
      _isSearching = true;
      _error = null;
    });

    final body = {
      "input": query,
      "sessionToken": _sessionToken,
      "includedRegionCodes": ["US", "CA"],
    };

    try {
      final res = await http
          .post(
            uri,
            headers: {
              "Content-Type": "application/json",
              "X-Goog-Api-Key": kGoogleMapsApiKey,
              "X-Goog-FieldMask":
                  "suggestions.placePrediction.placeId,suggestions.placePrediction.text.text",
            },
            body: jsonEncode(body),
          )
          .timeout(_httpTimeout);

      if (res.statusCode >= 400) {
        throw Exception(
            'Places autocomplete failed: ${res.statusCode} ${res.body}');
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final raw = (data["suggestions"] as List<dynamic>? ?? []);

      final next = <_PlaceSuggestion>[];
      for (final s in raw) {
        final m = s as Map<String, dynamic>;
        final pp = m["placePrediction"] as Map<String, dynamic>?;
        if (pp == null) continue;

        final placeId = pp["placeId"] as String?;
        final textObj = pp["text"] as Map<String, dynamic>?;
        final txt = textObj?["text"] as String?;

        if (placeId != null && txt != null && txt.trim().isNotEmpty) {
          next.add(_PlaceSuggestion(placeId: placeId, text: txt.trim()));
        }
      }

      if (!mounted) return;
      setState(() {
        _suggestions
          ..clear()
          ..addAll(next);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _suggestions.clear();
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<_PlaceDetails> _fetchPlaceDetails(String placeId) async {
    final uri = Uri.parse('https://places.googleapis.com/v1/places/$placeId');

    final res = await http.get(
      uri,
      headers: {
        "X-Goog-Api-Key": kGoogleMapsApiKey,
        "X-Goog-FieldMask": "id,formattedAddress,location",
      },
    ).timeout(_httpTimeout);

    if (res.statusCode >= 400) {
      throw Exception('Places details failed: ${res.statusCode} ${res.body}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final loc = data["location"] as Map<String, dynamic>?;
    if (loc == null) throw Exception("Place details missing location");

    final lat = (loc["latitude"] as num).toDouble();
    final lng = (loc["longitude"] as num).toDouble();
    final addr = (data["formattedAddress"] as String?)?.trim() ?? '';

    return _PlaceDetails(
      placeId: placeId,
      formattedAddress: addr,
      lat: lat,
      lng: lng,
    );
  }

  Future<void> _selectSuggestion(_PlaceSuggestion s) async {
    FocusScope.of(context).unfocus();

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final details = await _fetchPlaceDetails(s.placeId);

      if (!mounted) return;
      setState(() {
        _placeId = details.placeId;
        _addressText = details.formattedAddress.isNotEmpty
            ? details.formattedAddress
            : s.text;
        _lat = details.lat;
        _lng = details.lng;

        _placeCtrl.text = _addressText ?? s.text;
        _suggestions.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Widget _buildSuggestions() {
    final q = _placeCtrl.text.trim();
    if (q.isEmpty) return const SizedBox.shrink();
    if (_suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _suggestions.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final s = _suggestions[i];
          return ListTile(
            dense: true,
            title: Text(s.text, maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => _selectSuggestion(s),
          );
        },
      ),
    );
  }

  // --------------------------
  // Create event
  // --------------------------

  int _parseInt(TextEditingController c, int fallback) {
    final v = int.tryParse(c.text.trim());
    return v ?? fallback;
  }

  Future<void> _create() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }

    if (_lat == null || _lng == null) {
      setState(() => _error = 'Pick a place from the suggestions.');
      return;
    }

    final safeAddressText = (_addressText ?? _placeCtrl.text.trim()).trim();
    if (safeAddressText.isEmpty) {
      setState(() => _error = 'Place is required.');
      return;
    }

    final safePlaceId = _placeId ?? '';

    if (!kPowerLevels.contains(_powerLevel)) {
      setState(() => _error = 'Invalid power level.');
      return;
    }

    if (!kFormatSlugs.contains(_formatSlug)) {
      setState(() => _error = 'Invalid format.');
      return;
    }

    final notes = _notesCtrl.text.trim();
    final hostNotes = notes.isEmpty ? null : notes;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      debugPrint('CREATE EVENT → format_slug=$_formatSlug');

      final eventId = await _eventService.createEvent(
        title: title,
        startsAt: _startsAt.toUtc(),
        durationMinutes: _parseInt(_durationCtrl, 180),
        maxPlayers: _parseInt(_maxPlayersCtrl, 4),
        powerLevel: _powerLevel,
        proxiesPolicy: _proxiesPolicy,
        format_slug: _formatSlug,
        addressText: safeAddressText,
        placeId: safePlaceId,
        lat: _lat!,
        lng: _lng!,
        hostNotes: hostNotes,
      );

      if (_autoJoin) {
        await _eventService.joinEvent(eventId);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --------------------------
  // UI
  // --------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create event')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _placeCtrl,
              decoration: InputDecoration(
                labelText: 'Place',
                border: const OutlineInputBorder(),
                hintText: 'Start typing…',
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (_placeCtrl.text.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              setState(() {
                                _placeCtrl.clear();
                                _suggestions.clear();
                                _resetPlaceSelection();
                              });
                            },
                            icon: const Icon(Icons.close),
                          )
                        : null),
              ),
            ),
            _buildSuggestions(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Starts: ${Event.formatStarts(_startsAt)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: _pickDateTime,
                  child: const Text('Change'),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-join as player'),
              value: _autoJoin,
              onChanged: (v) => setState(() => _autoJoin = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _durationCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Duration (min)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _maxPlayersCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Max players',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ✅ Format (slug stored, label displayed)
            DropdownButtonFormField<String>(
              initialValue: _formatSlug,
              decoration: const InputDecoration(
                labelText: 'Format',
                border: OutlineInputBorder(),
              ),
              items: kFormatSlugs
                  .map(
                    (slug) => DropdownMenuItem(
                      value: slug,
                      child: Text(kFormatLabels[slug] ?? slug),
                    ),
                  )
                  .toList(),
              onChanged: (v) =>
                  setState(() => _formatSlug = v ?? kFormatSlugs.first),
            ),

            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _powerLevel,
              decoration: const InputDecoration(
                labelText: 'Power level',
                border: OutlineInputBorder(),
              ),
              items: kPowerLevels
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _powerLevel = v ?? kPowerLevels.first),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _proxiesPolicy,
              decoration: const InputDecoration(
                labelText: 'Proxies',
                border: OutlineInputBorder(),
              ),
              items: kProxiesPolicies
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _proxiesPolicy = v ?? kProxiesPolicies.last),
            ),

            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Host notes (optional)',
                border: OutlineInputBorder(),
                hintText: 'Anything players should know (parking, rules, etc.)',
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _isSaving ? null : _create,
              child: _isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create event'),
            ),
          ],
        ),
      ),
    );
  }
}