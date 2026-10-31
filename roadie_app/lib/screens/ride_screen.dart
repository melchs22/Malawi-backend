import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import '../services/websocket_service.dart';
import '../services/api_service.dart';
import 'rating_screen.dart';
import 'home_screen.dart';

class RideScreen extends StatefulWidget {
  final Map request;
  final WebSocketService? ws; // Shared WS from HomeScreen (optional)
  const RideScreen({required this.request, this.ws, super.key});

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> {
  Map<String, dynamic> currentRequest = {};
  final MapController mapController = MapController();
  late final WebSocketService ws;
  List<Map<String, dynamic>> messages = [];
  bool _isConnected = false;
  bool _ownsWs = false; // Whether this screen created the WS
  WSCallback? _rideHandler; // Store handler reference
  Timer? locationTimer;
  bool _isChatOpen = false;
  bool _isProcessing = false; // Add debouncing flag
  bool _isCancelled = false; // Prevent duplicate cancellation dialogs
  bool _isRatingPushed = false; // Prevent double navigation to RatingScreen
  final Set<String> _shownStatuses = {}; // Prevent duplicate status alerts
  double _sliderValue = 0.0; // Add slider state
  int _unreadCount = 0;
  
  LatLng riderLocation = const LatLng(0, 0);
  LatLng roadieLocation = const LatLng(0, 0);
  final TextEditingController chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    // Use shared WS if provided, otherwise create new (fallback for splash screen)
    if (widget.ws != null) {
      ws = widget.ws!;
      _ownsWs = false;
    } else {
      ws = WebSocketService();
      _ownsWs = true;
    }
    currentRequest = Map<String, dynamic>.from(widget.request);
    
    // Ensure status is set to ACCEPTED if missing (since we just accepted it to get here)
    if (currentRequest["status"] == null) {
      currentRequest["status"] = "ACCEPTED";
    }
    
    _parseInitialLocations();
    _setupWSHandler();
    _loadChatHistory(); // Load previous messages
    startSendingLocation();
  }

  void _parseInitialLocations() {
    try {
      if (currentRequest["rider_lat"] != null) {
        double lat =
            double.tryParse(currentRequest["rider_lat"].toString()) ?? 0.0;
        double lng =
            double.tryParse(currentRequest["rider_lng"].toString()) ?? 0.0;
        if (lat != 0) riderLocation = LatLng(lat, lng);
      }
      if (currentRequest["roadie_lat"] != null) {
        double lat =
            double.tryParse(currentRequest["roadie_lat"].toString()) ?? 0.0;
        double lng =
            double.tryParse(currentRequest["roadie_lng"].toString()) ?? 0.0;
        if (lat != 0) roadieLocation = LatLng(lat, lng);
      } else {
        roadieLocation = riderLocation;
      }
    } catch (e) {
      debugPrint("Error parsing initial locations: $e");
    }
  }

