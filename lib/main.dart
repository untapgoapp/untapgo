import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';

import 'screens/auth_gate.dart';
import 'services/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔥 Firebase (para push)
  await Firebase.initializeApp();
  print('Firebase OK');

  // 🔐 Supabase
  await Supabase.initialize(
    url: 'https://lofprlmlpdtulapypqcy.supabase.co',
    anonKey: 'sb_publishable_WegSnaWTAvcN9suXGUU9TA_Yy4O0CnN',
  );

  // ⚙️ Settings (km / mi, etc)
  await SettingsStore.init();

  runApp(const UntapGoApp());
}

class UntapGoApp extends StatelessWidget {
  const UntapGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UntapGo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,

        // 🎨 Fondo global
        scaffoldBackgroundColor: const Color(0xFFFBF7F1),

        // 👇 FIX dropdowns / menus
        canvasColor: const Color(0xFFFBF7F1),

        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6E5AA7),
          background: const Color(0xFFFBF7F1),
          surface: Colors.white,
        ),

        // Limpia líneas Material innecesarias
        dividerColor: Colors.transparent,
      ),
      home: const AuthGate(),
    );
  }
}