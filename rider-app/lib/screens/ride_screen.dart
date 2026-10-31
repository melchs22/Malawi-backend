// RIDE SCREEN (FULL)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'rating_screen.dart';
import 'home_screen.dart';
class RideScreen extends StatefulWidget {
  final Map request;
  final bool isRoadie;
  final WebSocketService? ws; // Shared WS from parent screen
  const RideScreen({required this.request, required this.isRoadie, this.ws, super.key});

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> {
  Map<String, dynamic> currentRequest = {};
  final MapController mapController = MapController();
  late final WebSocketService ws;

  List<Map<String, dynamic>> messages = [];
  bool _ownsWs = false; // Whether this screen created the WS
  WSCallback? _rideHandler; // Store handler reference

  Timer? locationTimer;

  LatLng riderLocation = const LatLng(0, 0);
  LatLng roadieLocation = const LatLng(0, 0);

  // Real-time tracking info
  double? distanceKm;
  int? etaSeconds;
  String? roadieName;

  final TextEditingController chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isCancelling = false; // Flag to prevent duplicate snackbars
  bool _isChatOpen = false;
  int _unreadCount = 0;
  final Set<String> _shownStatuses = {}; // Prevent duplicate status alerts

  @override
  void initState() {
    super.initState();

    currentRequest = Map.from(widget.request);

    // Use shared WS if provided, otherwise create new (fallback)
    if (widget.ws != null) {
      ws = widget.ws!;
      _ownsWs = false;
    } else {
      ws = WebSocketService();
      _ownsWs = true;
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

      // Populate initial tracking info from request map
      String? name = (currentRequest["rodie_username"] ?? currentRequest["roadie_username"] ?? currentRequest["rodie_name"] ?? currentRequest["roadie_name"])?.toString();
      if (name != null && name.toLowerCase() != "roadie") {
        roadieName = name;
      }
      distanceKm = currentRequest["distance_km"] != null ? double.tryParse(currentRequest["distance_km"].toString()) : null;
      etaSeconds = currentRequest["eta_seconds"] != null ? int.tryParse(currentRequest["eta_seconds"].toString()) : null;

    } catch (e) {
      debugPrint("Error parsing initial locations: $e");
    }
  }

  /// WEBSOCKET HANDLER SETUP
  void _setupWSHandler() async {
    // Create and store handler for cleanup on dispose
    _rideHandler = (data) {
      if (!mounted) return;
      final type = data["type"];
      final typeLower = type?.toString().toLowerCase();
      debugPrint("\ud83d\udce9 [RideScreen] WS message received: type=$type");

      /// ROADIE LOCATION UPDATE
      if (typeLower == "rodie_location") {
        setState(() {
          roadieLocation = LatLng(
            double.parse(data["lat"].toString()),
            double.parse(data["lng"].toString()),
          );
          
          // Update tracking info - handle potential string/int issues
          distanceKm = data["distance_km"] != null ? double.tryParse(data["distance_km"].toString()) : distanceKm;
          etaSeconds = data["eta_seconds"] != null ? int.tryParse(data["eta_seconds"].toString()) : etaSeconds;
          
          final String? newName = (data["rodie_username"] ?? data["username"] ?? data["rodie_name"])?.toString();
          if (newName != null && newName.toLowerCase() != "roadie") {
            roadieName = newName;
          }
        });
        _moveMap();
      }

      /// RIDER LOCATION UPDATE
      else if (data["type"] == "RIDER_LOCATION") {
        setState(() {
          riderLocation = LatLng(
            double.parse(data["lat"].toString()),
            double.parse(data["lng"].toString()),
          );
        });
        _moveMap();
      }

      /// WS RECONNECTED - re-join request room
      else if (data["type"] == "WS_RECONNECTED") {
        debugPrint("🔄 [Rider] WS reconnected, re-joining request room");
        ws.send({"type": "JOIN_REQUEST", "request_id": currentRequest["id"]});
      }
      /// RIDE CANCELLED (from personal channel)
      else if (data["type"] == "REQUEST_CANCELLED") {
        if (!_isCancelling) {
          _isCancelling = true;
          _playCancellationSound();
          _showRideCancelledInfoDialog(data["message"] ?? "The Mechanic has cancelled this request.");
        }
      }

      /// CHAT HANDLING
      else if (data["type"] == "CHAT_MESSAGE" || data["type"] == "CHAT_NOTIFICATION") {
        if (data["sender_role"] != "RIDER") {
          final isDuplicate = messages.any((m) =>
            m["text"] == data["text"] &&
            m["sender_id"] == data["sender_id"] &&
            m["created_at"] == data["created_at"]);

          if (!isDuplicate) {
            setState(() {
              messages.add(data);
              if (!_isChatOpen) _unreadCount++;
            });
            if (_isChatOpen) {
              _scrollChatToBottom();
            }
          }

          // Show snackbar if it's a new message and chat is closed
          if (!_isChatOpen && mounted && !isDuplicate) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${data["sender_name"] ?? "Mechanic"}: ${data["text"]}'),
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
      }

      /// REQUEST STATUS UPDATE (from request group)
      else if (typeLower == "request_update" || typeLower == "request_arrived" || typeLower == "request_enroute" || typeLower == "request_started" || typeLower == "request_completed") {
        final incomingStatus = data["request"]?["status"] ?? data["status"];
        debugPrint("\ud83d\udea8 [RideScreen] STATUS UPDATE received: type=$type, status=$incomingStatus, shownStatuses=$_shownStatuses");

        if (data["request"] != null) {
          setState(() {
            currentRequest = data["request"];
            final String? reqName = (currentRequest["rodie_username"] ?? currentRequest["roadie_username"] ?? currentRequest["rodie_name"] ?? currentRequest["roadie_name"])?.toString();
            if (reqName != null && reqName.toLowerCase() != "roadie") {
              roadieName = reqName;
            }
          });
        }

        final status = data["request"]?["status"] ?? data["status"];

        // Guard: only show each status alert once
        if (_shownStatuses.contains(status)) return;
        _shownStatuses.add(status);

        if (status == "ARRIVED") {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Mechanic has arrived!")),
          );
        }

        if (status == "STARTED") {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Assist started")),
          );
        }

        if (status == "COMPLETED") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => RatingScreen(
                request: currentRequest,
                isRoadie: false,
              ),
            ),
          );
        }

