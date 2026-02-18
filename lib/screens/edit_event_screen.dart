import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/event.dart';
import '../services/event_service.dart';

class EditEventScreen extends StatefulWidget {
  final Event event;

  const EditEventScreen({super.key, required this.event});

  @override
  State<EditEventScreen> createState() => _EditEventScreenState();
}

class _EditEventScreenState extends State<EditEventScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _notesCtrl;
  final TextEditingController _maxPlayersCtrl = TextEditingController();

  bool _busy = false;
  String? _error;

  DateTime? _startsAtLocal;

  // ─────────────────────────────────────────────────────────────
  // FORMAT
  // ─────────────────────────────────────────────────────────────
  static const Map<String, String> kFormatLabels = {
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

  static const List<String> _formatSlugs = [
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

  // ─────────────────────────────────────────────────────────────
  // PROXIES
  // ─────────────────────────────────────────────────────────────
  static const Map<String, String> kProxyLabels = {
    'Yes': 'Allowed',
    'No': 'Not allowed',
    'Ask': 'Ask host',
  };

  static const List<String> _proxyValues = ['Yes', 'No', 'Ask'];

  String? _proxiesPolicy;

  // ─────────────────────────────────────────────────────────────
  // POWER LEVEL
  // ─────────────────────────────────────────────────────────────
  static const List<String> _powerLevels = [
    'Casual',
    'Competitive',
  ];

  String? _powerLevel;
  String? _formatSlug;

  Map<String, String> _headers() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @override
  void initState() {
    super.initState();

    _titleCtrl = TextEditingController(text: widget.event.title);
    _addressCtrl = TextEditingController(text: widget.event.addressText ?? '');
    _notesCtrl = TextEditingController(text: widget.event.hostNotes ?? '');

    _maxPlayersCtrl.text = widget.event.maxPlayers.toString();

    final pl = (widget.event.powerLevel ?? '').trim();
    _powerLevel = _powerLevels.contains(pl) ? pl : null;

    final fs = (widget.event.formatSlug ?? '').trim().toLowerCase();
    _formatSlug = _formatSlugs.contains(fs) ? fs : null;

    final rawProxies = (widget.event.proxies ?? '').trim();
    _proxiesPolicy = _proxyValues.contains(rawProxies) ? rawProxies : null;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    _maxPlayersCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _toastError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.grey.shade900,
      ),
    );
  }

  String _humanizeError(Object e) {
    return e.toString().replaceFirst('Exception: ', '');
  }

  // ─────────────────────────────────────────────────────────────
  // PATCH payload
  // ─────────────────────────────────────────────────────────────
  Map<String, dynamic> _buildPatchPayload() {
    final payload = <String, dynamic>{};

    if (_titleCtrl.text.trim() != widget.event.title) {
      payload['title'] = _titleCtrl.text.trim();
    }

    if (_addressCtrl.text.trim() != (widget.event.addressText ?? '')) {
      payload['address_text'] = _addressCtrl.text.trim();
    }

    final nextMax = int.tryParse(_maxPlayersCtrl.text.trim());
    if (nextMax != widget.event.maxPlayers) {
      payload['max_players'] = nextMax;
    }

    if ((_powerLevel ?? '') != (widget.event.powerLevel ?? '')) {
      payload['power_level'] = _powerLevel;
    }

    if ((_formatSlug ?? '') != (widget.event.formatSlug ?? '')) {
      payload['format_slug'] = _formatSlug;
    }

    if ((_proxiesPolicy ?? '') != (widget.event.proxies ?? '')) {
      payload['proxies_policy'] = _proxiesPolicy;
    }

    if (_notesCtrl.text.trim() != (widget.event.hostNotes ?? '')) {
      payload['host_notes'] =
          _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
    }

    return payload;
  }

  // ─────────────────────────────────────────────────────────────
  // SAVE
  // ─────────────────────────────────────────────────────────────
  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final payload = _buildPatchPayload();

      if (payload.isEmpty) {
        _toast('No changes');
        Navigator.pop(context, null);
        return;
      }

      final res = await http.patch(
        Uri.parse('${EventService.backendBaseUrl}/events/${widget.event.id}'),
        headers: _headers(),
        body: jsonEncode(payload),
      );

      if (res.statusCode != 200) {
        throw Exception(res.body);
      }

      // ✅ DEVOLVEMOS EL EVENT ACTUALIZADO
      final updatedEvent = widget.event.copyWith(
        title: _titleCtrl.text.trim(),
        addressText: _addressCtrl.text.trim(),
        maxPlayers: int.tryParse(_maxPlayersCtrl.text.trim()),
        formatSlug: _formatSlug,
        proxies: _proxiesPolicy,
        powerLevel: _powerLevel,
        hostNotes: _notesCtrl.text.trim(),
      );

      _toast('Saved');
      Navigator.pop(context, updatedEvent);
    } catch (e) {
      final msg = _humanizeError(e);
      setState(() => _error = msg);
      _toastError(msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit event'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressCtrl,
            decoration: const InputDecoration(
              labelText: 'Place',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _maxPlayersCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Max players',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _formatSlug,
            items: _formatSlugs
                .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(kFormatLabels[s] ?? s),
                    ))
                .toList(),
            onChanged: _busy ? null : (v) => setState(() => _formatSlug = v),
            decoration: const InputDecoration(
              labelText: 'Format',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _proxiesPolicy,
            items: _proxyValues
                .map((v) => DropdownMenuItem(
                      value: v,
                      child: Text(kProxyLabels[v] ?? v),
                    ))
                .toList(),
            onChanged: _busy ? null : (v) => setState(() => _proxiesPolicy = v),
            decoration: const InputDecoration(
              labelText: 'Proxies',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _powerLevel,
            items: _powerLevels
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: _busy ? null : (v) => setState(() => _powerLevel = v),
            decoration: const InputDecoration(
              labelText: 'Power level',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Host notes',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),

          // ✅ ÚNICO BOTÓN DE GUARDAR (ABAJO)
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save changes'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}