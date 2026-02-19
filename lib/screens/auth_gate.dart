import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_screen.dart';
import 'root_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // Mientras Supabase hidrata la sesión
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // ✅ SIEMPRE leer la sesión real desde aquí
        final session = Supabase.instance.client.auth.currentSession;

        print('AUTHGATE SESSION EXISTS: ${session != null}');
        print('AUTHGATE USER: ${session?.user.id}');
        print('Hello from AuthGate!');

        if (session == null) {
          return const LoginScreen();
        }

        return const RootScreen();
      },
    );
  }
}
