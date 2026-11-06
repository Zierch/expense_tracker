import 'package:flutter/material.dart';

/// Branded screen shown briefly after the Android native launch screen.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [Color(0xFF101916), Color(0xFF1B2924)]
                : const [Color(0xFF0B3D2E), Color(0xFF0E5A44)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/icon/splash_1024.png', width: 120, height: 120),
              const SizedBox(height: 24),
              const Text(
                'ExpenseTracker',
                style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Track smarter, spend better.',
                style: TextStyle(color: Color(0xFFC3E3D2), fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
