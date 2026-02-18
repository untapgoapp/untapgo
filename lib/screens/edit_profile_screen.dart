import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/profile_service.dart';

class EditProfileScreen extends StatefulWidget {
  final ProfileService service;
  final String initialNickname;
  final String? initialAvatarUrl;
  final String? initialBio;
  final String? initialMtgArenaUsername;

  const EditProfileScreen({
    super.key,
    required this.service,
    required this.initialNickname,
    this.initialAvatarUrl,
    this.initialBio,
    this.initialMtgArenaUsername,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nickname;
  late final TextEditingController _bio;
  late final TextEditingController _mtgArenaUsername;

  bool _saving = false;
  bool _picking = false;
  bool _uploadingAvatar = false;
  String? _error;

  String? _avatarUrl; // current (url) avatar
  File? _pendingAvatarFile; // selected image waiting to upload

  @override
  void initState() {
    super.initState();
    _nickname = TextEditingController(text: widget.initialNickname);
    _bio = TextEditingController(text: widget.initialBio ?? '');
    _mtgArenaUsername =
        TextEditingController(text: widget.initialMtgArenaUsername ?? '');
    _avatarUrl = (widget.initialAvatarUrl ?? '').trim().isEmpty
        ? null
        : widget.initialAvatarUrl!.trim();
  }

  @override
  void dispose() {
    _nickname.dispose();
    _bio.dispose();
    _mtgArenaUsername.dispose();
    super.dispose();
  }

  bool get _busy => _saving || _uploadingAvatar;

  ImageProvider? get _avatarImage {
    if (_pendingAvatarFile != null) return FileImage(_pendingAvatarFile!);
    if ((_avatarUrl ?? '').isNotEmpty) return NetworkImage(_avatarUrl!);
    return null;
  }

  Future<void> _pickAvatar() async {
    if (_busy || _picking) return;

    setState(() {
      _picking = true;
      _error = null;
    });

    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        imageQuality: 80,
      );

      if (image == null) return;

      setState(() {
        _pendingAvatarFile = File(image.path);
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _openAvatarPreview() {
    final img = _avatarImage;
    if (img == null) return;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                color: Colors.black,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Image(
                        image: img,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _uploadAvatarAndGetPublicUrl(File file) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw Exception('AUTH_REQUIRED');

    final userId = user.id;

    final lower = file.path.toLowerCase();
    final isPng = lower.endsWith('.png');
    final ext = isPng ? 'png' : 'jpg';
    final contentType = isPng ? 'image/png' : 'image/jpeg';

    final path = '$userId/avatar.$ext';

    await Supabase.instance.client.storage.from('avatars').upload(
          path,
          file,
          fileOptions: FileOptions(
            upsert: true,
            contentType: contentType,
          ),
        );

    final url =
        Supabase.instance.client.storage.from('avatars').getPublicUrl(path);

    // Cache-bust para evitar ver el avatar viejo
    return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _save() async {
    final nick = _nickname.text.trim();
    if (nick.isEmpty) {
      setState(() => _error = 'Nickname is required');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      String? avatarUrlToSave = _avatarUrl;

      // 1) Upload avatar if user selected a new file
      if (_pendingAvatarFile != null) {
        setState(() => _uploadingAvatar = true);
        try {
          avatarUrlToSave =
              await _uploadAvatarAndGetPublicUrl(_pendingAvatarFile!);
        } finally {
          if (mounted) setState(() => _uploadingAvatar = false);
        }
      }

      final arena = _mtgArenaUsername.text.trim();

      // 2) Save profile (backend)
      await widget.service.updateMyProfile(
        nickname: nick,
        avatarUrl: avatarUrlToSave,
        bio: _bio.text.trim(),
        mtgArenaUsername: arena.isEmpty ? null : arena,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _avatarSquircle(ImageProvider? avatarImage) {
    const double size = 112;
    final r = BorderRadius.circular(size * 0.28); // same “squircle” rule as Profile

    return InkWell(
      borderRadius: r,
      onTap: avatarImage == null ? null : _openAvatarPreview,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: r,
            child: Container(
              width: size,
              height: size,
              color: Colors.grey.shade200,
              child: avatarImage != null
                  ? Image(image: avatarImage, fit: BoxFit.cover)
                  : const Center(child: Icon(Icons.person, size: 52)),
            ),
          ),

          // Upload overlay (squircle too)
          if (_uploadingAvatar)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: r,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black38,
                  ),
                  child: Center(
                    child: SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
            ),

          // Zoom icon
          if (avatarImage != null && !_uploadingAvatar)
            Positioned(
              bottom: 6,
              right: 6,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.zoom_in, size: 18, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarImage = _avatarImage;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(child: _avatarSquircle(avatarImage)),

            const SizedBox(height: 12),

            Center(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _pickAvatar,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(_picking ? 'Opening…' : 'Choose photo'),
              ),
            ),

            if (_pendingAvatarFile != null) ...[
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'New photo selected (uploads on Save)',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ],

            const SizedBox(height: 20),

            TextField(
              controller: _nickname,
              decoration: const InputDecoration(
                labelText: 'Nickname',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _bio,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Bio',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _mtgArenaUsername,
              decoration: const InputDecoration(
                labelText: 'MTG Arena username',
                hintText: 'optional',
                border: OutlineInputBorder(),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