        if (status == "CANCELLED" && !_isCancelling) {
          _isCancelling = true;
          _playCancellationSound();
          _showRideCancelledInfoDialog(data["message"] ?? "This request has been cancelled.");
        }
      }
    };

    if (_ownsWs) {
      // Fallback: create new connection if no WS was passed
      await ws.connect(widget.isRoadie ? "RODIE" : "RIDER", _rideHandler!);
    } else {
      // Add handler to shared WS (don't create new connection)
      ws.addHandler(_rideHandler!);

      // Safety: if WS was disconnected during screen transition, reconnect
      if (!ws.isConnected) {
        debugPrint("⚠️ [RideScreen] WS not connected — triggering reconnect");
        ws.reconnect();
        // Give WS a moment to reconnect before sending JOIN
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    /// JOIN REQUEST ROOM
    if (mounted) {
      ws.send({
        "type": "JOIN_REQUEST",
        "request_id": currentRequest["id"],
      });
      debugPrint("📡 Joined request room: ${currentRequest["id"]}");
    }
  }

  void _handleCancellation(Map<String, dynamic> data) {
    if (!mounted || _isCancelling) return;
    
    setState(() => _isCancelling = true); // Prevent further processing
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Request cancelled"),
        backgroundColor: Colors.red,
      ),
    );
    
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreen(role: "RIDER"),
          ),
        );
      }
    });
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

  /// SEND LOCATION EVERY 3 SECONDS (optimized for real-time tracking)
  void startSendingLocation() {
    final updateInterval = (!widget.isRoadie && 
        (currentRequest["status"]?.toString().toUpperCase() == "ACCEPTED" ||
         currentRequest["status"]?.toString().toUpperCase() == "EN_ROUTE")) 
        ? 3 : 5;
    
    _sendLocationTick();
    locationTimer = Timer.periodic(Duration(seconds: updateInterval), (_) => _sendLocationTick());
  }

  Future<void> _sendLocationTick() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      ws.sendLocation(lat: position.latitude, lng: position.longitude);

      if (mounted) {
        setState(() {
          if (widget.isRoadie) {
            roadieLocation = LatLng(position.latitude, position.longitude);
          } else {
            riderLocation = LatLng(position.latitude, position.longitude);
          }
        });
        _moveMap();
      }
    } catch (e) {
      debugPrint("Location update error: $e");
    }
  }

  void sendChat() {
    final text = chatController.text.trim();
    if (text.isEmpty) return;

    // Optimistically add message to local list so it shows immediately
    setState(() {
      messages.add({
        "type": "CHAT_MESSAGE",
        "sender_role": "RIDER",
        "sender_name": "You",
        "text": text,
        "created_at": DateTime.now().toIso8601String(),
      });
    });

    // Safety: reconnect WS if it died mid-ride
    if (!ws.isConnected) {
      debugPrint("\u26a0\ufe0f [RideScreen] WS not connected for chat \u2014 reconnecting");
      ws.reconnect();
    }

    final chatPayload = {
      "type": "CHAT",
      "request_id": int.tryParse(currentRequest["id"].toString()) ?? currentRequest["id"],
      "text": text,
    };
    debugPrint("\ud83d\udcac [RideScreen] Sending chat: $chatPayload, wsConnected=${ws.isConnected}");
    ws.send(chatPayload);

    chatController.clear();
    _scrollChatToBottom();
  }

  void _scrollChatToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          0, // reversed list, 0 is bottom
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

  Future<void> _callRoadie() async {
    final roadiePhone = currentRequest["rodie_phone"];
    if (roadiePhone == null || roadiePhone.toString().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Mechanic phone number not available")),
      );
      return;
    }

    final url = 'tel:$roadiePhone';
    final uri = Uri.parse(url);
    
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open phone dialer")),
      );
    }
  }

  Widget _buildChatPanel() {
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
              // Drag handle + header
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
                        "Chat with ${roadieName ?? currentRequest["rodie_username"] ?? currentRequest["rodie_name"] ?? "Mechanic"}",
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
                                "No messages yet.\nSend a message to the mechanic.",
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
                            final isMe = msg["sender_role"] == "RIDER";
                            final time = _formatMessageTime(msg["created_at"]?.toString());
                            final senderName = isMe ? null : (msg["sender_name"] ?? "Mechanic");

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
                                            ? const Color(0xFF10223D)
                                            : Colors.white,
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(16),
                                          topRight: const Radius.circular(16),
                                          bottomLeft: Radius.circular(isMe ? 16 : 4),
                                          bottomRight: Radius.circular(isMe ? 4 : 16),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.06),
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
                                            style: TextStyle(
                                              color: isMe ? Colors.white : const Color(0xFF10223D),
                                              fontSize: 15,
                                            ),
                                          ),
                                          if (time.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              time,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isMe
                                                    ? Colors.white.withValues(alpha: 0.6)
                                                    : Colors.grey[400],
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

  void _moveMap() {
    try {
      final center = LatLng(
        (riderLocation.latitude + roadieLocation.latitude) / 2,
        (riderLocation.longitude + roadieLocation.longitude) / 2,
      );

      mapController.move(center, mapController.camera.zoom);
    } catch (_) {}
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

  void startAssist() async {
    await ApiService.post(
      "/requests/${currentRequest["id"]}/start/",
      {},
    );
  }

  void completeAssist() async {
    await ApiService.post(
      "/requests/${currentRequest["id"]}/complete/",
      {},
    );
  }

  void _cancelRequest() async {
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
    int? selectedReasonId;
    final customTextController = TextEditingController();
    Map<String, dynamic>? selectedReason;

    final selectedReasonIdResult = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Cancel Request"),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Please select a reason for cancellation:",
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      ...reasons.map((reason) => Column(
                        children: [
                          ListTile(
                            leading: Radio<int>(
                              value: reason['id'],
                              groupValue: selectedReasonId,
                              onChanged: (value) {
                                setState(() {
                                  selectedReasonId = value;
                                  selectedReason = reason;
                                  if (!(reason['requires_custom_text'] as bool)) {
                                    customTextController.clear();
                                  }
                                });
                              },
                              activeColor: const Color(0xFFFF8C00),
                            ),
                            title: Text(reason['reason']),
                            onTap: () {
                              setState(() {
                                selectedReasonId = reason['id'];
                                selectedReason = reason;
                                if (!(reason['requires_custom_text'] as bool)) {
                                  customTextController.clear();
                                }
                              });
                            },
                          ),
                          if (reason['requires_custom_text'] as bool && selectedReasonId == reason['id'])
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
                      )),
                    ],
                  ),
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
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("CANCEL REQUEST"),
                ),
              ],
            );
          },
        );
      },
    );

    if (selectedReasonIdResult == null) return; // User cancelled the dialog

    // Proceed with cancellation with reason
    final cancelData = {
      'reason_id': selectedReasonIdResult['id'],
      if (selectedReasonIdResult['requires_custom_text']) 
        'custom_reason_text': selectedReasonIdResult['custom_text'] ?? '',
      'current_lat': riderLocation.latitude,
      'current_lng': riderLocation.longitude,
    };

    setState(() => _isCancelling = true);
    final result = await ApiService.post(
      "/requests/${currentRequest["id"]}/cancel/",
      cancelData,
    );
    
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Request cancelled successfully")),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen(role: "RIDER")),
        (route) => false,
      );
    }
  }

  bool _canCancelRequest() {
    final status = currentRequest["status"]?.toString().toUpperCase();
    // Requirements: Disappear only after STARTED. 
    // So ACCEPTED, EN_ROUTE, and ARRIVED are all cancellable.
    return status == "REQUESTED" || status == "ACCEPTED" || status == "EN_ROUTE" || status == "ARRIVED";
  }

  String _formatETA(int? etaSeconds) {
    if (etaSeconds == null) return "Calculating...";
    
    if (etaSeconds < 60) {
      return "< 1 min";
    } else if (etaSeconds < 3600) {
      final minutes = (etaSeconds / 60).round();
      return "$minutes min";
    } else {
      final hours = etaSeconds ~/ 3600;
      final minutes = ((etaSeconds % 3600) / 60).round();
      return "${hours}h ${minutes}m";
    }
  }

  String _formatDistance(double? distanceKm) {
    if (distanceKm == null) return "Calculating...";
    
    if (distanceKm < 1) {
      final meters = (distanceKm * 1000).round();
      return "$meters m";
    } else {
      return "${distanceKm.toStringAsFixed(1)} km";
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
      // Remove handler but do NOT disconnect - parent screen owns the WS
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

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Service in Progress"),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF10223D),
        automaticallyImplyLeading: false, // Remove back button
      ),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          // You could show a snackbar here if you want
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Service in progress. Use 'Cancel' button if needed.")),
          );
        },
        child: Stack(
          children: [
          Column(
        children: [
          /// TRACKING INFO (for riders)
          if (!widget.isRoadie && 
              (currentRequest["status"]?.toString().toUpperCase() == "ACCEPTED" ||
              currentRequest["status"]?.toString().toUpperCase() == "EN_ROUTE"))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.directions_car, color: Colors.orange, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        roadieName ?? 
                        currentRequest["rodie_username"] ?? 
                        currentRequest["rodie_name"] ?? 
                        currentRequest["roadie_name"] ?? 
                        "Mechanic",
                        style: const TextStyle(
                          color: Color(0xFF10223D),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          currentRequest["status"]?.toString().toUpperCase() ?? "EN ROUTE",
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Distance",
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              _formatDistance(distanceKm),
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              "ETA",
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              _formatETA(etaSeconds),
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
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

          /// MAP
          Expanded(
            flex: 3,
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 15,
              ),
              children: [

                TileLayer(
                  urlTemplate:
                      "https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png",
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.srs.roadie',
                ),

                MarkerLayer(
                  markers: [

                    /// RIDER
                    Marker(
                      point: riderLocation,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.person_pin_circle,
                          size: 40, color: Colors.blue),
                    ),

                    /// ROADIE
                    Marker(
                      point: roadieLocation,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.build,
                          size: 40, color: Colors.orange),
                    ),
                  ],
                ),
              ],
            ),
          ),
               /// BOTTOM ACTION CARD (Premium White)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: currentRequest["status"]?.toString().toUpperCase() == "STARTED"
                  ? BorderRadius.zero
                  : const BorderRadius.vertical(top: Radius.circular(32)),
              boxShadow: currentRequest["status"]?.toString().toUpperCase() == "STARTED"
                  ? []
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 15,
                        offset: const Offset(0, -5),
                      ),
                    ],
            ),
            child: widget.isRoadie 
                ? Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          label: "Start Assist",
                          onPressed: startAssist,
                          icon: Icons.play_arrow,
                          color: const Color(0xFF10223D),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildActionButton(
                          label: "Complete",
                          onPressed: completeAssist,
                          icon: Icons.check_circle,
                          color: const Color(0xFFFF8C00),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Status Label for Rider
                      Text(
                        _getStatusDisplayText(),
                        style: TextStyle(
                          color: currentRequest["status"]?.toString().toUpperCase() == "STARTED"
                              ? const Color(0xFF10223D)
                              : Colors.grey[600],
                          fontSize: currentRequest["status"]?.toString().toUpperCase() == "STARTED" ? 22 : 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Primary Actions (Call/Chat)
                      if (currentRequest["status"]?.toString().toUpperCase() != "REQUESTED" &&
                          currentRequest["status"]?.toString().toUpperCase() != "COMPLETED" &&
                          currentRequest["status"]?.toString().toUpperCase() != "CANCELLED") ...[
                        Row(
                          children: [
                            Expanded(
                              child: _buildActionButton(
                                label: "Call",
                                onPressed: _callRoadie,
                                icon: Icons.call,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  SizedBox(
                                    width: double.infinity,
                                    child: _buildActionButton(
                                      label: "Chat",
                                      onPressed: () => setState(() {
                                        _isChatOpen = true;
                                        _unreadCount = 0;
                                      }),
                                      icon: Icons.chat_bubble_outline,
                                      color: const Color(0xFF10223D),
                                    ),
                                  ),
                                  if (_unreadCount > 0)
                                    Positioned(
                                      right: -4,
                                      top: -4,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text(
                                          _unreadCount > 9 ? '9+' : '$_unreadCount',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                      
                      // Secondary Action (Cancel) - disappears when assist starts
                      if (currentRequest["status"]?.toString().toUpperCase() != "STARTED" &&
                          currentRequest["status"]?.toString().toUpperCase() != "COMPLETED" &&
                          currentRequest["status"]?.toString().toUpperCase() != "CANCELLED") ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: _canCancelRequest() ? _cancelRequest : null,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              foregroundColor: _canCancelRequest() ? Colors.red[700] : Colors.grey[400],
                            ),
                            child: Text(
                              _canCancelRequest() ? "Cancel Request" : "Cannot Cancel (In Progress)",
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          ], // end Column children
          ), // end Column
          // Chat panel overlay — part of main widget tree so it rebuilds on new messages
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
        ],
      ),
    ),
  );
}

  /// Helper for status text
  String _getStatusDisplayText() {
    final status = currentRequest["status"]?.toString().toUpperCase() ?? "PENDING";
    switch (status) {
      case "ACCEPTED": return "Mechanic has accepted your request";
      case "EN_ROUTE": return "Mechanic is on the way to your location";
      case "ARRIVED": return "Mechanic has reached your location";
      case "STARTED": return "Service is currently in progress";
      case "COMPLETED": return "Service completed successfully";
      case "CANCELLED": return "Request has been cancelled";
      default: return "Requesting your assistance...";
    }
  }

  /// Helper for premium buttons
  Widget _buildActionButton({
    required String label,
    required VoidCallback onPressed,
    required IconData icon,
    required Color color,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
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
    
    // Automatically pop back to the Home Screen
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
