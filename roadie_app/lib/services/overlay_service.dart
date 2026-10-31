import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io' show Platform;

/// Professional Overlay Service for Roadie App
/// 
/// Features:
/// - System overlay permission management
/// - Floating widget control
/// - Background service integration
/// - Quick access functionality
/// - Request alert handling
/// - Production-ready for 500+ users
class OverlayService {
  static final OverlayService _instance = OverlayService._internal();
  factory OverlayService() => _instance;
  OverlayService._internal();

  // Configuration keys
  static const String _prefKey = 'overlay_enabled';
  static const String _permissionAskedKey = 'overlay_permission_asked';
  
  // Platform channels for native overlay
  static const MethodChannel _channel = MethodChannel('vehix/overlay');
  static const MethodChannel _backgroundChannel = MethodChannel('srs/background');
  
  // State management
  bool _isInitialized = false;
  bool _isEnabled = false;
  bool _hasPermission = false;
  bool _isOverlayVisible = false;
  bool _isRoadieOnline = false;
  bool _isAppInForeground = true;
  Timer? _statusCheckTimer;
  
  // Stream controllers for state management
  final StreamController<bool> _overlayStateController = StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _requestAlertController = StreamController<Map<String, dynamic>>.broadcast();
  
  Stream<bool> get overlayStateStream => _overlayStateController.stream;
  Stream<Map<String, dynamic>> get requestAlertStream => _requestAlertController.stream;

