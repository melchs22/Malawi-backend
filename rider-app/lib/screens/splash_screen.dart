import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rider_app/screens/login_screen.dart';
import 'package:rider_app/screens/home_screen.dart';
import 'package:rider_app/screens/ride_screen.dart';
import 'package:rider_app/screens/requesting_screen.dart';
import 'package:rider_app/services/api_service.dart';
import 'package:rider_app/services/websocket_service.dart';
import 'package:rider_app/services/wake_lock_service.dart';
import 'package:rider_app/services/network_service.dart';
import 'package:rider_app/services/app_lifecycle_manager.dart';
import 'package:rider_app/core/cache/cache_manager.dart';
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

  Future<void> _requestOverlayPermission() async {
    try {
      const channel = MethodChannel('vehix/overlay');
      await channel.invokeMethod('requestOverlayPermission');
    } catch (_) {}
  }

  Future<void> _initializeApp() async {
    try {
      // Initialize Hive cache
      await CacheManager().initialize();

      // Initialize services in parallel
      await Future.wait([
        WakeLockService().initialize(),
        NetworkService().initialize(),
        _requestOverlayPermission(),
      ]);

      // Initialize lifecycle manager (non-blocking)
      AppLifecycleManager().initialize();
      
      // Now proceed with session check
      await _checkSession();
    } catch (e) {
      debugPrint("Rider app initialization error: $e");
      _checkSession();
    }
  }

  Future<void> _checkSession() async {
    try {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      final token = await ApiService.getToken();
      final role = await ApiService.getRole();

      if (token != null) {
        // Fetch active request with timeout or catch-all
        final activeRequests = await ApiService.getMyRequests(
          status: 'active',
        ).timeout(const Duration(seconds: 5), onTimeout: () => []);

        if (activeRequests.isNotEmpty && mounted) {
          final active = activeRequests.first;
          final ws = WebSocketService(); // Initialize WS for the active session
          if (active["status"] == "REQUESTED") {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => RequestingScreen(request: active, ws: ws),
              ),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => RideScreen(request: active, isRoadie: false, ws: ws),
              ),
            );
          }
          return;
        }

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => HomeScreen(role: role ?? "RIDER"),
            ),
          );
        }
      } else {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen(role: 'RIDER')),
          );
        }
      }
    } catch (e) {
      debugPrint("Session check error: $e");
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen(role: 'RIDER')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Hero(
          tag: 'app_logo',
          child: Image.asset(
            'assets/smart_mobility_logo.png',
            height: 120,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
