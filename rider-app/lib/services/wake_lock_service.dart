import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:async';

/// Professional Wake Lock Service for SRS Apps using wakelock_plus
/// 
/// Features:
/// - Reliable background/foreground management
/// - Platform-independent implementation via wakelock_plus
/// - Automatic lifecycle management
/// - Production-ready for stable roadside assistance operations
class WakeLockService {
  static final WakeLockService _instance = WakeLockService._internal();
  factory WakeLockService() => _instance;
  WakeLockService._internal();

  bool _isInitialized = false;
  
  /// Initialize the wake lock service
  /// Call this once when app starts
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Enable wakelock by default when app starts
      await WakelockPlus.enable();
      _isInitialized = true;
      print('🔋 WakeLockService initialized and screen-awake ENABLED');
    } catch (e) {
      print('❌ WakeLockService initialization failed: $e');
    }
  }

  /// Manually enable wake lock
  Future<void> enable() async {
    try {
      await WakelockPlus.enable();
      print('🔋 Wake lock manually ENABLED');
    } catch (e) {
      print('❌ Failed to enable wake lock: $e');
    }
  }

  /// Manually disable wake lock
  Future<void> disable() async {
    try {
      await WakelockPlus.disable();
      print('🔋 Wake lock manually DISABLED');
    } catch (e) {
      print('❌ Failed to disable wake lock: $e');
    }
  }

  /// Get current wake lock state (sync)
  bool get isEnabled => _isInitialized;

  /// Get current wake lock state (async)
  Future<bool> get isActive async => await WakelockPlus.enabled;

  /// Set wake lock state
  Future<void> setEnabled(bool value) async {
    if (value) {
      await enable();
    } else {
      await disable();
    }
  }

  /// Call this when app goes to foreground or returns from background
  void onAppResumed() {
    WakelockPlus.enable();
    print('🔋 App resumed - screen-awake resumed');
  }

  /// Call this when app goes to background
  void onAppPaused() {
    WakelockPlus.disable();
    print('🔋 App paused - screen-awake paused');
  }

  /// Dispose the service (safely disable wake lock)
  Future<void> dispose() async {
    try {
      await WakelockPlus.disable();
      _isInitialized = false;
      print('🔋 Wake lock DISABLED on shutdown');
    } catch (e) {
      print('❌ Failed to disable wake lock on dispose: $e');
    }
  }
}
