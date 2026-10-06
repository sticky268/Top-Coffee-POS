import 'package:flutter/material.dart';

/// Placeholder splash/boot screen. Phase 3 wires this to the real auth-check
/// (read stored token -> validate -> redirect to login or POS home).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
