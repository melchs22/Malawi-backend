import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:roadie_app/screens/login_screen.dart';
import 'package:roadie_app/screens/ride_screen.dart';

import 'package:roadie_app/services/api_service.dart';
import 'package:roadie_app/services/websocket_service.dart';
import 'package:roadie_app/services/network_service.dart';
import 'package:roadie_app/screens/notifications_screen.dart';
import 'package:roadie_app/widgets/app_drawer.dart';
import 'package:roadie_app/core/cache/cache_manager.dart';
import 'package:roadie_app/services/overlay_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:roadie_app/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  final String role;
  final bool isFreshLogin;
  const HomeScreen({required this.role, this.isFreshLogin = false, super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _isNavigatingToRide = false;
  LatLng? currentLocation;
  StreamSubscription<Map<String, dynamic>>? _offerRequestSubscription;
  List<LatLng> roadieLocations = [];
  final WebSocketService ws = WebSocketService();
  String _loadingStatus = "Initializing...";
  bool _isReady = false;
  Map? activeOffer;
  StreamSubscription<Position>? _locationSubscription;
  final AudioPlayer _audioPlayer = AudioPlayer();
  Map<String, dynamic>? userData;
  bool _isOnline = false;
  final MapController _mapController = MapController();
  final Set<int> _processedRequestIds = {}; 
  Timer? _offerDialogTimer;
  bool _offerDialogActive = false;
  bool _isConnected = true;
  StreamSubscription<bool>? _networkSubscription;
  bool _shouldFollowUser = true; 
  int _unreadNotifCount = 0;
  StreamSubscription<String>? _sessionSubscription;
  Timer? _heartbeatTimer;

  final String _tileTemplate = 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _offerRequestSubscription = NotificationService.offerRequestStream.listen((requestData) {
      if (mounted) {
        final rawId = requestData['id'] ?? requestData['request_id'];
        final requestId = rawId != null ? (int.tryParse(rawId.toString()) ?? (rawId is int ? rawId : -1)) : -1;
        
        if (requestId != -1 && _processedRequestIds.contains(requestId)) {
          debugPrint("⚠️ [RODIE] Stream listener skipping already-processed request $requestId");
          return;
        }
        if (requestId != -1) {
          _processedRequestIds.add(requestId);
          NotificationService.markAsProcessed(requestId);
        }
        _showOfferDialog(requestData);
      }
    });

    _checkPendingOfferRequest();
    
    // Configure audio for notifications so it bypasses media muting
    final audioContext = AudioContext(
      android: AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: true,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.notificationRingtone,
        audioFocus: AndroidAudioFocus.gainTransientExclusive,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
      ),
    );
    AudioPlayer.global.setAudioContext(audioContext);

    _loadCachedData();
    _initializeScreen();
    _sessionSubscription = ApiService.sessionInvalidatedStream.listen((message) {
      if (mounted) _showSessionInvalidatedDialog(message);
    });

    _networkSubscription = NetworkService().connectionStream.listen((connected) {
      if (mounted) setState(() => _isConnected = connected);
    });

    _fetchUnreadCount();
  }

  Future<void> _fetchUnreadCount() async {
    try {
      final notifs = await ApiService.getNotifications();
      if (mounted) {
        setState(() {
          _unreadNotifCount = notifs.where((n) => n['is_read'] == false).length;
        });
      }
    } catch (e) {
      debugPrint("Error fetching unread count: $e");
    }
  }

  void _loadCachedData() {
    final cache = CacheManager();
    final cachedLoc = cache.getLastLocation();
    if (cachedLoc != null) {
      currentLocation = LatLng(cachedLoc['lat']!, cachedLoc['lng']!);
    }
    final cachedProfile = cache.getUserProfile();
    if (cachedProfile != null) {
      userData = cachedProfile;
      final bool isApproved = cachedProfile['is_approved'] ?? false;
      _isOnline = isApproved ? (cachedProfile['is_online'] ?? false) : false;
      
      // Keep SharedPreferences updated with current user ID
      SharedPreferences.getInstance().then((prefs) {
        if (cachedProfile['id'] != null) {
          prefs.setString('logged_in_rodie_id', cachedProfile['id'].toString());
        }
      }).catchError((_) {});
    }
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (mounted) {
      _refreshUserData();
    }
  }

  Future<void> _refreshUserData() async {
    try {
      final userInfo = await ApiService.fetchUserInfo();
      if (mounted) {
        setState(() {
          userData = userInfo;
          final bool isApproved = userInfo?['is_approved'] ?? false;
          _isOnline = isApproved ? (userInfo?['is_online'] ?? false) : false;
        });
      }
    } catch (e) {
      debugPrint("Failed to refresh user data: $e");
    }
  }

  Future<void> _initializeScreen() async {
    try {
      final userInfo = await ApiService.fetchUserInfo();
      if (mounted) {
        final bool isApproved = userInfo?['is_approved'] ?? false;
        final bool isOnlineFromServer = userInfo?['is_online'] ?? false;
        
        setState(() {
          userData = userInfo;
          // Requirement: Upon logging back in (fresh login), they should remain offline by default.
          if (widget.isFreshLogin) {
            _isOnline = false;
          } else {
            _isOnline = isApproved ? isOnlineFromServer : false;
          }
        });

        if (userInfo != null) CacheManager().saveUserProfile(userInfo);

        // If it's a fresh login or they were online but not approved, sync with server to be offline
        if ((widget.isFreshLogin && isOnlineFromServer) || (!isApproved && isOnlineFromServer)) {
          await ApiService.updateRodieStatus(false);
        }

        if (widget.role == 'RODIE' && !isApproved) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Center(child: Text("Account Approval Pending", style: TextStyle(fontWeight: FontWeight.bold))),
                content: const Text("You'll be notified once your SRS account is approved to go online.", textAlign: TextAlign.center),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK", style: TextStyle(color: Color(0xFFFF8C00)))),
                ],
              ),
            );
          });
        }
      }
      // Fire and forget location to prevent blocking UI
      _initLocation();
      await _ensureOverlayPermission();
      if (mounted) setState(() => _loadingStatus = "Connecting...");
      await _connectWS().timeout(const Duration(seconds: 10));
      NetworkService().setWebSocketService(ws);
      if (mounted) {
        setState(() => _isReady = true);
        _sendInitialLocation();
        _startLocationBroadcast();
        
        // Initialize background/overlay service with current status
        await OverlayService().updateRoadieStatus(_isOnline);
      }
    } on SessionInvalidatedException catch (e) {
      if (mounted) _showSessionInvalidatedDialog(e.message);
    } catch (e) {
      if (mounted) setState(() => _loadingStatus = "Error: $e");
    }
  }

  void _showSessionInvalidatedDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Session Ended'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              final nav = Navigator.of(context);
              if (nav.canPop()) {
                nav.pop();
              }
              nav.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => LoginScreen(role: widget.role)),
                (route) => false,
              );
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool> _ensureLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Location services are off. Please enable GPS.'),
            action: SnackBarAction(label: 'Settings', onPressed: () => Geolocator.openLocationSettings()),
          ),
        );
      }
      return false;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // PROMINENT DISCLOSURE FOR GOOGLE PLAY & APP STORE
      // Apple policy 5.1.1(iv): The user must always proceed to the real system
      // permission dialog. No exit/decline button allowed on this pre-prompt.
      // The user can still deny location access inside the iOS system dialog.
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text("Location Access Required"),
          content: const Text("SRS Mechanic needs your location to find nearby emergency roadside requests and track your arrival time, even when the app is closed or not in use."),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CONTINUE"),
            ),
          ],
        ),
      );

      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Location permission denied permanently. Enable it in app settings.'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(label: 'Open Settings', onPressed: () => Geolocator.openAppSettings()),
          ),
        );
      }
      return false;
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<void> _ensureOverlayPermission() async {
    if (!Platform.isAndroid) return;
    
    // Request "Display over other apps" permission (System Alert Window)
    // This is required to show the offer dialog when the app is in background or locked.
    if (!await Permission.systemAlertWindow.isGranted) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text("Overlay Permission Required"),
            content: const Text("SRS needs permission to display over other apps so you can receive service requests even when using other apps or when your phone is locked."),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await Permission.systemAlertWindow.request();
                },
                child: const Text("GRANT PERMISSION"),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _initLocation() async {
    try {
      if (mounted) setState(() => _loadingStatus = 'Getting location...');
      
      final ok = await _ensureLocationPermission();
      if (!ok) {
        if (mounted && currentLocation == null) {
          setState(() => currentLocation = const LatLng(0.3356, 32.5830));
        }
        return;
      }

      Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        setState(() => currentLocation = LatLng(lastKnown.latitude, lastKnown.longitude));
        try { _mapController.move(currentLocation!, 15.0); } catch (_) {}
      }
      
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
      );


      if (mounted) {
        setState(() => currentLocation = LatLng(position.latitude, position.longitude));
        CacheManager().saveLastLocation(position.latitude, position.longitude);
        try { _mapController.move(currentLocation!, 16.0); } catch (_) {}
      }
    } catch (e) {
      debugPrint('Roadie _initLocation error: $e');
    }
  }

  Future<void> _connectWS() async {
    await ws.connect('ROADIE', (data) {
      if (!mounted) return;
      final messageType = (data["type"] ?? "").toString().toLowerCase();

      if (messageType == "session_invalidated") {
        if (mounted) {
          _showSessionInvalidatedDialog(data["message"] ?? "You have been logged out.");
        }
        ws.disconnect();
        ApiService.logout(); // Ensure token is deleted locally
        return;
      }

      // Handle session state synchronization for active rides
      if (messageType == "request_update") {
        final status = data["status"];
        final request = data["request"];
        if (mounted && request != null && !_isNavigatingToRide) {
          if (["ACCEPTED", "EN_ROUTE", "ARRIVED", "STARTED"].contains(status)) {
            if (ModalRoute.of(context)?.isCurrent == true) {
              _isNavigatingToRide = true;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => RideScreen(request: request, ws: ws),
                ),
              );
            }
          }
        }
        return;
      }

      if (messageType == "account.approved") {
        _handleAccountApproved(data);
        return;
      }
      if (messageType == "account.unapproved") {
        _handleAccountUnapproved(data);
        return;
      }
      
      if (messageType == "offer_request" || messageType == "new_request") {
        final rawId = data["request"]?['id'] ?? data["data"]?['id'] ?? data["request_id"];
        final requestId = rawId != null ? (int.tryParse(rawId.toString()) ?? rawId) : null;
        final requestData = data["request"] ?? data["data"] ?? data;
        if (requestId != null && _processedRequestIds.contains(requestId)) return;
        
        final isForeground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
        if (!isForeground) {
          debugPrint("⏳ [RODIE] WS received offer in background. Playing sound but letting FCM/Resume handle dialog.");
          _audioPlayer.setReleaseMode(ReleaseMode.release);
          _audioPlayer.play(AssetSource('Strong.mp3')).catchError((_) {});
          return;
        }

        if (requestId != null) {
          _processedRequestIds.add(requestId);
          // Sync to NotificationService so FCM handler also knows this ID is handled
          if (requestId is int) {
            NotificationService.markAsProcessed(requestId);
          }
        }
        
        if (mounted && requestId != null) {
          _showOfferDialog(requestData);
        }
      } else if (messageType == "request_cancelled") {
        // Rider cancelled — stop sound/vibration and dismiss any active offer dialog
        _audioPlayer.stop();
        _audioPlayer.setReleaseMode(ReleaseMode.release);
        Vibration.cancel();
        if (_offerDialogActive && mounted) {
          _dismissOfferDialog();
          if (Navigator.of(context).canPop()) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        }
        // Clear processed ID so future requests from same rider work
        final cancelledRequestId = data["request_id"];
        if (cancelledRequestId != null) _processedRequestIds.remove(cancelledRequestId);
        
        if (mounted) {
          _playCancellationSound();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Driver has cancelled the request"), backgroundColor: Colors.orange),
          );
        }
      } else if (messageType == "rodie_location" || messageType == "nearby_list" || messageType == "rodie_status") {
        if (mounted && data["type"] == "RODIE_LOCATION") {
          setState(() {
            roadieLocations = [LatLng(
              double.tryParse(data["lat"].toString()) ?? 0.0,
              double.tryParse(data["lng"].toString()) ?? 0.0,
            )];
          });
        } else if (mounted && data["type"] == "RODIE_STATUS") {
          final statusData = data["data"];
          if (statusData != null && statusData['rodie_id'].toString() == userData?['id'].toString()) {
            final bool newStatus = statusData['is_online'] ?? false;
            if (newStatus != _isOnline) {
              setState(() => _isOnline = newStatus);
              if (userData != null) {
                userData!['is_online'] = newStatus;
                CacheManager().saveUserProfile(userData!);
              }
            }
          }
        }
      }
    });
  }

  Future<void> _playAcceptanceSound() async {
    try {
      await _audioPlayer.stop();
      _audioPlayer.setReleaseMode(ReleaseMode.release);
      await _audioPlayer.play(AssetSource('Accept.mp3'));
      if (await Vibration.hasVibrator()) await Vibration.vibrate(pattern: [0, 300, 100, 300]);
    } catch (e) { debugPrint("Sound error: $e"); }
  }

  Future<void> _playCancellationSound() async {
    try {
      await _audioPlayer.stop();
      _audioPlayer.setReleaseMode(ReleaseMode.release);
      await _audioPlayer.play(AssetSource('cancel.mp3'));
      if (await Vibration.hasVibrator()) await Vibration.vibrate(pattern: [0, 300, 100, 300]);
    } catch (e) { debugPrint("Sound error: $e"); }
  }

  Future<void> _sendInitialLocation() async {
    if (!_isOnline) return;
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      ws.sendLocation(lat: position.latitude, lng: position.longitude);
    } catch (e) {
      debugPrint("Initial location high-accuracy error, using fallback: $e");
      if (currentLocation != null) {
        ws.sendLocation(lat: currentLocation!.latitude, lng: currentLocation!.longitude);
      } else {
        try {
          Position? lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null) {
            ws.sendLocation(lat: lastKnown.latitude, lng: lastKnown.longitude);
          }
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _offerRequestSubscription?.cancel();
    _sessionSubscription?.cancel();
    _locationSubscription?.cancel();
    _networkSubscription?.cancel();
    _heartbeatTimer?.cancel();
    _audioPlayer.dispose();
    _dismissOfferDialog();
    // Do not call ws.disconnect() here because ws is a shared singleton and is passed to RideScreen.
    // Disconnecting it here will kill the connection for RideScreen when HomeScreen is pushed/replaced.
    super.dispose();
  }

  void _startLocationBroadcast() {
    _locationSubscription?.cancel();
    _heartbeatTimer?.cancel();
    
    // 1. Distance-based updates (for when moving)
    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen((position) {
      if (mounted && _isReady) {
        final newLoc = LatLng(position.latitude, position.longitude);
        setState(() => currentLocation = newLoc);
        if (_isOnline) {
          ws.sendLocation(lat: position.latitude, lng: position.longitude);
        }
        CacheManager().saveLastLocation(position.latitude, position.longitude);
        if (_shouldFollowUser) {
          _mapController.move(newLoc, 16.0);
        }
      }
    });

    // 2. Frequency Heartbeat (every 30 seconds)
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && _isOnline && _isReady) {
        ws.send({'type': 'PING'});
      } else {
        timer.cancel();
      }
    });
  }

  void _resetMapToCurrentLocation() async {
    try {
      final ok = await _ensureLocationPermission();
      if (!ok) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Refreshing GPS location...'), duration: Duration(seconds: 1)),
        );
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
      );

      if (mounted) {
        setState(() {
          currentLocation = LatLng(position.latitude, position.longitude);
          _shouldFollowUser = true;
        });
        _mapController.move(currentLocation!, 16.0);
      }
    } catch (e) {
      try {
        Position? lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null && mounted) {
          setState(() {
            currentLocation = LatLng(lastKnown.latitude, lastKnown.longitude);
            _shouldFollowUser = true;
          });
          _mapController.move(currentLocation!, 16.0);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Map centered to last known location'), duration: Duration(seconds: 2)),
          );
          return;
        }
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get GPS fix. Check signal.'), backgroundColor: Colors.orange),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF10223D), Color(0xFF1D3B63)])),
          child: Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 24),
              Text(_loadingStatus, style: const TextStyle(color: Colors.white, fontSize: 16)),
            ]),
          ),
        ),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) { if (!didPop) SystemNavigator.pop(); },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white, elevation: 2, foregroundColor: const Color(0xFF10223D), title: const Text(""),
          actions: [
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_none, size: 26),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                    );
                    _fetchUnreadCount(); // Refresh count when coming back
                  },
                ),
                if (_unreadNotifCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        _unreadNotifCount > 9 ? '9+' : '$_unreadNotifCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12.0), 
              child: Icon(_isConnected ? Icons.wifi : Icons.wifi_off, color: _isConnected ? Colors.green : Colors.red, size: 20)
            ),
          ],

        ),
        drawer: AppDrawer(
          userData: userData,
          onRefresh: _refreshUserData,
        ),
        body: Stack(children: [
          RepaintBoundary(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: currentLocation ?? const LatLng(0.3476, 32.5825), // Default to Kampala Center
                initialZoom: 15,
                onPositionChanged: (pos, hasGesture) {
                  if (hasGesture && _shouldFollowUser) {
                    setState(() => _shouldFollowUser = false);
                  }
                },
              ),
              children: [
                TileLayer(urlTemplate: _tileTemplate, subdomains: const ['a', 'b', 'c', 'd'], userAgentPackageName: 'com.srs.roadie'),
                MarkerLayer(markers: [
                  if (currentLocation != null && currentLocation!.latitude != 0.0) 
                    Marker(point: currentLocation!, width: 60, height: 60, child: _buildLocationMarker())
                ]),
              ],
            ),
          ),
          _buildStatusBanner(),
          if (!_isConnected) _buildNetworkErrorBanner(),
        ]),
        floatingActionButton: FloatingActionButton(onPressed: _resetMapToCurrentLocation, backgroundColor: const Color(0xFFFF8C00), foregroundColor: Colors.white, child: const Icon(Icons.my_location)),
      ),
    );
  }

  Widget _buildLocationMarker() {
    return Stack(alignment: Alignment.center, children: [
      Container(width: 60, height: 60, decoration: BoxDecoration(color: const Color(0xFF10223D).withValues(alpha: 0.12), shape: BoxShape.circle)),
      Container(width: 22, height: 22, decoration: BoxDecoration(color: const Color(0xFFFF8C00), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3))),
    ]);
  }

  Widget _buildStatusBanner() {
    String subtitle = _isOnline ? "Waiting for requests" : "Drivers need your help. Go online to assist.";
    bool isApproved = userData?['is_approved'] == true;
    bool servicesSelected = userData?['services_selected'] == true;
    final double balance = double.tryParse(userData?['wallet']?['balance']?.toString() ?? '0.0') ?? 0.0;
    final double maxNeg = (userData?['max_negative_balance'] as num?)?.toDouble() ?? 0.0;
    bool balanceExceeded = balance < -maxNeg;
    if (!isApproved) {
      subtitle = "Account Pending Approval";
    } else if (!servicesSelected) {
      subtitle = "Select a service to provide";
    } else if (balanceExceeded) {
      subtitle = "Make payment first to go online";
    }
    return Positioned(
      top: 100, left: 20, right: 20,
      child: Container(
        padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20)]),
        child: Row(children: [
          Icon(Icons.online_prediction, color: _isOnline ? Colors.green : (isApproved && servicesSelected && !balanceExceeded ? Colors.grey : Colors.red)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_isOnline ? "Status: Online" : "Status: Offline", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            Text(subtitle, style: TextStyle(fontSize: 12, color: _isOnline || (isApproved && servicesSelected && !balanceExceeded) ? Colors.grey[600] : Colors.red[700], fontWeight: _isOnline ? FontWeight.normal : FontWeight.w500)),
          ])),
          Switch(
            value: _isOnline, activeThumbColor: const Color(0xFFFF8C00),
            onChanged: (val) async {
              if (val) {
                // Ensure we have the latest balance and platform settings (max_negative_balance)
                if (mounted) setState(() => _loadingStatus = "Checking account status...");
                await _refreshUserData(); 
                if (mounted) setState(() => _loadingStatus = "");
                
                // Re-calculate after refresh
                final double currentBalance = double.tryParse(userData?['wallet']?['balance']?.toString() ?? '0.0') ?? 0.0;
                final double currentMaxNeg = (userData?['max_negative_balance'] as num?)?.toDouble() ?? 0.0;
                final bool isApproved = userData?['is_approved'] == true;
                final bool servicesSelected = userData?['services_selected'] == true;
                final bool isBalanceExceeded = currentBalance < -currentMaxNeg;

                if (!isApproved) { _showCheckDialog("Account Pending Approval", "You’ll be notified once your SRS account is approved to go online."); return; }
                if (!servicesSelected) { _showCheckDialog("Select a service", "Please select at least one service you intend to provide before going online."); return; }
                if (isBalanceExceeded) { _showCheckDialog("Balance Exceeded", "Your negative balance (UGX $currentBalance) exceeds the allowed limit (UGX $currentMaxNeg). Please settle your balance in the wallet to go online."); return; }

                // iOS only: NIN was optional at sign-up (Apple policy 5.1.1v).
                // If the roadie skipped it, block going online until they add it via Profile.
                if (Platform.isIOS) {
                  final String nin = (userData?['nin'] ?? '').toString().trim();
                  if (nin.isEmpty || nin.length != 14) {
                    _showCheckDialog(
                      "Identity Verification Required",
                      "To go online and accept requests, you must complete identity verification.\n\nPlease go to your Profile and add your National Identification Number (NIN) before going online.",
                    );
                    return;
                  }
                }
              }
              setState(() => _isOnline = val);
              await ApiService.updateRodieStatus(val);
              
              // Trigger background/overlay service
              await OverlayService().updateRoadieStatus(val);
              
              if (val) _sendInitialLocation();
            },
          ),
        ]),
      ),
    );
  }

  void _showCheckDialog(String title, String content) {
    showDialog(context: context, builder: (context) => AlertDialog(title: Center(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))), content: Text(content, textAlign: TextAlign.center), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK", style: TextStyle(color: Color(0xFFFF8C00))))]));
  }

  Widget _buildNetworkErrorBanner() {
    return Positioned(top: 80, left: 16, right: 16, child: Container(padding: const EdgeInsets.all(12), color: Colors.red, child: const Text("No Network Connection", style: TextStyle(color: Colors.white))));
  }

  void _dismissOfferDialog() { _offerDialogTimer?.cancel(); _offerDialogTimer = null; _offerDialogActive = false; }

  void _showOfferDialog(Map request) {
    _dismissOfferDialog();
    
    // Clear any pending offer requests from SharedPreferences immediately to prevent duplicates on resume
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('pending_offer_request_id');
      prefs.remove('pending_offer_request_timestamp');
      prefs.remove('pending_offer_request_receive_time');
    }).catchError((_) {});
    
    // Calculate remaining seconds if local_receive_time or timestamp exists
    int timeLeft = 15;
    double receiveTime = 0.0;
    
    if (request['local_receive_time'] != null) {
      final val = request['local_receive_time'];
      if (val is num) {
        receiveTime = val.toDouble();
      } else {
        receiveTime = double.tryParse(val.toString()) ?? 0.0;
      }
    }
    
    if (receiveTime > 0.0) {
      final double nowSec = DateTime.now().millisecondsSinceEpoch / 1000.0;
      final int elapsed = (nowSec - receiveTime).round();
      timeLeft = 15 - elapsed;
      debugPrint("⏳ [RODIE] Calculated timeLeft: $timeLeft (nowSec: $nowSec, receiveTime: $receiveTime, elapsed: $elapsed)");
    } else {
      debugPrint("⏳ [RODIE] Fresh foreground request, starting full 15s timer");
    }
    
    // NOTE: processed list is now handled by the guard at the top of this method
    
    if (timeLeft <= 0) {
      debugPrint("⏳ [RODIE] Offer request already expired when modal would come up");
      return;
    }
    
    // Use an absolute expiry time so backgrounding the app doesn't pause the timer
    final DateTime expiryTime = DateTime.now().add(Duration(seconds: timeLeft));
    
    _offerDialogActive = true;
    
    // Play incoming request sound once (not looping) to prevent infinite ghost sound
    // if the OS suspends the app in the background before the 15s timer finishes.
    _audioPlayer.setReleaseMode(ReleaseMode.release);
    _audioPlayer.play(AssetSource('Strong.mp3')).catchError((e) {
      debugPrint("Warning: Strong.mp3 failed to play: $e");
    });
    
    Vibration.hasVibrator().then((hasVibrator) {
      if (hasVibrator == true) {
        Vibration.vibrate(pattern: [0, 500, 500, 500, 500, 500, 500, 500]);
      }
    });

    showDialog(
      context: context, barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          _offerDialogTimer ??= Timer.periodic(const Duration(seconds: 1), (timer) {
            if (!_offerDialogActive) { timer.cancel(); return; }
            final int newTimeLeft = expiryTime.difference(DateTime.now()).inSeconds;
            if (newTimeLeft > 0) { setDialogState(() => timeLeft = newTimeLeft); } 
            else { 
              timer.cancel(); 
              _audioPlayer.stop();
              _audioPlayer.setReleaseMode(ReleaseMode.release);
              Vibration.cancel();
              Navigator.pop(dialogContext); 
              ApiService.declineRequest(request['id']); 
            }
          });
          return Dialog(
            backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _buildDialogHeader(),
              Padding(padding: const EdgeInsets.all(24), child: Column(children: [_buildDialogInfo(request, timeLeft), const SizedBox(height: 24), _buildDialogActions(request, dialogContext)])),
            ]),
          );
        },
      ),
    ).then((_) => _dismissOfferDialog());
  }

  Widget _buildDialogHeader() { return Container(height: 100, width: double.infinity, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF10223D), Color(0xFF1D3B63)]), borderRadius: BorderRadius.vertical(top: Radius.circular(32))), child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text("🚨", style: TextStyle(fontSize: 30)), SizedBox(height: 4), Text("NEW REQUEST", style: TextStyle(color: Colors.white, letterSpacing: 2))])); }

  Widget _buildDialogInfo(Map request, int timeLeft) {
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(request['service_type_name'] ?? "Assist", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Text("${timeLeft}s", style: const TextStyle(color: Colors.red)))]),
      const SizedBox(height: 16), _buildInfoRow(Icons.location_on, "Distance", "${request['distance_km'] ?? '?'} km"),
    ]);
  }

  Widget _buildDialogActions(Map request, BuildContext dialogContext) {
    return Row(children: [
      Expanded(child: TextButton(onPressed: () { _audioPlayer.stop(); _audioPlayer.setReleaseMode(ReleaseMode.release); Vibration.cancel(); Navigator.pop(dialogContext); ApiService.declineRequest(request['id']); }, child: const Text("Decline"))),
      const SizedBox(width: 16),
      Expanded(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8C00), foregroundColor: Colors.white),
          onPressed: () async {
            _dismissOfferDialog();
            await _audioPlayer.stop();
            _audioPlayer.setReleaseMode(ReleaseMode.release);
            Vibration.cancel();
            final nav = Navigator.of(dialogContext);
            nav.pop();

            final response = await ApiService.acceptRequest(
              request['id'],
              lat: currentLocation?.latitude,
              lng: currentLocation?.longitude,
            );

            // SUCCESS: backend returns {'detail': 'Request accepted', 'request_id': ..., 'request': {...}}
            // The presence of 'request' or 'request_id' distinguishes a real success from an error.
            // Previously this check was (response['detail'] == null) which ALWAYS FAILED because the
            // success response also contains a 'detail' key ("Request accepted"), causing the Roadie
            // to see a "Request accepted" snackbar but never navigate to the RideScreen.
            final bool isSuccess = response != null &&
                (response['request'] != null || response['request_id'] != null);

            if (isSuccess) {
              _playAcceptanceSound();
              final fullRequest = (response['request'] != null)
                  ? Map<String, dynamic>.from(response['request'])
                  : Map<String, dynamic>.from(request);
              if (fullRequest["status"] == "REQUESTED") fullRequest["status"] = "ACCEPTED";

              // Guard against double-navigation (the WS request_update handler also navigates)
              if (!_isNavigatingToRide && mounted) {
                _isNavigatingToRide = true;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => RideScreen(request: fullRequest, ws: ws)),
                );
              }
            } else if (response != null) {
              // Only real errors reach here (e.g. "no longer available", "already on a job")
              final errorMsg = response['detail'] ?? response['error'] ?? 'Failed to accept request';
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
                );
              }
            }
          },
          child: const Text("ACCEPT"),
        ),
      ),
    ]);
  }

  Widget _buildInfoRow(IconData icon, String label, String value) { return Row(children: [Icon(icon, size: 20, color: Colors.blueGrey), const SizedBox(width: 12), Text("$label: $value")]); }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingOfferRequest();
    }
    OverlayService().handleLifecycleChange(state == AppLifecycleState.resumed);
  }

  Future<void> _checkPendingOfferRequest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // Force reload disk changes written by background FCM isolate
      final pendingIdStr = prefs.getString('pending_offer_request_id');
      final pendingTimestampStr = prefs.getString('pending_offer_request_timestamp');
      final pendingReceiveTime = prefs.getDouble('pending_offer_request_receive_time');
      
      if (pendingIdStr != null && pendingIdStr.isNotEmpty) {
        // Clear immediately so we don't process it twice
        await prefs.remove('pending_offer_request_id');
        await prefs.remove('pending_offer_request_timestamp');
        await prefs.remove('pending_offer_request_receive_time');
        
        final requestId = int.tryParse(pendingIdStr);
        if (requestId != null) {
          if (_processedRequestIds.contains(requestId)) return;
          _processedRequestIds.add(requestId); // Guard immediately
          NotificationService.markAsProcessed(requestId); // Sync to FCM handler
          
          debugPrint("📦 [RODIE] Found pending offer request $requestId in storage on resume");
          final requestData = await ApiService.getRequestDetails(requestId);
          if (requestData != null) {
            if (pendingReceiveTime != null) {
              requestData['local_receive_time'] = pendingReceiveTime;
            }
            if (pendingTimestampStr != null && pendingTimestampStr.isNotEmpty) {
              requestData['timestamp'] = pendingTimestampStr;
            }
            _showOfferDialog(requestData);
          } else {
            // Revert guard if fetch failed
            _processedRequestIds.remove(requestId);
          }
        }
      }
    } catch (e) {
      debugPrint("Error checking pending offer request: $e");
    }
  }

  void _handleAccountApproved(Map data) async { await _refreshUserData(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Account Approved!"), backgroundColor: Colors.green)); }

  void _handleAccountUnapproved(Map data) async { setState(() => _isOnline = false); await ApiService.updateRodieStatus(false); await _refreshUserData(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Account Unapproved by Admin"), backgroundColor: Colors.orange)); }

}
