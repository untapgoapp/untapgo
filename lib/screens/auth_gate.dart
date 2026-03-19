import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'login_screen.dart';
import 'root_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final supabase = Supabase.instance.client;

  String? _lastUserId; // 👈 evita duplicados

  @override
  void initState() {
    super.initState();

    // 👇 caso: app abre ya logueada
    final session = supabase.auth.currentSession;
    if (session != null) {
      _initPushIfNeeded(session.user.id);
    }

    // 👇 caso: login/logout en runtime
    supabase.auth.onAuthStateChange.listen((data) {
      final userId = data.session?.user.id;
      if (userId != null) {
        _initPushIfNeeded(userId);
      }
    });
  }

  Future<void> _initPushIfNeeded(String userId) async {
    if (_lastUserId == userId) return; // 👈 evita spam

    _lastUserId = userId;

    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission();

    final token = await messaging.getToken();

    print('FCM TOKEN: $token');

    // 👉 siguiente paso: enviar a backend
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final session = supabase.auth.currentSession;

        print('AUTHGATE SESSION EXISTS: ${session != null}');
        print('AUTHGATE USER: ${session?.user.id}');

        if (session == null) {
          return const LoginScreen();
        }

        return const RootScreen();
      },
    );
  }
}