  void _setupWSHandler() async {
    // Create and store handler for cleanup on dispose
    _rideHandler = (data) {
      if (!mounted) return;

      final type = data["type"];
      final typeLower = type?.toString().toLowerCase();

      if (typeLower == "rodie_location") {
        setState(() {
          roadieLocation = LatLng(
            double.parse(data["lat"].toString()),
            double.parse(data["lng"].toString()),
          );
        });
        _moveMap();
      } else if (typeLower == "rider_location") {
        setState(() {
          riderLocation = LatLng(
            double.parse(data["lat"].toString()),
            double.parse(data["lng"].toString()),
          );
        });
        _moveMap();
      } else if (typeLower == "request_cancelled") {
        if (!_isCancelled) {
          _isCancelled = true;
          _playCancellationSound();
          _showRideCancelledInfoDialog(data["message"] ?? "The Driver has cancelled this request.");
        }
      } else if (typeLower == "ws_reconnected") {
        debugPrint("🔄 [Roadie] WS reconnected, re-joining request room");
        ws.send({"type": "JOIN_REQUEST", "request_id": currentRequest["id"]});
        if (mounted) setState(() => _isConnected = true);
      } else if (typeLower == "chat_message" || typeLower == "chat_notification") {
        if (data["sender_role"] != "RODIE") {
          final isDuplicate = messages.any((m) =>
              m["text"] == data["text"] &&
              m["sender_id"] == data["sender_id"] &&
              m["created_at"] == data["created_at"]);

          if (!isDuplicate) {
            setState(() {
              messages.add(data);
              if (!_isChatOpen) _unreadCount++;
            });
            if (_isChatOpen) _scrollChatToBottom();
          }

          if (!_isChatOpen && mounted && !isDuplicate) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${data["sender_name"] ?? "Driver"}: ${data["text"]}'),
                duration: const Duration(seconds: 3),
                backgroundColor: const Color(0xFF10223D),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(
                  label: 'VIEW',
                  textColor: const Color(0xFFFF8C00),
                  onPressed: () => setState(() {
                    _isChatOpen = true;
                    _unreadCount = 0;
                  }),
                ),
              ),
            );
          }
        }
      } else if (typeLower == "request_update" ||
          typeLower == "request_arrived" ||
          typeLower == "request_enroute" ||
          typeLower == "request_started" ||
          typeLower == "request_completed") {
        debugPrint("🔄 [Roadie] Received update: $data");

        if (data["request"] != null) {
          setState(() => currentRequest = data["request"]);
        }

        final status = data["request"]?["status"] ?? data["status"];

        // Guard: only show each status alert once
        if (_shownStatuses.contains(status)) return;
        _shownStatuses.add(status);

        if (status == "ARRIVED") {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Arrival confirmed!")));
        } else if (status == "STARTED") {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Assist has started")));
        } else if (status == "COMPLETED") {
          if (mounted && !_isRatingPushed) {
            _isRatingPushed = true;
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => RatingScreen(request: currentRequest),
                transitionsBuilder: (context, animation, secondaryAnimation, child) => FadeTransition(opacity: animation, child: child),
                transitionDuration: const Duration(milliseconds: 600),
              ),
            );
          }
        } else if (status == "CANCELLED" && !_isCancelled) {
          _isCancelled = true;
          _playCancellationSound();
          _showRideCancelledInfoDialog(data["message"] ?? "This request has been cancelled.");
        }
      }
    };

    if (_ownsWs) {
      await ws.connect('ROADIE', _rideHandler!);
    } else {
      ws.addHandler(_rideHandler!);
    }

    if (mounted) {
      setState(() => _isConnected = ws.isConnected);
      ws.send({"type": "JOIN_REQUEST", "request_id": currentRequest["id"]});
    }
  }

  Future<void> _loadChatHistory() async {
    final requestId = currentRequest["id"];
    if (requestId == null) return;

    final history = await ApiService.fetchChatHistory(requestId);
    if (mounted && history.isNotEmpty) {
      setState(() {
        messages = List<Map<String, dynamic>>.from(history);
      });
    }
  }

  void startSendingLocation() {
    // Run once immediately
    _sendLocationTick();
    
    // Then start periodic timer
    locationTimer = Timer.periodic(const Duration(seconds: 5), (_) => _sendLocationTick());
  }

  Future<void> _sendLocationTick() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      int? riderId;
      if (currentRequest["rider_id"] != null) {
        riderId = int.tryParse(currentRequest["rider_id"].toString());
      } else if (currentRequest["rider"] is Map && currentRequest["rider"]["id"] != null) {
        riderId = int.tryParse(currentRequest["rider"]["id"].toString());
      } else if (widget.request["rider_id"] != null) {
        riderId = int.tryParse(widget.request["rider_id"].toString());
      } else if (widget.request["rider"] is Map && widget.request["rider"]["id"] != null) {
        riderId = int.tryParse(widget.request["rider"]["id"].toString());
      }

      ws.sendLocation(
        lat: position.latitude,
        lng: position.longitude,
        riderId: riderId
      );
      if (mounted) {
        setState(() {
          roadieLocation = LatLng(position.latitude, position.longitude);
        });
        // Added: Move map locally so roadie sees instant feedback
        _moveMap();
      }
    } catch (e) {
      debugPrint("Roadie location update error: $e");
    }
  }

  void sendChat() {
    final text = chatController.text.trim();
    if (text.isEmpty) return;
    // Optimistically add message to local list so it shows immediately
    setState(() {
      messages.add({
        "type": "CHAT_MESSAGE",
        "sender_role": "RODIE",
        "sender_name": "You",
        "text": text,
        "created_at": DateTime.now().toIso8601String(),
      });
    });
    ws.send({
      "type": "CHAT",
      "request_id": int.tryParse(currentRequest["id"].toString()) ?? currentRequest["id"],
      "text": text,
    });
    chatController.clear();
    _scrollChatToBottom();
  }

  void _scrollChatToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatMessageTime(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final hour = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$hour:$min';
    } catch (_) {
      return '';
    }
  }

  void _moveMap() {
    try {
      if (riderLocation.latitude != 0 && roadieLocation.latitude != 0) {
        final center = LatLng(
          (riderLocation.latitude + roadieLocation.latitude) / 2,
          (riderLocation.longitude + roadieLocation.longitude) / 2,
        );
        mapController.move(center, mapController.camera.zoom);
      }
    } catch (_) {
      // Map might not be ready yet
    }
  }

  Future<void> _playCancellationSound() async {
    try {
      await _audioPlayer.stop();
      _audioPlayer.setReleaseMode(ReleaseMode.release);
      await _audioPlayer.play(AssetSource('cancel.mpeg'));
      if (await Vibration.hasVibrator()) await Vibration.vibrate(pattern: [0, 300, 100, 300]);
    } catch (e) {
      debugPrint("Error playing cancellation sound: $e");
    }
  }

  void confirmArrival() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    
    try {
      // Backend requires ACCEPTED → EN_ROUTE → ARRIVED
      // If still ACCEPTED, mark EN_ROUTE first
      if (currentRequest["status"] == "ACCEPTED") {
        debugPrint("📍 [RoadieRide] Status is ACCEPTED — calling enroute first");
        final enrouteResult = await ApiService.post(
          "/requests/${currentRequest["id"]}/enroute/",
          {},
          requiresAuth: true,
        );
        if (enrouteResult == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Failed to mark en-route. Please try again."),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        if (mounted) {
          setState(() => currentRequest["status"] = "EN_ROUTE");
        }
        debugPrint("✅ [RoadieRide] EN_ROUTE set, now calling arrived");
      }

      final result = await ApiService.post(
        "/requests/${currentRequest["id"]}/arrived/",
        {},
        requiresAuth: true,
      );
      if (mounted) {
        if (result != null) {
          setState(() {
            currentRequest["status"] = "ARRIVED";
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Failed to confirm arrival. Please try again."),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error confirming arrival: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void startAssist() async {
    if (_isProcessing) return; // Prevent multiple calls
    setState(() => _isProcessing = true);
    
    try {
      final result = await ApiService.post(
        "/requests/${currentRequest["id"]}/start/",
        {},
        requiresAuth: true,
      );
      if (mounted) {
        if (result != null) {
          setState(() {
            currentRequest["status"] = "STARTED";
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Assist started!")),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Failed to start assist. Please try again."),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error starting assist: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void completeAssist() async {
    if (_isProcessing) return; // Prevent multiple calls
    setState(() => _isProcessing = true);
    
    try {
      final result = await ApiService.post(
        "/requests/${currentRequest["id"]}/complete/",
        {},
        requiresAuth: true,
      );
      if (mounted) {
        if (result != null) {
          // Update status locally
          setState(() {
            currentRequest["status"] = "COMPLETED";
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Assist completed!")),
          );

          // Navigate to rating screen immediately
          if (mounted && !_isRatingPushed) {
            _isRatingPushed = true;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => RatingScreen(request: currentRequest),
              ),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Failed to complete assist. Please try again."),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error completing assist: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void cancelRequest() async {
    // Get current roadie location
    final lat = roadieLocation.latitude;
    final lng = roadieLocation.longitude;

    if (!mounted) return;

    // First fetch cancellation reasons
    final reasonsResponse = await ApiService.get(
      "/requests/cancellation-reasons/",
    );

    if (reasonsResponse == null || !mounted) return;

    final reasons = reasonsResponse['reasons'] as List;
    if (reasons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error loading cancellation reasons")),
      );
      return;
    }

    // Show reason selection dialog
    final selectedReason = await _showCancellationDialog(reasons);
    if (selectedReason == null) return; // User cancelled the dialog

    // Show confirmation dialog
    final confirmed = await _showConfirmationDialog();
    if (!confirmed) return;

    // Proceed with cancellation with reason
    final cancelData = {
      'current_lat': lat,
      'current_lng': lng,
      'reason_id': selectedReason['id'],
      if (selectedReason['requires_custom_text']) 
        'custom_reason_text': selectedReason['custom_text'] ?? '',
    };

    final result = await ApiService.post(
      "/requests/${currentRequest["id"]}/cancel/",
      cancelData,
      requiresAuth: true,
    );

    if (!mounted) return;

    if (result != null && result is Map) {
      if (result.containsKey("detail")) {
        String message = result["detail"] ?? "Request cancelled";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );

        // If cancellation was successful, transition to HomeScreen
        if (message.contains("successfully")) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen(role: "RODIE")),
          );
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error cancelling request")),
      );
    }
  }

  Future<Map<String, dynamic>?> _showCancellationDialog(List reasons) async {
    int? selectedReasonId;
    final customTextController = TextEditingController();
    Map<String, dynamic>? selectedReason;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Cancel Request"),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Please select a reason for cancellation:",
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    ...reasons.map((reason) {
                      final reasonId = reason['id'] as int;
                      final requiresCustomText = reason['requires_custom_text'] as bool;
                      final isSelected = selectedReasonId == reasonId;
                      
                      return Column(
                        children: [
                          ListTile(
                            leading: Radio<int>(
                              value: reasonId,
                              groupValue: selectedReasonId,
                              onChanged: (value) {
                                setState(() {
                                  selectedReasonId = value;
                                  selectedReason = reason;
                                  if (!requiresCustomText) {
                                    customTextController.clear();
                                  }
                                });
                              },
                              activeColor: const Color(0xFFFF8C00),
                            ),
                            title: Text(reason['reason']),
                            onTap: () {
                              setState(() {
                                selectedReasonId = reasonId;
                                selectedReason = reason;
                                if (!requiresCustomText) {
                                  customTextController.clear();
                                }
                              });
                            },
                          ),
                          if (requiresCustomText && isSelected)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 16.0,
                                right: 16.0,
                                bottom: 8.0,
                              ),
                              child: TextField(
                                controller: customTextController,
                                decoration: const InputDecoration(
                                  labelText: "Please provide details",
                                  border: OutlineInputBorder(),
                                  hintText: "Explain why you're cancelling...",
                                ),
                                maxLines: 3,
                                onChanged: (value) {
                                  if (selectedReason != null) {
                                    selectedReason!['custom_text'] = value;
                                  }
                                },
                              ),
                            ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("BACK"),
                ),
                ElevatedButton(
                  onPressed: selectedReasonId != null
                      ? () {
                          final reason = reasons.firstWhere(
                            (r) => r['id'] == selectedReasonId,
                          );
                          Navigator.of(context).pop(reason);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                  child: const Text("NEXT"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _showConfirmationDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Cancellation"),
        content: const Text("Are you sure you want to cancel this assist request?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("No"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text("Yes, Cancel"),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _showNavigationOptions() async {
    final riderLat = currentRequest["rider_lat"];
    final riderLng = currentRequest["rider_lng"];
    
    if (riderLat == null || riderLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Driver location not available")),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Navigate to Driver"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Choose your preferred navigation app:",
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.map, color: Colors.blue),
                title: const Text("Google Maps"),
                subtitle: const Text("Recommended"),
                onTap: () {
                  Navigator.of(context).pop();
                  _openGoogleMaps(double.parse(riderLat.toString()), double.parse(riderLng.toString()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.directions_car, color: Colors.blue),
                title: const Text("Waze"),
                subtitle: const Text("Community-based navigation"),
                onTap: () {
                  Navigator.of(context).pop();
                  _openWaze(double.parse(riderLat.toString()), double.parse(riderLng.toString()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.navigation, color: Colors.orange),
                title: const Text("Apple Maps"),
                subtitle: const Text("iOS default navigation"),
                onTap: () {
                  Navigator.of(context).pop();
                  _openAppleMaps(double.parse(riderLat.toString()), double.parse(riderLng.toString()));
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openGoogleMaps(double lat, double lng) async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
    final uri = Uri.parse(url);
    
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open Google Maps")),
      );
    }
  }

  Future<void> _openWaze(double lat, double lng) async {
    final url = 'https://waze.com/ul?ll=$lat,$lng&navigate=yes';
    final uri = Uri.parse(url);
    
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open Waze")),
      );
    }
  }

  Future<void> _openAppleMaps(double lat, double lng) async {
    final url = 'https://maps.apple.com/?daddr=$lat,$lng';
    final uri = Uri.parse(url);
    
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open Apple Maps")),
      );
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    locationTimer?.cancel();
    _chatScrollController.dispose();
    if (_ownsWs) {
      ws.disconnect();
    } else if (_rideHandler != null) {
      // Remove handler but do NOT disconnect - HomeScreen owns the WS
      ws.removeHandler(_rideHandler!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = LatLng(
      (riderLocation.latitude + roadieLocation.latitude) / 2,
      (riderLocation.longitude + roadieLocation.longitude) / 2,
    );
    final counterpart = widget.request["rider"];

    String name = currentRequest["rider_username"]?.toString() ?? 
                  widget.request["rider_username"]?.toString() ?? 
                  "Driver";
                  
    if (counterpart is Map && counterpart["username"] != null && counterpart["username"].toString().isNotEmpty) {
      name = counterpart["username"].toString();
    }

    // Debug current state for visibility issues
    debugPrint("📱 [RideScreen] Build - Status: ${currentRequest["status"]} | Connected: $_isConnected");
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Finish or cancel the ride first.")),
          );
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Column(
              children: [
                // Modern Header
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF10223D), Color(0xFF1D3B63)],
                    ),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.assistant_navigation,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Text(
                                      "Assisting Driver",
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.phone, color: Colors.white),
                                  onPressed: () async {
                                    final phone = currentRequest["rider_phone"] ?? 
                                                 widget.request["rider_phone"] ?? 
                                                 (widget.request["rider"] is Map ? widget.request["rider"]["phone"] : null) ??
                                                 (currentRequest["rider"] is Map ? currentRequest["rider"]["phone"] : null);
                                                 
                                    if (phone == null || phone.toString().isEmpty) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text("Driver phone number not available")),
                                        );
                                      }
                                      return;
                                    }
                                    
                                    final phoneUrl = 'tel:$phone';
                                    final uri = Uri.parse(phoneUrl);
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    } else {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text("Could not open phone dialer")),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          
                        ],
                      ),
                    ),
                  ),
                ),
                
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: FlutterMap(
                            mapController: mapController,
                            options: MapOptions(initialCenter: center, initialZoom: 15),
                            children: [
                              TileLayer(
                                urlTemplate: "https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png",
                                subdomains: const ['a', 'b', 'c', 'd'],
                                retinaMode: RetinaMode.isHighDensity(context),
                                userAgentPackageName: 'com.srs.roadie',
                              ),
                              MarkerLayer(
                                markers: [
                                  // Rider Marker
                                  Marker(
                                    point: riderLocation,
                                    width: 60,
                                    height: 60,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Container(
                                          width: 60,
                                          height: 60,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10223D).withValues(alpha: 0.2),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10223D),
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 3),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Roadie Marker
                                  Marker(
                                    point: roadieLocation,
                                    width: 60,
                                    height: 60,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Container(
                                          width: 60,
                                          height: 60,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFF8C00).withValues(alpha: 0.2),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFF8C00),
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 3),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Small Overlay for Status
                      Positioned(
                        top: 24,
                        left: 32,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6, height: 6,
                                decoration: BoxDecoration(
                                  color: _isConnected ? Colors.green : Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _isConnected ? "Live" : "Reconnecting...",
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Bottom Section - Roadie Action Slider
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _buildRoadieActionSlider(),
                  ),
                ),
              ],
            ),
            
            // Chat panel now triggered from the new layered UI instead of FAB!
            
            // Chat panel overlay — inline so it rebuilds on new messages
            _buildChatPanel(),
            
            // Semi-transparent overlay when chat is open
            if (_isChatOpen)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                bottom: MediaQuery.of(context).size.height * 0.65,
                child: GestureDetector(
                  onTap: () => setState(() => _isChatOpen = false),
                  child: Container(color: Colors.black.withValues(alpha: 0.3)),
                ),
              ),
          ], // Stack children
        ), // Stack
      ), // Scaffold
    ); // PopScope
  }

  Widget _buildRoadieActionSlider() {
    final status = currentRequest["status"];
    
    String labelText = "Upon arrival, slide to confirm arrival";
    String sliderText = "→ Confirm Arrival →";
    Color thumbColor = const Color(0xFF10223D);
    
    if (status == "ARRIVED") {
      labelText = "Reached Location! Slide to start assisting";
      sliderText = "→ Start Assisting →";
      thumbColor = const Color(0xFF10223D);
    } else if (status == "STARTED") {
      labelText = "Service in Progress";
      sliderText = "→ Slide to Complete Assist →";
      thumbColor = const Color(0xFFFF8C00);
    }

    // Cancellation is only allowed before the roadie marks arrival
    final showCancel = status == null || status == "ACCEPTED" || status == "EN_ROUTE";

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // LAYER 1: Navigation, Chat, Cancel
          if (showCancel || status == "ARRIVED" || status == "STARTED")
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (showCancel || status == "ARRIVED" || status == "STARTED")
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _showNavigationOptions,
                      icon: const Icon(Icons.directions, color: Color(0xFF10223D), size: 18),
                      label: const Text("Nav", style: TextStyle(color: Color(0xFF10223D), fontSize: 13, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF10223D)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _isChatOpen = true;
                      _unreadCount = 0;
                    }),
                    icon: Icon(
                      _unreadCount > 0 ? Icons.mark_chat_unread : Icons.chat_bubble_outline, 
                      color: _unreadCount > 0 ? const Color(0xFFFF8C00) : const Color(0xFF10223D), 
                      size: 18
                    ),
                    label: Text(
                      _unreadCount > 0 ? "Chat ($_unreadCount)" : "Chat", 
                      style: TextStyle(
                        color: _unreadCount > 0 ? const Color(0xFFFF8C00) : const Color(0xFF10223D), 
                        fontSize: 13, 
                        fontWeight: FontWeight.bold
                      )
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _unreadCount > 0 ? const Color(0xFFFF8C00) : const Color(0xFF10223D)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                if (showCancel) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: cancelRequest,
                      icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 18),
                      label: const Text("Cancel", style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ]
              ],
            ),
          
          const SizedBox(height: 16),
          
          // LAYER 2: Text Description
          Center(
            child: Column(
              children: [
                Text(
                  labelText,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF10223D),
                  ),
                  textAlign: TextAlign.center,
                ),
                if (status == "ACCEPTED" || status == "EN_ROUTE")
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      "Make sure you have reached the driver first",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // LAYER 3: Slider
          Container(
            height: 60,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  sliderText,
                  style: TextStyle(
                    color: thumbColor.withValues(alpha: 0.6),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                Positioned.fill(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 60,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 28,
                        elevation: 4,
                        pressedElevation: 8,
                      ),
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: thumbColor,
                    ),
                    child: Slider(
                      value: _sliderValue,
                      min: 0,
                      max: 100,
                      onChanged: _isProcessing ? null : (value) {
                        setState(() => _sliderValue = value);
                        if (value >= 90 && !_isProcessing) {
                          HapticFeedback.mediumImpact();
                          // Reset slider immediately for visual feedback
                          Future.delayed(const Duration(milliseconds: 200), () {
                            if (mounted) setState(() => _sliderValue = 0);
                          });
                          // Fire the API action — _isProcessing blocks further swipes until done
                          if (status == "ACCEPTED" || status == "EN_ROUTE") {
                            confirmArrival();
                          } else if (status == "ARRIVED") {
                            startAssist();
                          } else if (status == "STARTED") {
                            completeAssist();
                          }
                        }
                      },
                      onChangeEnd: (value) {
                        if (value < 90) {
                          setState(() => _sliderValue = 0);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatPanel() {
    final riderName = currentRequest["rider_username"]?.toString() ?? 
                     widget.request["rider_username"]?.toString() ?? 
                     currentRequest["rider_name"] ?? 
                     widget.request["rider_name"] ?? "Driver";
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      bottom: _isChatOpen ? 0 : -(MediaQuery.of(context).size.height * 0.65),
      left: 0,
      right: 0,
      height: (MediaQuery.of(context).size.height * 0.65) + MediaQuery.of(context).viewInsets.bottom,
      child: Material(
        elevation: 20,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Header
              GestureDetector(
                onTap: () => setState(() => _isChatOpen = false),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF10223D),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        "Chat with $riderName",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => setState(() => _isChatOpen = false),
                        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 28),
                      ),
                    ],
                  ),
                ),
              ),

              // Messages list
              Expanded(
                child: Container(
                  color: const Color(0xFFF8F9FA),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: messages.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
                              SizedBox(height: 12),
                              Text(
                                "No messages yet.\nSend a message to the driver.",
                                style: TextStyle(color: Colors.grey, fontSize: 14),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _chatScrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[messages.length - 1 - index];
                            final isMe = msg["sender_role"] == "RODIE";
                            final time = _formatMessageTime(msg["created_at"]?.toString());
                            final senderName = isMe ? null : (msg["sender_name"] ?? "Driver");

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (senderName != null)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 12, bottom: 2),
                                      child: Text(
                                        senderName,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  Align(
                                    alignment: isMe
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Container(
                                      constraints: BoxConstraints(
                                        maxWidth: MediaQuery.of(context).size.width * 0.72,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isMe
                                            ? const Color(0xFFFF8C00)
                                            : const Color(0xFF10223D),
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(16),
                                          topRight: const Radius.circular(16),
                                          bottomLeft: Radius.circular(isMe ? 16 : 4),
                                          bottomRight: Radius.circular(isMe ? 4 : 16),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.08),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            msg["text"] ?? "",
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                            ),
                                          ),
                                          if (time.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              time,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.white.withValues(alpha: 0.6),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),

              // Input area
              Container(
                padding: EdgeInsets.fromLTRB(
                  12, 10, 12,
                  10 + MediaQuery.of(context).viewInsets.bottom,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: chatController,
                          decoration: InputDecoration(
                            hintText: "Type a message...",
                            hintStyle: TextStyle(color: Colors.grey[400]),
                            filled: true,
                            fillColor: const Color(0xFFF5F5F5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                          ),
                          maxLines: null,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => sendChat(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: const Color(0xFFFF8C00),
                        radius: 22,
                        child: IconButton(
                          onPressed: sendChat,
                          icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRideCancelledInfoDialog(String message) {
    if (!mounted) return;
    
    // Show a snackbar on the root context so it survives navigation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
    
    // Automatically push back to the Home Screen since RideScreen was a replacement route
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen(role: "RODIE")),
      (route) => false,
    );
  }
}
