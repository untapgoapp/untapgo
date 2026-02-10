import 'package:flutter/material.dart';

import '../models/public_profile.dart';
import '../services/profile_service.dart';
import 'edit_profile_screen.dart';
import 'my_decks_screen.dart';

class EditAccountScreen extends StatelessWidget {
  final PublicProfile profile;
  final ProfileService service;

  const EditAccountScreen({
    super.key,
    required this.profile,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Profile'),
              Tab(text: 'Decks'),
            ],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            EditProfileScreen(
              service: service,
              initialNickname: profile.nickname,
              initialAvatarUrl: profile.avatarUrl,
              initialBio: profile.bio,
            ),
            const MyDecksBody(),
          ],
        ),
      ),
    );
  }
}
