import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:rider_app/services/api_service.dart';
import 'package:rider_app/services/websocket_service.dart';
import 'package:rider_app/services/network_service.dart';
import 'package:rider_app/screens/requesting_screen.dart';
import 'package:rider_app/screens/ride_screen.dart';
import 'package:rider_app/widgets/app_drawer.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:rider_app/widgets/skeleton_loader.dart';
import 'package:rider_app/core/cache/cache_manager.dart';
import 'package:rider_app/screens/service_detail_screen.dart';
import 'package:rider_app/screens/notifications_screen.dart';
import 'package:rider_app/screens/login_screen.dart';


class HomeScreen extends StatefulWidget {
  final String role;
  final WebSocketService? ws;
  const HomeScreen({required this.role, this.ws, super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  LatLng? currentLocation;
  List<LatLng> roadieLocations = [];
  List<Map<String, dynamic>> roadieData = [];
  String _loadingStatus = "Initializing...";
  bool _isReady = false;
  List<dynamic> services = [];
  bool _loadingServices = true;
  Map<String, dynamic>? userData;
  final MapController _mapController = MapController();
  late final WebSocketService ws;
  
  // Network status monitoring
  bool _isConnected = true;
  StreamSubscription<bool>? _networkSubscription;
  
  // Stream-based location tracking
  StreamSubscription<Position>? _locationSubscription;
  bool _shouldFollowUser = true;
  StreamSubscription<String>? _sessionSubscription;

  int _unreadNotifCount = 0;

  final String _tileTemplate = 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';

  @override
  void initState() {
    super.initState();
    ws = widget.ws ?? WebSocketService();
    NetworkService().setWebSocketService(ws);
    _loadCachedData();
    _initializeScreen();
    _sessionSubscription = ApiService.sessionInvalidatedStream.listen((message) {
      if (mounted) _showSessionInvalidatedDialog(message);
    });

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

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (mounted) _refreshServices();
  }

  void _loadCachedData() {
    final cache = CacheManager();
    final cachedLoc = cache.getLastLocation();
    if (cachedLoc != null) {
      currentLocation = LatLng(cachedLoc['lat']!, cachedLoc['lng']!);
    }
    final cachedServices = cache.getServices();
    if (cachedServices != null && cachedServices.isNotEmpty) {
      services = cachedServices;
      _loadingServices = false;
    }
    final cachedProfile = cache.getUserProfile();
    if (cachedProfile != null) {
      userData = cachedProfile;
    }
  }

  Future<void> _refreshServices() async {
    try {
      final serviceList = await ApiService.getServices().timeout(const Duration(seconds: 8));
      if (mounted) {
        setState(() {
          services = serviceList;
          _loadingServices = false;
        });
        if (serviceList.isNotEmpty) {
          CacheManager().saveServices(serviceList);
        }
      }
    } catch (e) {
      debugPrint("❌ Failed to fetch services from API: $e");
      if (mounted && services.isEmpty) {
        final cachedServices = CacheManager().getServices();
        setState(() {
          services = (cachedServices != null && cachedServices.isNotEmpty)
              ? cachedServices
              : [];
          _loadingServices = false;
        });
      }
    }
  }

  Future<void> _initializeScreen() async {
    try {
      // Fire and forget location so it doesn't block the UI render
      _initLocation();
      
      final results = await Future.wait<dynamic>([
        _connectWS().timeout(const Duration(seconds: 10)),           
        ApiService.fetchUserInfo().timeout(const Duration(seconds: 8)), 
        _fetchServices(),
        _checkActiveRequest(),                                            
      ], eagerError: false);

      final userInfo = results[1] as Map<String, dynamic>?;
      if (userInfo != null && mounted) {
        setState(() => userData = userInfo);
        CacheManager().saveUserProfile(userInfo);
      }
      ApiService.getProfilePhotoUrl();
      if (mounted) {
        setState(() => _isReady = true);
      }
    } on SessionInvalidatedException catch (e) {
      if (mounted) _showSessionInvalidatedDialog(e.message);
    } catch (e) {
      debugPrint("HomeScreen init error: $e");
      if (mounted) {
        setState(() {
          _loadingStatus = "Connection issues, checking...";
          _isReady = true; 
        });
      }
    }
  }
  
  Future<void> _checkActiveRequest() async {
    try {
      final activeRequests = await ApiService.getMyRequests(status: 'active');
      if (activeRequests.isNotEmpty && mounted) {
        final request = activeRequests.first;
        final status = request['status']?.toString().toUpperCase();
        
        debugPrint("🔄 [HomeScreen] Found active request: $status (ID: ${request['id']})");

        if (status == "REQUESTED") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => RequestingScreen(request: request, ws: ws),
            ),
          );
        } else if (["ACCEPTED", "EN_ROUTE", "ARRIVED", "STARTED"].contains(status)) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => RideScreen(request: request, isRoadie: false, ws: ws),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error checking active request: $e");
    }
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    _locationSubscription?.cancel();
    _networkSubscription?.cancel();
    // Do NOT call ws.disconnect() here — the WS is a singleton shared across
    // screens. Disconnecting it kills the connection for the ride/requesting
    // screens that are still using it. Only disconnect on explicit user logout.
    super.dispose();
  }

