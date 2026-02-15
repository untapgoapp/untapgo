import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/event_service.dart';

class EditDeckScreen extends StatefulWidget {
  final String? deckId;
  final String initialCommanderName;
  final String? initialDeckUrl;

  final String? initialFormatSlug;
  final String? initialExportText;

  final bool initialW;
  final bool initialU;
  final bool initialB;
  final bool initialR;
  final bool initialG;
  final bool initialC;

  const EditDeckScreen({
    super.key,
    this.deckId,
    this.initialCommanderName = '',
    this.initialDeckUrl,
    this.initialFormatSlug,
    this.initialExportText,
    this.initialW = false,
    this.initialU = false,
    this.initialB = false,
    this.initialR = false,
    this.initialG = false,
    this.initialC = false,
  });

  bool get isEdit => deckId != null;

  @override
  State<EditDeckScreen> createState() => _EditDeckScreenState();
}

class _EditDeckScreenState extends State<EditDeckScreen> {
  late final TextEditingController _commander;
  late final TextEditingController _deckUrl;
  late final TextEditingController _exportText;

  bool _w = false, _u = false, _b = false, _r = false, _g = false, _c = false;

  String _formatSlug = '';
  bool _saving = false;

  static const List<Map<String, String>> _formatOptions = [
    {'slug': '', 'label': 'None'},
    {'slug': 'commander', 'label': 'Commander'},
    {'slug': 'legacy', 'label': 'Legacy'},
    {'slug': 'modern', 'label': 'Modern'},
    {'slug': 'pauper', 'label': 'Pauper'},
    {'slug': 'pioneer', 'label': 'Pioneer'},
    {'slug': 'premodern', 'label': 'Premodern'},
    {'slug': 'standard', 'label': 'Standard'},
    {'slug': 'vintage', 'label': 'Vintage'},
    {'slug': 'other', 'label': 'Other'},
  ];

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
    _commander = TextEditingController(text: widget.initialCommanderName);
    _deckUrl = TextEditingController(text: widget.initialDeckUrl ?? '');
    _exportText = TextEditingController(text: widget.initialExportText ?? '');

    _w = widget.initialW;
    _u = widget.initialU;
    _b = widget.initialB;
    _r = widget.initialR;
    _g = widget.initialG;
    _c = widget.initialC;

    _formatSlug = (widget.initialFormatSlug ?? '').trim();
  }

  @override
  void dispose() {
    _commander.dispose();
    _deckUrl.dispose();
    _exportText.dispose();
    super.dispose();
  }

  bool get _hasAnyColor => _w || _u || _b || _r || _g;

  Future<void> _save() async {
    final commanderName = _commander.text.trim();

    if (commanderName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Name is required'),
          backgroundColor: Colors.grey.shade900,
        ),
      );
      return;
    }

    final bool colorlessFinal = _c || !_hasAnyColor;

    setState(() => _saving = true);

    final format = _formatSlug.trim();

    final body = {
      'commander_name': commanderName,
      'deck_url': _deckUrl.text.trim().isEmpty ? null : _deckUrl.text.trim(),
      'color_white': _w,
      'color_blue': _u,
      'color_black': _b,
      'color_red': _r,
      'color_green': _g,
      'color_colorless': colorlessFinal,
      'format_slug': format.isEmpty ? null : format,
      'export_text':
          _exportText.text.trim().isEmpty ? null : _exportText.text.trim(),
    };

    try {
      final base = EventService.backendBaseUrl;
      final uri = widget.isEdit
          ? Uri.parse('$base/me/decks/${widget.deckId}')
          : Uri.parse('$base/me/decks');

      final res = widget.isEdit
          ? await http.patch(uri, headers: _headers(), body: jsonEncode(body))
          : await http.post(uri, headers: _headers(), body: jsonEncode(body));

      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception('${res.statusCode} ${res.body}');
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      final raw = e.toString();
      String message = 'Something went wrong';

      if (raw.contains('23514')) {
        message = 'Invalid deck configuration. Check format and colors.';
      } else if (raw.contains('duplicate')) {
        message = 'A deck with this name already exists.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.grey.shade900,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _colorToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: _saving ? null : () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: value ? Colors.black.withOpacity(0.05) : Colors.transparent,
          border: Border.all(
            color: value ? Colors.black : Colors.grey.shade400,
            width: value ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: SvgPicture.asset(
          'assets/mana/${label.toLowerCase()}.svg',
          width: 24,
          height: 24,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isEdit ? 'Edit deck' : 'Add deck';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _commander,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          DropdownButtonFormField<String>(
            value: _formatSlug,
            items: _formatOptions
                .map(
                  (o) => DropdownMenuItem(
                    value: o['slug'],
                    child: Text(o['label']!),
                  ),
                )
                .toList(),
            onChanged:
                _saving ? null : (v) => setState(() => _formatSlug = v ?? ''),
            decoration: const InputDecoration(
              labelText: 'Format',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 12),

          TextField(
            controller: _deckUrl,
            decoration: const InputDecoration(
              labelText: 'Deck URL (optional)',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 16),

          Text(
            'Colors',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),

          const SizedBox(height: 10),

          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _colorToggle('W', _w, (v) => setState(() => _w = v)),
              _colorToggle('U', _u, (v) => setState(() => _u = v)),
              _colorToggle('B', _b, (v) => setState(() => _b = v)),
              _colorToggle('R', _r, (v) => setState(() => _r = v)),
              _colorToggle('G', _g, (v) => setState(() => _g = v)),
              _colorToggle('C', _c, (v) => setState(() => _c = v)),
            ],
          ),

          const SizedBox(height: 20),

          TextField(
            controller: _exportText,
            minLines: 8,
            maxLines: 20,
            decoration: const InputDecoration(
              labelText: 'Plain text (paste here)',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 28),

          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check),
            label: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}
