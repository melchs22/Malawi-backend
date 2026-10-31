import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import '../services/network_service.dart';
import 'ride_screen.dart';
import 'home_screen.dart';

// Keep a global player so it isn't garbage collected during screen transitions
final AudioPlayer _globalAcceptPlayer = AudioPlayer();

class RequestingScreen extends StatefulWidget {
  final Map request;
  final WebSocketService ws; // Add WebSocketService parameter
  const RequestingScreen({required this.request, required this.ws, super.key});

  @override
  State<RequestingScreen> createState() => _RequestingScreenState();
}

class _RequestingScreenState extends State<RequestingScreen>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _animation;

  double? _distance;
  int? _eta;
  
  int _remainingSeconds = 90; // Aligned with backend expiry
  Timer? _countdownTimer;
  bool _isCancelling = false;
  bool _hasAccepted = false; // Guard for single acceptance sound/nav
  WSCallback? _requestHandler; // Store handler reference

  @override
  void initState() {
    super.initState();

    debugPrint("⏳ [Rider] RequestingScreen initialized for request ID: ${widget.request['id']}");

    // Airwaves animation
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.7, end: 1.3).animate(_controller!);

    // Start countdown timer
    _startCountdown();

    // Listen for request updates
    _initialWS();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _remainingSeconds--;
        });
      }
      if (_remainingSeconds <= 0) {
        timer.cancel();
        // Timer expired - no roadies available
        if (mounted && !_isCancelling) {
          _showTimeoutDialog();
        }
      }
    });
  }

  Future<void> _showTimeoutDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('No Mechanics Available'),
        content: const Text(
          'Unfortunately, no service providers are available right now. Please try again later.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const HomeScreen(role: 'RIDER'),
                  ),
                );
              }
            },
            child: const Text('Back to Home'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelRequest() async {
    final requestId = widget.request['id'];
    if (requestId == null) return;

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

    final result = await showDialog<Map<String, dynamic>>(
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
                  onPressed: (selectedReasonId != null && 
                             (!selectedReason!['requires_custom_text'] || 
                              (selectedReason!['custom_text'] != null && selectedReason!['custom_text'].toString().trim().isNotEmpty)))
                      ? () {
                          Navigator.of(context).pop(selectedReason);
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

    if (result == null || !mounted) return; // User cancelled the dialog

    setState(() => _isCancelling = true);
    try {
      // Proceed with cancellation with reason
      final cancelData = {
        'reason_id': result['id'],
        if (result['requires_custom_text']) 
          'custom_reason_text': result['custom_text'] ?? '',
      };

      final response = await ApiService.post(
        "/requests/$requestId/cancel/",
        cancelData,
        requiresAuth: true
      );

      if (response != null && mounted) {
        _countdownTimer?.cancel();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request cancelled successfully'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const HomeScreen(role: 'RIDER'),
              ),
            );
          }
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to cancel request'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isCancelling = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isCancelling = false);
      }
    }
  }

  Future<void> _initialWS() async {
    try {
      debugPrint("🔌 [Rider] Checking WebSocket status for request tracking...");
      
      if (!widget.ws.isConnected) {
        debugPrint("🔄 [Rider] WebSocket disconnected, forcing reconnection...");
        await widget.ws.connect("rider", (data) {
          // Re-attach the main home screen handler if needed, 
          // or just handle request updates here.
        });
      }
      
      debugPrint("✅ [Rider] WebSocket ready for request tracking");
      
      // Create and store handler
      _requestHandler = (data) {
        if (!mounted) return;
        
        final type = data["type"];
        final typeLower = type?.toString().toLowerCase();
        
        if (typeLower == "request_update" || typeLower == "request_accepted") {
          final requestData = data["request"] ?? data["data"] ?? data;
          final status = requestData["status"] ?? data["status"];
          
          if (["ACCEPTED", "EN_ROUTE", "ARRIVED", "STARTED"].contains(status) && !_hasAccepted) {
            _hasAccepted = true; // Guard against duplicate calls
            debugPrint("✅ [Rider] Request ACCEPTED! Navigating to RideScreen");
            
            // 1. Play sound immediately
            _playAcceptanceSound();
            
            // 2. Stop local timer
            _countdownTimer?.cancel();

            // 3. REMOVE THIS HANDLER BEFORE NAVIGATING
            // This prevents late-arriving messages from re-triggering this logic 
            // while the navigation transition is in progress.
            if (_requestHandler != null) {
              widget.ws.removeHandler(_requestHandler!);
              _requestHandler = null; 
            }
            
            final request = data["request"] ?? data["data"] ?? widget.request;
            request["status"] = "ACCEPTED";
            
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    RideScreen(
                      request: request,
                      isRoadie: false,
                      ws: widget.ws,
                    ),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
                transitionDuration: const Duration(milliseconds: 600),
              ),
            );
          } else if (status == "CANCELLED") {
            _countdownTimer?.cancel();
            if (!mounted) return;
            
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Request has been cancelled"),
                duration: Duration(seconds: 3),
              ),
            );
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            });
          }

        } else if (typeLower == "request_proximity") {
          if (mounted) {
            setState(() {
              _distance = data["distance_km"];
              _eta = data["eta_seconds"];
            });
          }
        } else if (typeLower == "request_cancelled") {
          debugPrint("❌ [Rider] Request was cancelled");
          if (!mounted || _isCancelling) return;
          
          setState(() => _isCancelling = true);
          _countdownTimer?.cancel();
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Request cancelled"),
              backgroundColor: Colors.red,
            ),
          );
          
          _playCancellationSound();
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen(role: "RIDER")),
          );
        }
      };
      
      // Add handler to existing WebSocket
      widget.ws.addHandler(_requestHandler!);
      
      if (mounted) {
        widget.ws.send({"type": "JOIN_REQUEST", "request_id": widget.request["id"]});
      }
    } catch (e) {
      debugPrint("❌ [Rider] WebSocket initialization error: $e");
    }
  }

  Future<void> _playAcceptanceSound() async {
    try {
      await _globalAcceptPlayer.stop();
      await _globalAcceptPlayer.setReleaseMode(ReleaseMode.release);
      await _globalAcceptPlayer.play(AssetSource('Accept.mpeg')).catchError((e) {
        debugPrint("Notice: Accept.mpeg playback error: $e");
      });
      
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(pattern: [0, 300, 100, 300]);
      }
    } catch (e) {
      debugPrint("Error playing acceptance sound: $e");
    }
  }

  Future<void> _playCancellationSound() async {
    try {
      await _globalAcceptPlayer.stop();
      await _globalAcceptPlayer.setReleaseMode(ReleaseMode.release);
      await _globalAcceptPlayer.play(AssetSource('cancel.mpeg')).catchError((e) {
        debugPrint("Notice: cancel.mpeg playback error: $e");
      });
      
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(pattern: [0, 300, 100, 300]);
      }
    } catch (e) {
      debugPrint("Error playing cancellation sound: $e");
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _countdownTimer?.cancel();
    // Remove WebSocket handler
    if (_requestHandler != null) {
      widget.ws.removeHandler(_requestHandler!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serviceName = widget.request["service_type_name"] ?? "Service";
    final progressPercent = _remainingSeconds / 90.0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Please wait for a Mechanic or cancel."),
                ),
              );
            },
            child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Header Section
              const Icon(
                Icons.search_rounded,
                size: 64,
                color: Color(0xFF10223D),
              ),
              const SizedBox(height: 24),
              Text(
                "Requesting $serviceName",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF10223D),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Searching for nearby Mechanics...",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              
              const SizedBox(height: 60),
              
              // Animated Pulse Section
              Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _animation!,
                    builder: (context, child) {
                      return Container(
                        width: 140 * _animation!.value,
                        height: 140 * _animation!.value,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF10223D).withValues(alpha: 0.05),
                        ),
                      );
                    },
                  ),
                  AnimatedBuilder(
                    animation: _animation!,
                    builder: (context, child) {
                      return Container(
                        width: 100 * _animation!.value,
                        height: 100 * _animation!.value,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF10223D).withValues(alpha: 0.1),
                        ),
                      );
                    },
                  ),
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10223D),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10223D).withValues(alpha: 0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.router_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 60),
              
              // Proximity Info
              if (_distance != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.location_on, color: Colors.blue, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Nearest Mechanic: ${_distance!.toStringAsFixed(1)} km",
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF10223D),
                              ),
                            ),
                            if (_eta != null)
                              Text(
                                "Estimated arrival: ${(_eta! / 60).ceil()} mins",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Timer Section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade100),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Safety Timeout",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          "$_remainingSeconds s",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: _remainingSeconds <= 10 ? Colors.red : const Color(0xFFFF8C00),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: progressPercent,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade100,
                        valueColor: AlwaysStoppedAnimation(
                          _remainingSeconds <= 10 ? Colors.red : const Color(0xFFFF8C00),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 48),
              
              // Cancel Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: _isCancelling ? null : _cancelRequest,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: BorderSide(color: Colors.red.withValues(alpha: 0.3), width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isCancelling
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                          ),
                        )
                      : const Text(
                          'CANCEL REQUEST',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  ),
    );
  }
}