  Future<void> _fetchServices() async {
    try {
      final serviceList = await ApiService.getServices().timeout(const Duration(seconds: 8));
      if (mounted) {
        setState(() {
          services = serviceList;
          _loadingServices = false;
        });
        if (serviceList.isNotEmpty) {
          CacheManager().saveServices(serviceList);
        }
      }
    } catch (e) {
      if (mounted && services.isEmpty) {
        final cachedServices = CacheManager().getServices();
        setState(() {
          services = (cachedServices != null && cachedServices.isNotEmpty)
              ? cachedServices
              : [];
          _loadingServices = false;
        });
      }
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

  Future<void> _initLocation() async {
    try {
      if (mounted) setState(() => _loadingStatus = 'Getting location...');
      
      final ok = await _ensureLocationPermission();
      if (!ok) {
        if (mounted && currentLocation == null) {
          setState(() => currentLocation = const LatLng(0.3356, 32.5830));
        }
        _startLocationTracking();
        return;
      }

      // Show cached last-known position instantly while real GPS fix loads
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
        _startLocationTracking();
      }
    } catch (e) {
      debugPrint('Rider _initLocation error: $e');
      if (mounted && currentLocation == null) {
        setState(() => currentLocation = const LatLng(0.3356, 32.5830));
      }
      _startLocationTracking();
    }
  }

  void _startLocationTracking() {
    _locationSubscription?.cancel();
    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((position) {
      if (mounted) {
        final newLoc = LatLng(position.latitude, position.longitude);
        setState(() => currentLocation = newLoc);
        ws.sendLocation(lat: position.latitude, lng: position.longitude);
        CacheManager().saveLastLocation(position.latitude, position.longitude);
        if (_shouldFollowUser) {
          _mapController.move(newLoc, 16.0);
        }
      }
    }, onError: (e) => debugPrint("Location tracking error: $e"));
  }

  Future<void> _connectWS() async {
    if (mounted) setState(() => _loadingStatus = "Connecting...");
    await ws.connect(widget.role, (data) {
      final type = data["type"];
      final typeLower = type?.toString().toLowerCase();
      
      if (typeLower == "session_invalidated") {
        if (mounted) {
          _showSessionInvalidatedDialog(data["message"] ?? "You have been logged out.");
        }
        ws.disconnect();
        ApiService.logout(); // Ensure token is deleted locally
        return;
      }

      // Handle state synchronization for active requests
      // Only navigate if this screen is the CURRENT visible route — prevents
      // the home screen from hijacking navigation when a ride/requesting screen
      // is already on top handling the same WS messages.
      if (typeLower == "request_update") {
        final status = data["status"];
        final request = data["request"];
        final isCurrentRoute = mounted && (ModalRoute.of(context)?.isCurrent ?? false);
        if (isCurrentRoute && request != null) {
          if (status == "REQUESTED") {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => RequestingScreen(request: request, ws: ws),
              ),
            );
          } else if (["ACCEPTED", "EN_ROUTE", "ARRIVED", "STARTED"].contains(status)) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => RideScreen(request: request, isRoadie: false, ws: ws),
              ),
            );
          }
        }
        return;
      }

      if (typeLower == "rodie_location" || typeLower == "nearby_list" || typeLower == "rodie_status") {
        if (mounted) {
          setState(() {
            if (typeLower == "rodie_location") {
              final roadieId = data["rodie_id"] ?? data["id"];
              if (roadieId == null) return;
              
              final roadie = {
                'id': roadieId,
                'lat': double.tryParse(data["lat"].toString()) ?? 0.0,
                'lng': double.tryParse(data["lng"].toString()) ?? 0.0,
                'username': data["username"] ?? "Mechanic",
              };
              final index = roadieData.indexWhere((r) => r['id'] == roadieId);
              if (index != -1) {
                roadieData[index] = roadie;
              } else {
                roadieData.add(roadie);
              }
            } else if (typeLower == "nearby_list") {
              final List<dynamic> roadies = data["roadies"] ?? [];
              roadieData = [];
              for (final roadie in roadies) {
                final lat = roadie["lat"];
                final lng = roadie["lng"];
                final roadieId = roadie["id"] ?? roadie["rodie_id"];
                if (lat != null && lng != null && roadieId != null) {
                  roadieData.add({
                    'id': roadieId,
                    'lat': double.tryParse(lat.toString()) ?? 0.0,
                    'lng': double.tryParse(lng.toString()) ?? 0.0,
                    'username': roadie["username"] ?? "Mechanic",
                  });
                }
              }
            } else if (typeLower == "rodie_status") {
              final statusData = data["data"] ?? data;
              final roadieId = statusData["rodie_id"] ?? statusData["id"];
              if (roadieId == null) return;
              
              final isOnline = statusData["is_online"];
              if (isOnline == true) {
                final lat = statusData["lat"];
                final lng = statusData["lng"];
                if (lat != null && lng != null) {
                  final roadie = {
                    'id': roadieId,
                    'lat': double.tryParse(lat.toString()) ?? 0.0,
                    'lng': double.tryParse(lng.toString()) ?? 0.0,
                    'username': statusData["username"] ?? "Mechanic",
                  };
                  final index = roadieData.indexWhere((r) => r['id'] == roadieId);
                  if (index != -1) {
                    roadieData[index] = roadie;
                  } else {
                    roadieData.add(roadie);
                  }
                }
              } else {
                roadieData.removeWhere((r) => r['id'] == roadieId);
              }
            }
          });
        }
      }
    });
  }

  void _resetMapToCurrentLocation() async {
    try {
      final ok = await _ensureLocationPermission();
      if (!ok) return;
      
      // Show immediate feedback
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Map centered to your location'), duration: Duration(seconds: 2)),
        );
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
    final location = currentLocation ?? const LatLng(0.3476, 32.5825);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) { if (!didPop) SystemNavigator.pop(); },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: const Color(0xFF10223D),
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
        drawer: AppDrawer(userData: userData),
        body: Stack(children: [
          RepaintBoundary(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: location, initialZoom: 15,
                onPositionChanged: (pos, hasGesture) {
                  if (hasGesture && _shouldFollowUser) {
                    setState(() => _shouldFollowUser = false);
                    debugPrint("📍 Rider panned map - following disabled");
                  }
                },
              ),
              children: [
                TileLayer(urlTemplate: _tileTemplate, subdomains: const ['a', 'b', 'c', 'd'], userAgentPackageName: 'com.srs.rider'),
                MarkerLayer(markers: [
                  if (currentLocation != null && currentLocation!.latitude != 0.0)
                    Marker(point: currentLocation!, width: 60, height: 60, child: _buildUserMarker()),
                  ...roadieData.map((roadie) => Marker(point: LatLng(roadie['lat'], roadie['lng']), width: 44, height: 44, child: _buildRoadieMarker(roadie['username']))),
                ]),
              ],
            ),
          ),
          Positioned(bottom: 0, left: 0, right: 0, child: SafeArea(child: _buildServiceSection())),
          if (!_isConnected) Positioned(top: 80, left: 16, right: 16, child: _buildNetworkBanner()),
        ]),
        floatingActionButton: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 80, right: 16),
          child: FloatingActionButton(onPressed: _resetMapToCurrentLocation, backgroundColor: const Color(0xFFFF8C00), foregroundColor: Colors.white, child: const Icon(Icons.my_location)),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }

  Widget _buildUserMarker() {
    return Stack(alignment: Alignment.center, children: [
      Container(width: 60, height: 60, decoration: BoxDecoration(color: const Color(0xFF10223D).withValues(alpha: 0.12), shape: BoxShape.circle)),
      Container(width: 22, height: 22, decoration: BoxDecoration(color: const Color(0xFF10223D), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: [BoxShadow(color: const Color(0xFF10223D).withValues(alpha: 0.3), blurRadius: 8, spreadRadius: 2)])),
    ]);
  }

  Widget _buildRoadieMarker(String username) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFFF8C00), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5), boxShadow: [BoxShadow(color: const Color(0xFFFF8C00).withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 1)]),
      child: const Icon(Icons.build, color: Colors.white, size: 22),
    );
  }

  Widget _buildNetworkBanner() {
    return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red[600], borderRadius: BorderRadius.circular(8)), child: const Row(children: [Icon(Icons.wifi_off, color: Colors.white, size: 20), SizedBox(width: 8), Text("No Network Connection", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]));
  }

  Widget _buildServiceSection() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 15, offset: const Offset(0, -5))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(width: double.infinity, child: Text("Request Assistance", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF10223D)))),
        const SizedBox(height: 12),
        SizedBox(height: 60, child: Row(children: [
          const SizedBox(width: 8), const Icon(Icons.chevron_left, color: Colors.grey),
          Expanded(child: _loadingServices ? ListView.builder(scrollDirection: Axis.horizontal, itemCount: 4, itemBuilder: (context, index) => const ServiceCardSkeleton()) : ListView.builder(scrollDirection: Axis.horizontal, itemCount: services.length, itemBuilder: (context, index) => _buildServiceCard(services[index]))),
          const Icon(Icons.chevron_right, color: Colors.grey), const SizedBox(width: 8),
        ])),
      ]),
    );
  }

  Widget _buildServiceCard(dynamic service) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceDetailScreen(serviceId: service['id'], serviceName: service['name'], description: service['description'] ?? '', currentLocation: currentLocation, ws: ws))),
      child: Container(width: 100, margin: const EdgeInsets.symmetric(horizontal: 10), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [_buildServiceImage(service), const SizedBox(height: 4), Flexible(child: Text(service['name'] ?? 'Unknown', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))]))
    );
  }

  Widget _buildServiceImage(Map<String, dynamic> service) {
    final String? imageUrl = service['image'];
    final String serviceName = service['name']?.toString().toLowerCase() ?? '';
    return Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 1.5), color: Colors.white), child: ClipOval(child: (imageUrl != null && imageUrl.isNotEmpty) ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (c, e, s) => Icon(_getServiceIcon(serviceName), size: 20)) : Icon(_getServiceIcon(serviceName), size: 20)));
  }

  IconData _getServiceIcon(String name) {
    if (name.contains('towing')) return Icons.local_shipping;
    if (name.contains('tire')) return Icons.tire_repair;
    if (name.contains('battery')) return Icons.battery_charging_full;
    if (name.contains('fuel')) return Icons.local_gas_station;
    if (name.contains('mechanic')) return Icons.build;
    return Icons.handyman;
  }
}
