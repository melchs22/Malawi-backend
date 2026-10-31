import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/overlay_service.dart';

/// Overlay Settings Screen for Roadie App
/// 
/// Allows users to control the floating overlay widget
/// Professional UI designed for production use
class OverlaySettingsScreen extends StatefulWidget {
  const OverlaySettingsScreen({super.key});

  @override
  State<OverlaySettingsScreen> createState() => _OverlaySettingsScreenState();
}

class _OverlaySettingsScreenState extends State<OverlaySettingsScreen> {
  final OverlayService _overlayService = OverlayService();
  bool _isEnabled = false;
  bool _hasPermission = false;
  bool _isLoading = false;
  bool _isRequestingPermission = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    
    // Listen to overlay state changes
    _overlayService.overlayStateStream.listen((isActive) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    
    _isEnabled = _overlayService.isEnabled;
    _hasPermission = _overlayService.hasPermission;
    
    setState(() => _isLoading = false);
  }

  Future<void> _toggleOverlay(bool value) async {
    setState(() => _isLoading = true);
    
    try {
      await _overlayService.setEnabled(value);
      setState(() => _isEnabled = value);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value 
              ? 'Floating widget will appear when you\'re online' 
              : 'Floating widget disabled'
          ),
          backgroundColor: value ? Colors.green : Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update setting: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _requestPermission() async {
    setState(() => _isRequestingPermission = true);
    
    try {
      final granted = await _overlayService.requestOverlayPermission();
      
      if (granted) {
        setState(() => _hasPermission = true);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Overlay permission granted! You can now enable the floating widget.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Overlay permission denied. Please enable it in Settings > Apps > SRS Mechanic.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to request permission: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isRequestingPermission = false);
    }
  }

  Future<void> _openAppSettings() async {
    try {
      await openAppSettings();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open settings: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
          child: Column(
            children: [
              // App Bar
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Floating Widget',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Content
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Permission Status Card
                            _buildPermissionCard(),
                            
                            const SizedBox(height: 16),
                            
                            // Main Setting Card
                            _buildMainSettingCard(),
                            
                            const SizedBox(height: 16),
                            
                            // Information Card
                            _buildInfoCard(),
                            
                            const SizedBox(height: 16),
                            
                            // Status Card
                            _buildStatusCard(),
                            
                            const SizedBox(height: 24),
                            
                            // Warning Note
                            _buildWarningCard(),
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

  Widget _buildPermissionCard() {
    return Container(
      decoration: BoxDecoration(
        color: _hasPermission 
          ? Colors.green.withValues(alpha: 0.1)
          : Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _hasPermission 
            ? Colors.green.withValues(alpha: 0.3)
            : Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _hasPermission ? Icons.check_circle : Icons.warning,
                  color: _hasPermission ? Colors.green : Colors.orange,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _hasPermission ? 'Permission Granted' : 'Permission Required',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _hasPermission ? Colors.green : Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _hasPermission 
                          ? 'Display over other apps permission is granted'
                          : 'Needed to show floating widget over other apps',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            if (!_hasPermission) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isRequestingPermission ? null : _requestPermission,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C00),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isRequestingPermission
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Grant Permission'),
                ),
              ),
              
              const SizedBox(height: 8),
              TextButton(
                onPressed: _openAppSettings,
                child: const Text(
                  'Open Settings Manually',
                  style: TextStyle(
                    color: Color(0xFFFF8C00),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMainSettingCard() {
    return Container(
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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.widgets,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enable Floating Widget',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Show SRS widget when you\'re online',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _isEnabled,
                  onChanged: _hasPermission ? _toggleOverlay : null,
                  activeTrackColor: const Color(0xFFFF8C00),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
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
            const Text(
              'How it works',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoItem(
              icon: Icons.visibility,
              title: 'Always Visible When Online',
              description: 'Small SRS icon floats over other apps when you\'re available',
              color: Colors.blue,
            ),
            const SizedBox(height: 8),
            _buildInfoItem(
              icon: Icons.touch_app,
              title: 'Quick Access',
              description: 'Tap the widget to instantly return to the SRS app',
              color: Colors.green,
            ),
            const SizedBox(height: 8),
            _buildInfoItem(
              icon: Icons.notifications_active,
              title: 'Request Alerts',
              description: 'Widget shows urgent alerts for new service requests',
              color: Colors.orange,
            ),
            const SizedBox(height: 8),
            _buildInfoItem(
              icon: Icons.battery_saver,
              title: 'Battery Optimized',
              description: 'Minimal battery impact with smart background management',
              color: Colors.purple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
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
              _overlayService.isActive 
                ? Icons.widgets 
                : Icons.widgets_outlined,
              color: _overlayService.isActive 
                ? Colors.green 
                : Colors.white70,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _overlayService.isActive 
                  ? 'Floating widget is currently visible'
                  : 'Floating widget is not visible',
                style: TextStyle(
                  color: _overlayService.isActive 
                    ? Colors.green 
                    : Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            color: Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'The floating widget helps you stay connected to service requests even when using other apps. It uses minimal battery and can be disabled anytime in settings.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
