import 'package:flutter/material.dart';
import 'package:roadie_app/screens/login_screen.dart';
import 'package:roadie_app/screens/home_screen.dart';
import 'package:roadie_app/screens/ride_screen.dart';
import 'package:roadie_app/services/api_service.dart';
import 'package:roadie_app/services/websocket_service.dart';
import 'package:roadie_app/services/wake_lock_service.dart';
import 'package:roadie_app/services/app_lifecycle_manager.dart';
import 'package:roadie_app/services/overlay_service.dart';
import 'package:roadie_app/services/network_service.dart';
import 'package:roadie_app/core/cache/cache_manager.dart';
import 'dart:async';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Initialize critical services while the splash screen is visible
      await CacheManager().initialize();
      
      await Future.wait([
        WakeLockService().initialize(),
        OverlayService().initialize(),
        NetworkService().initialize(),
      ]);

      AppLifecycleManager().initialize();
      
      // Now proceed with session check
      await _checkSession();
    } catch (e) {
      debugPrint("App initialization error: $e");
      // Fallback to session check if services fail
      _checkSession();
    }
  }

  Future<void> _checkSession() async {
    try {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      final token = await ApiService.getToken();
      if (token != null) {
        // Fetch active request for Roadie with timeout
        final activeRequests = await ApiService.getMyRequests(
          status: 'active',
        ).timeout(const Duration(seconds: 5), onTimeout: () => []);

        if (activeRequests.isNotEmpty && mounted) {
          final active = activeRequests.first;
          final ws = WebSocketService();
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => RideScreen(request: active, ws: ws),
            ),
          );
          return;
        }

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen(role: "RODIE")),
          );
        }
      } else {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen(role: "RODIE")),
          );
        }
      }
    } catch (e) {
      debugPrint("Roadie session check error: $e");
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen(role: "RODIE")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF10223D), Color(0xFF1D3B63), Color(0xFF10223D)],
          ),
        ),
        child: Center(
          child: Hero(
            tag: 'logo',
            child: Image.asset(
              'assets/smart_mobility_logo.png',
              height: 120,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
