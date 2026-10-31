import 'package:flutter/material.dart';
import '../services/overlay_service.dart';
import '../services/wake_lock_service.dart';
import 'overlay_settings_screen.dart';

/// Example of how to integrate the overlay system
/// This shows how to use the overlay service in your existing screens
class OverlayIntegrationExample extends StatefulWidget {
  const OverlayIntegrationExample({super.key});

  @override
  State<OverlayIntegrationExample> createState() => _OverlayIntegrationExampleState();
}

class _OverlayIntegrationExampleState extends State<OverlayIntegrationExample> {
  final OverlayService _overlayService = OverlayService();
  final WakeLockService _wakeLockService = WakeLockService();
  
  bool _isRoadieOnline = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    // Listen to overlay state changes
    _overlayService.overlayStateStream.listen((isActive) {
      if (mounted) {
        setState(() {});
      }
    });

    // Listen to request alerts
    _overlayService.requestAlertStream.listen((requestData) {
      if (mounted) {
        _handleIncomingRequest(requestData);
      }
    });
  }

  Future<void> _toggleOnlineStatus() async {
    setState(() => _isLoading = true);
    
    try {
      _isRoadieOnline = !_isRoadieOnline;
      
      // Update overlay service
      await _overlayService.updateRoadieStatus(_isRoadieOnline);
      
      // Update wake lock service
      if (_isRoadieOnline) {
        await _wakeLockService.activateForService();
      } else {
        await _wakeLockService.deactivateForService();
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isRoadieOnline ? 'You are now online' : 'You are now offline'),
          backgroundColor: _isRoadieOnline ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _handleIncomingRequest(Map<String, dynamic> requestData) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Service Request!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Request ID: ${requestData['requestId'] ?? 'N/A'}'),
            const SizedBox(height: 8),
            Text('Location: ${requestData['location'] ?? 'Unknown'}'),
            const SizedBox(height: 8),
            Text('Service: ${requestData['serviceType'] ?? 'General Assistance'}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Decline'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _acceptRequest(requestData);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8C00),
              foregroundColor: Colors.white,
            ),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  void _acceptRequest(Map<String, dynamic> requestData) {
    // Navigate to request details screen
    // Navigator.push(
    //   context,
    //   MaterialPageRoute(
    //     builder: (_) => RequestDetailsScreen(requestData: requestData),
    //   ),
    // );
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Request accepted! Navigate to details screen.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _simulateIncomingRequest() async {
    if (!_isRoadieOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be online to receive requests'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Simulate incoming request
    final requestData = {
      'requestId': 'REQ-${DateTime.now().millisecondsSinceEpoch}',
      'location': '123 Main St, City',
      'serviceType': 'Battery Jump',
      'customerName': 'John Doe',
      'urgency': 'High',
    };

    await _overlayService.showRequestAlert(requestData);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF10223D), Color(0xFF1D3B63), Color(0xFF10223D)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Mechanic Dashboard',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // Status Card
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _isRoadieOnline ? Icons.online_prediction : Icons.offline_bolt,
                              color: _isRoadieOnline ? Colors.green : Colors.red,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isRoadieOnline ? 'Online' : 'Offline',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: _isRoadieOnline ? Colors.green : Colors.red,
                                    ),
                                  ),
                                  Text(
                                    _isRoadieOnline 
                                      ? 'Ready to receive service requests'
                                      : 'Not available for requests',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isRoadieOnline,
                              onChanged: _isLoading ? null : (_) => _toggleOnlineStatus(),
                              activeTrackColor: const Color(0xFFFF8C00),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Overlay Status Card
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          _overlayService.isActive ? Icons.widgets : Icons.widgets_outlined,
                          color: _overlayService.isActive ? Colors.green : Colors.white70,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _overlayService.isActive 
                              ? 'Floating widget is active'
                              : 'Floating widget is inactive',
                            style: TextStyle(
                              color: _overlayService.isActive ? Colors.green : Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Action Buttons
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _simulateIncomingRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8C00),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Simulate Incoming Request',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const OverlaySettingsScreen(),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF8C00),
                      side: const BorderSide(color: Color(0xFFFF8C00)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Overlay Settings',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                
                const Spacer(),
                
                // Instructions
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'How to use:',
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '1. Go online to start receiving requests\n'
                        '2. The floating widget will appear when online\n'
                        '3. Switch to other apps to see the widget\n'
                        '4. Tap the widget to return to SRS\n'
                        '5. Requests will show alerts on the widget',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
