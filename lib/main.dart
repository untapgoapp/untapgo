import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth_gate.dart';
import 'services/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://lofprlmlpdtulapypqcy.supabase.co',
    anonKey: 'sb_publishable_WegSnaWTAvcN9suXGUU9TA_Yy4O0CnN',
  );

  // Init app settings (km / mi, etc)
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}