  /// Initialize the overlay service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load user preferences
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_prefKey) ?? true;
      
      // Check permission status
      await _checkPermissionStatus();
      
      // Set up background service
      await _setupBackgroundService();
      
      // Start status monitoring
      _startStatusMonitoring();
      
      _isInitialized = true;
      print('🎯 OverlayService initialized successfully');
    } catch (e) {
      print('❌ OverlayService initialization failed: $e');
    }
  }

  /// Request overlay permission
  Future<bool> requestOverlayPermission() async {
    if (!Platform.isAndroid) {
      print('⚠️ Overlay not supported on iOS');
      return false;
    }
    
    try {
      // Check current permission status
      final status = await Permission.systemAlertWindow.status;
      
      if (status.isGranted) {
        _hasPermission = true;
        return true;
      }
      
      // Request permission
      final result = await Permission.systemAlertWindow.request();
      
      if (result.isGranted) {
        _hasPermission = true;
        
        // Save that we asked for permission
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_permissionAskedKey, true);
        
        print('✅ Overlay permission granted');
        return true;
      } else {
        _hasPermission = false;
        print('❌ Overlay permission denied');
        return false;
      }
    } catch (e) {
      print('❌ Failed to request overlay permission: $e');
      return false;
    }
  }

  /// Show floating overlay widget
  Future<void> showOverlay() async {
    if (!Platform.isAndroid) return;
    if (!_isInitialized || !_hasPermission || !_isEnabled) return;
    
    try {
      await _channel.invokeMethod('showOverlay', {
        'isOnline': _isRoadieOnline,
        'appIcon': 'assets/smart_mobility_logo.png',
      });
      _isOverlayVisible = true;
      _overlayStateController.add(true);
      print('🎯 Overlay widget shown');
    } catch (e) {
      print('❌ Failed to show overlay: $e');
    }
  }

  /// Hide floating overlay widget
  Future<void> hideOverlay() async {
    if (!Platform.isAndroid) return;
    if (!_isInitialized) return;
    
    try {
      await _channel.invokeMethod('hideOverlay');
      _isOverlayVisible = false;
      _overlayStateController.add(false);
      print('🎯 Overlay widget hidden');
    } catch (e) {
      print('❌ Failed to hide overlay: $e');
    }
  }

  /// Update overlay status (online/offline)
  Future<void> updateRoadieStatus(bool isOnline) async {
    _isRoadieOnline = isOnline;
    
    if (isOnline && _isEnabled && _hasPermission && !_isAppInForeground) {
      await showOverlay();
    } else {
      await hideOverlay();
    }
    
    // Update background service
    if (Platform.isAndroid) {
      try {
        await _backgroundChannel.invokeMethod('updateStatus', {'isOnline': isOnline});
      } catch (e) {
        print('⚠️ Failed to update background status: $e');
      }
    }
    
    print('🎯 Roadie status updated: ${isOnline ? "ONLINE" : "OFFLINE"}');
  }

  /// Handle app lifecycle changes
  Future<void> handleLifecycleChange(bool isInForeground) async {
    if (!Platform.isAndroid) return;
    _isAppInForeground = isInForeground;
    
    if (isInForeground) {
      // Hide overlay when app comes to foreground
      await hideOverlay();
    } else if (_isRoadieOnline && _isEnabled && _hasPermission) {
      // Show overlay when app goes to background if online
      await showOverlay();
    }
  }

  /// Show urgent request alert on overlay
  Future<void> showRequestAlert(Map<String, dynamic> requestData) async {
    if (!Platform.isAndroid) return;
    if (!_isOverlayVisible) return;
    
    try {
      await _channel.invokeMethod('showRequestAlert', requestData);
      _requestAlertController.add(requestData);
      
      // Also show notification
      await _backgroundChannel.invokeMethod('showNotification', {
        'title': 'New Service Request!',
        'body': 'Someone needs roadside assistance nearby',
        'data': requestData,
      });
      
      print('🎯 Request alert shown on overlay');
    } catch (e) {
      print('❌ Failed to show request alert: $e');
    }
  }

  /// Enable/disable overlay feature
  Future<void> setEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    if (!_isInitialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, enabled);
      _isEnabled = enabled;
      
      if (enabled && _isRoadieOnline && _hasPermission) {
        await showOverlay();
      } else {
        await hideOverlay();
      }
      
      print('🎯 Overlay ${enabled ? "enabled" : "disabled"}');
    } catch (e) {
      print('❌ Failed to set overlay enabled: $e');
    }
  }

  /// Get current state
  bool get isActive => _isOverlayVisible;
  bool get isEnabled => _isEnabled;
  bool get hasPermission => _hasPermission;
  bool get isRoadieOnline => _isRoadieOnline;

  /// Dispose the service
  Future<void> dispose() async {
    _statusCheckTimer?.cancel();
    _overlayStateController.close();
    _requestAlertController.close();
    
    // Hide overlay and stop background service
    await hideOverlay();
    if (Platform.isAndroid) {
      try {
        await _backgroundChannel.invokeMethod('stopService');
      } catch (e) {
        print('⚠️ Failed to stop background service: $e');
      }
    }
    
    print('🎯 OverlayService disposed');
  }

  // Private methods

  Future<void> _checkPermissionStatus() async {
    if (!Platform.isAndroid) {
      _hasPermission = false;
      return;
    }
    
    try {
      final status = await Permission.systemAlertWindow.status;
      _hasPermission = status.isGranted;
      print('🎯 Overlay permission status: ${_hasPermission ? "GRANTED" : "DENIED"}');
    } catch (e) {
      print('⚠️ Failed to check overlay permission: $e');
      _hasPermission = false;
    }
  }

  Future<void> _setupBackgroundService() async {
    if (!Platform.isAndroid) return;
    try {
      await _backgroundChannel.invokeMethod('initializeService', {
        'notificationTitle': 'SRS Mechanic',
        'notificationText': 'Ready to assist roadside',
      });
      print('🎯 Background service initialized');
    } catch (e) {
      print('⚠️ Failed to setup background service: $e');
    }
  }

  void _startStatusMonitoring() {
    _statusCheckTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
      try {
        // Check if app is still online and overlay should be visible
        if (_isRoadieOnline && _isEnabled && _hasPermission && !_isOverlayVisible && !_isAppInForeground) {
          await showOverlay();
        }
      } catch (e) {
        print('⚠️ Status monitoring check failed: $e');
      }
    });
  }

  /// Handle overlay tap (called from native code)
  Future<void> onOverlayTapped() async {
    if (!Platform.isAndroid) return;
    try {
      // Bring app to foreground
      await _channel.invokeMethod('bringAppToFront');
      
      // Navigate to main screen or requests screen
      // This will be handled by the app's main navigator
      print('🎯 Overlay tapped - bringing app to front');
    } catch (e) {
      print('❌ Failed to handle overlay tap: $e');
    }
  }

  /// Handle request alert tap (called from native code)
  Future<void> onRequestAlertTapped(Map<String, dynamic> requestData) async {
    if (!Platform.isAndroid) return;
    try {
      // Bring app to foreground and navigate to request details
      await _channel.invokeMethod('bringAppToFront');
      
      // Emit request data for app to handle
      _requestAlertController.add(requestData);
      
      print('🎯 Request alert tapped - navigating to request');
    } catch (e) {
      print('❌ Failed to handle request alert tap: $e');
    }
  }
}
