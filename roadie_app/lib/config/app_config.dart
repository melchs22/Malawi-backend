/// AppConfig - Centralized configuration for API endpoints and settings
class AppConfig {
  // Default to production URL; can be overridden at runtime
  static String apiBaseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://smartmobilityroadcare.com/api',
  );

  static String wsBaseUrl = const String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'wss://smartmobilityroadcare.com/ws',
  );

  /// Set API base URL at runtime (e.g., for development/staging)
  static void setApiBaseUrl(String url) {
    apiBaseUrl = url;
  }

  /// Set WebSocket base URL at runtime
  static void setWsBaseUrl(String url) {
    wsBaseUrl = url;
  }

  /// Get full API endpoint
  static String getApiUrl(String endpoint) {
    return '$apiBaseUrl$endpoint';
  }

  /// Get full WebSocket endpoint
  static String getWsUrl(String role) {
    return '$wsBaseUrl/$role/';
  }

  // Certificate pinning configuration
  static const Map<String, List<String>> certificatePins = {
    'smartmobilityroadcare.com': [
      // Add your certificate pins here
      // Run: openssl s_client -servername smartmobilityroadcare.com -connect smartmobilityroadcare.com:443 | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64
      // Placeholder - update with actual certificate pins in production
      'sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
    ],
  };

  // Request configuration
  static const Duration requestTimeout = Duration(seconds: 15);
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);
  
  // Token
  static const String tokenExpiryMargin = '5'; // Refresh token 5 seconds before expiry
}
