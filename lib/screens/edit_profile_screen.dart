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

  String? _avatarUrl;
  File? _pendingAvatarFile;

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
                      child: Image(image: img, fit: BoxFit.contain),
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

    final ext = file.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';

    final path = '$userId/avatar.$ext';

    await Supabase.instance.client.storage.from('avatars').upload(
          path,
          file,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );

    final url =
        Supabase.instance.client.storage.from('avatars').getPublicUrl(path);

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
    final r = BorderRadius.circular(size * 0.28);

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
          if (_uploadingAvatar)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: r,
                child: const DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black38),
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
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarImage = _avatarImage;

    return Scaffold(
      backgroundColor: const Color(0xFFFBF7F1),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFFBF7F1),
        foregroundColor: Colors.black,
        title: const SizedBox.shrink(),
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
                  style: TextStyle(
                    fontSize: 17, // 👈 clave
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6E5AA7),
                  ),
                ),
          )
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [

            Center(child: _avatarSquircle(avatarImage)),
            const SizedBox(height: 16),

            Center(
              child: GestureDetector(
                onTap: _busy ? null : _pickAvatar,
                child: Text(
                  _picking ? 'Opening…' : 'Choose photo',
                  style: const TextStyle(
                    color: Color(0xFF6E5AA7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Nickname
            TextField(
              controller: _nickname,
              decoration: const InputDecoration(
                labelText: 'Nickname',
                border: InputBorder.none,
              ),
            ),
            const Divider(height: 1, thickness: 0.5, color: Colors.black12),
            const SizedBox(height: 16),

            // Bio
            TextField(
              controller: _bio,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Bio',
                border: InputBorder.none,
              ),
            ),
            const Divider(height: 1, thickness: 0.5, color: Colors.black12),
            const SizedBox(height: 16),

            // Arena
            TextField(
              controller: _mtgArenaUsername,
              decoration: const InputDecoration(
                labelText: 'MTG Arena username',
                border: InputBorder.none,
              ),
            ),
            const Divider(height: 1, thickness: 0.5, color: Colors.black12),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}