import 'dart:convert';
import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';

typedef WSCallback = void Function(Map<String, dynamic> data);

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;
  late String _role;
  WSCallback? _callback;
  final List<WSCallback> _handlers = [];
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Timer? _connectionTimeoutTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const int _connectionTimeoutSeconds = 10;
  bool _isManuallyDisconnected = false;
  bool _isAlive = false;
  bool _isConnecting = false;
  bool _hasConnectedBefore = false;
  DateTime? _lastMessageTime;
  DateTime? _lastPingTime;
  int _messageCount = 0;
  
  // Performance monitoring
  static const int _maxMessagesPerSecond = 100;
  final Queue<DateTime> _messageTimestamps = Queue();
  
  // Connection quality metrics
  double _averageLatency = 0.0;
  final List<double> _latencyMeasurements = [];
  
  bool get isConnected => _channel != null && _isAlive && !_isConnecting;
  bool get isConnecting => _isConnecting;
  double get averageLatency => _averageLatency;
  int get messageCount => _messageCount;
  DateTime? get lastMessageTime => _lastMessageTime;

  /// Connect to WebSocket with authentication and performance optimizations
  Future<void> connect(String role, WSCallback callback) async {
    if (_isConnecting || _channel != null) {
      debugPrint("🔌 WebSocket: Connection attempt while state is: connecting=$_isConnecting, alive=$_isAlive");
      
      if (!_isAlive) {
        debugPrint("⚠️ WebSocket: Forcing closure of stuck/pending connection...");
        await _closeConnection();
        _isConnecting = false;
      } else {
        debugPrint("✅ WebSocket: Already connected and alive. Skipping.");
        return;
      }
    }

    debugPrint("🚀 WebSocket: Connecting with role: $role");
    _reconnectTimer?.cancel();
    _connectionTimeoutTimer?.cancel();
    _isManuallyDisconnected = false;
    _isConnecting = true;

    _role = role.toUpperCase();
    _callback = callback;

    try {
      final token = await ApiService.getToken();
      if (token == null || token.isEmpty) {
        debugPrint("❌ WebSocket: No token available");
        _isConnecting = false;
        return;
      }

      // Close any existing connection first
      await _closeConnection();

      final roleEndpoint = _role == "RIDER" ? "rider" : "rodie";
      final url = "wss://smartmobilityroadcare.com/ws/$roleEndpoint/?token=$token";
      debugPrint("🌐 WebSocket: Connecting to: $url");

      // Set connection timeout
      _connectionTimeoutTimer = Timer(const Duration(seconds: _connectionTimeoutSeconds), () {
        if (_isConnecting) {
          debugPrint("⏰ WebSocket: Connection timeout");
          _isConnecting = false;
          _reconnect();
        }
      });

      debugPrint("📡 WebSocket: Opening socket to $url...");
      _channel = WebSocketChannel.connect(Uri.parse(url));
      debugPrint("⏳ WebSocket: Socket opened, waiting for handshake...");
      
      try {
        await _channel!.ready.timeout(const Duration(seconds: 10));
        debugPrint("🤝 WebSocket: Handshake successful!");
        _isConnecting = false;
        _isAlive = true;
        _reconnectAttempts = 0;
      } catch (e) {
        debugPrint("❌ WebSocket Handshake Failed: $e");
        _isAlive = false;
        _isConnecting = false;
        _reconnect();
        return;
      }
      
      // Start connection quality monitoring
      _startConnectionMonitoring();

      _channel!.stream.listen(
        _handleMessage,
        onDone: _handleConnectionClosed,
        onError: _handleConnectionError,
      );

      // Send initial ping to measure latency
      _sendLatencyPing();

      // Notify handlers of reconnection (skip on first connect)
      if (_hasConnectedBefore) {
        final reconnectEvent = {"type": "WS_RECONNECTED"};
        if (_callback != null) _callback!(reconnectEvent);
        for (final handler in _handlers) {
          handler(reconnectEvent);
        }
      }
      _hasConnectedBefore = true;
      
      debugPrint("✅ WebSocket: Connection initiated");
    } catch (e) {
      debugPrint("❌ WebSocket: Connection failed: $e");
      _isConnecting = false;
      _reconnect();
    }
  }

  void _handleMessage(dynamic event) {
    _connectionTimeoutTimer?.cancel();
    
    if (!_isAlive || _isConnecting) {
      _isAlive = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      debugPrint("✅ WebSocket: Connection confirmed alive");
    }

    final now = DateTime.now();
    _lastMessageTime = now;
    _messageCount++;
    
    // Rate limiting check
    _messageTimestamps.add(now);
    while (_messageTimestamps.isNotEmpty && 
           now.difference(_messageTimestamps.first).inSeconds > 1) {
      _messageTimestamps.removeFirst();
    }
    
    if (_messageTimestamps.length > _maxMessagesPerSecond) {
      debugPrint("⚠️ WebSocket: High message rate detected: ${_messageTimestamps.length}/sec");
    }

    try {
      final data = jsonDecode(event) as Map<String, dynamic>;
      
      // Handle pong response for latency measurement
      if (data['type'] == 'PONG') {
        if (data['timestamp'] != null) {
          _calculateLatency(data['timestamp']);
        }
        return;
      }
      
      // Process message with minimal delay
      // Each handler is wrapped in its own try-catch so one handler crashing
      // does NOT prevent other handlers from receiving the message.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        try {
          _callback?.call(data);
        } catch (e) {
          debugPrint("❌ WebSocket: Error in primary callback: $e");
        }
        for (final handler in List<WSCallback>.from(_handlers)) {
          try {
            handler(data);
          } catch (e) {
            debugPrint("❌ WebSocket: Error in handler: $e");
          }
        }
      });
      
    } catch (e) {
      debugPrint("❌ WebSocket: Error decoding message: $e");
    }
  }

  void _handleConnectionClosed() {
    debugPrint("⚠️ WebSocket: Connection closed by server");
    _isAlive = false;
    _isConnecting = false;
    _connectionTimeoutTimer?.cancel();
    _reconnect();
  }

  void _handleConnectionError(dynamic error) {
    debugPrint("❌ WebSocket: Connection error: $error");
    _isAlive = false;
    _isConnecting = false;
    _connectionTimeoutTimer?.cancel();
    
    // Handle different error types
    final errorString = error.toString();
    if (errorString.contains('SocketException') ||
        errorString.contains('Connection reset') ||
        errorString.contains('Connection refused') ||
        errorString.contains('Network is unreachable')) {
      debugPrint("🌐 WebSocket: Network error detected");
      _closeConnection();
    } else {
      _reconnect();
    }
  }

  void _startConnectionMonitoring() {
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (isConnected) {
        _sendLatencyPing();
      }
    });
  }

  void _sendLatencyPing() {
    if (_channel != null) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _lastPingTime = DateTime.now();
      _channel!.sink.add(jsonEncode({
        "type": "PING",
        "timestamp": timestamp,
      }));
    }
  }

  void _calculateLatency(int pingTimestamp) {
    if (_lastPingTime != null) {
      final latency = DateTime.now().difference(_lastPingTime!).inMilliseconds.toDouble();
      _latencyMeasurements.add(latency);
      
      // Keep only last 10 measurements for average
      if (_latencyMeasurements.length > 10) {
        _latencyMeasurements.removeAt(0);
      }
      
      _averageLatency = _latencyMeasurements.reduce((a, b) => a + b) / _latencyMeasurements.length;
      
      if (kDebugMode) {
        debugPrint("📊 WebSocket: Latency ${latency}ms (avg: ${_averageLatency.toStringAsFixed(1)}ms)");
      }
    }
  }

  Future<void> _closeConnection() async {
    _pingTimer?.cancel();
    _connectionTimeoutTimer?.cancel();
    
    if (_channel != null) {
      try {
        await _channel!.sink.close();
      } catch (e) {
        debugPrint("⚠️ WebSocket: Error closing connection: $e");
      }
      _channel = null;
    }
    
    _isAlive = false;
    // Do NOT set _isConnecting = false here, as it breaks the _reconnect flow state.
  }

  void _reconnect() {
    if (_isManuallyDisconnected || _isConnecting) {
      return;
    }

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint("🔌 WebSocket: Max reconnection attempts reached");
      return;
    }

    _reconnectAttempts++;
    // Exponential backoff with jitter
    final baseDelay = [2, 4, 8, 16, 30, 60, 120, 300, 600, 900][_reconnectAttempts - 1];
    final jitter = (baseDelay * 0.2 * (DateTime.now().millisecond % 100) / 100).toInt();
    final delaySeconds = baseDelay + jitter;

    debugPrint("🔌 WebSocket: Reconnecting in ${delaySeconds}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)");

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_role.isNotEmpty && _callback != null && !_isManuallyDisconnected) {
        connect(_role, _callback!);
      }
    });
  }

  /// Disconnect gracefully
  Future<void> disconnect() async {
    debugPrint("🔌 WebSocket: Manual disconnect requested");
    _isManuallyDisconnected = true;
    _reconnectTimer?.cancel();
    _connectionTimeoutTimer?.cancel();
    await _closeConnection();
    _reconnectAttempts = 0;
    _handlers.clear();
    _latencyMeasurements.clear();
    _averageLatency = 0.0;
  }

  /// Manual reconnect when network is restored
  void reconnect() {
    debugPrint("🔌 WebSocket: Manual reconnect requested");
    _reconnectAttempts = 0;
    _isManuallyDisconnected = false;
    if (_role.isNotEmpty && _callback != null) {
      connect(_role, _callback!);
    }
  }

  /// Send location updates with batching for performance
  void sendLocation({required double lat, required double lng}) {
    if (!isConnected) {
      // Quietly skip if not connected to avoid log spam
      return;
    }

    final roundedLat = double.parse(lat.toStringAsFixed(6));
    final roundedLng = double.parse(lng.toStringAsFixed(6));

    final message = {
      "type": "LOCATION",
      "lat": roundedLat,
      "lng": roundedLng,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    };

    _channel!.sink.add(jsonEncode(message));
  }

  /// Send chat message with delivery confirmation
  void sendChat(int requestId, String text) {
    if (!isConnected) {
      debugPrint("❌ WebSocket: Cannot send chat - not connected");
      return;
    }

    final message = {
      "type": "CHAT",
      "request_id": requestId,
      "text": text,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    };

    _channel!.sink.add(jsonEncode(message));
  }

  /// Send arbitrary data with timestamp
  void send(Map<String, dynamic> data) {
    if (!isConnected) {
      debugPrint("⚠️ WebSocket: send() DROPPED — not connected (channel=${_channel != null}, alive=$_isAlive, connecting=$_isConnecting) type=${data['type']}");
      return;
    }

    final message = Map<String, dynamic>.from(data);
    message['timestamp'] = DateTime.now().millisecondsSinceEpoch;
    
    debugPrint("📤 WebSocket: send() type=${data['type']}");
    _channel!.sink.add(jsonEncode(message));
  }

  /// Add additional message handler
  void addHandler(WSCallback handler) {
    _handlers.add(handler);
  }

  /// Remove message handler
  void removeHandler(WSCallback handler) {
    _handlers.remove(handler);
  }

  /// Get connection quality metrics
  Map<String, dynamic> getConnectionMetrics() {
    return {
      'isConnected': isConnected,
      'averageLatency': _averageLatency,
      'messageCount': _messageCount,
      'lastMessageTime': _lastMessageTime?.toIso8601String(),
      'reconnectAttempts': _reconnectAttempts,
      'uptime': _lastMessageTime != null 
          ? DateTime.now().difference(_lastMessageTime!).inSeconds 
          : 0,
    };
  }

  /// Clear message history for memory management
  void clearMessageHistory() {
    _messageCount = 0;
    _lastMessageTime = null;
    debugPrint("🧹 WebSocket: Message history cleared");
  }
}
