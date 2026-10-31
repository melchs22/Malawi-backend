import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/cache/cache_manager.dart';


class SessionInvalidatedException implements Exception {
  final String message;
  SessionInvalidatedException(this.message);
  @override
  String toString() => message;
}

class ApiService {
  static const String baseUrl = "https://smartmobilityroadcare.com/api";
  
  // Stream to notify UI about session invalidation (multiple device login)
  static final StreamController<String> _sessionController = StreamController<String>.broadcast();
  static Stream<String> get sessionInvalidatedStream => _sessionController.stream;

  static const Duration requestTimeout = Duration(seconds: 15);
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);

  // In-memory cache so drawer/profile don't re-fetch every time
  static Map<String, dynamic>? _cachedUserInfo;
  static String? _cachedProfilePhotoUrl;
  static bool _profilePhotoFetched = false;
  
  // Service cache - load once during login, persist for entire session
  static List<dynamic>? _cachedServices;
  static bool _servicesLoaded = false;

  /// Synchronous getters for cached data (used by drawer to avoid flicker)
  static Map<String, dynamic>? get cachedUserInfo => _cachedUserInfo;
  static String? get cachedProfilePhotoUrl => _cachedProfilePhotoUrl;
  static List<dynamic>? get cachedServices => _cachedServices;
  static bool get servicesLoaded => _servicesLoaded;

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("access", token);
    print("💾 [RIDER] Token SAVED to SharedPreferences: ${token.substring(0, 20)}...");
    final verify = prefs.getString("access");
    print("✅ [RIDER] Token VERIFIED in prefs: ${verify != null ? 'YES (${verify.substring(0, 20)}...)' : 'FAILED'}");
  }

  static Future<void> saveRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("role", role);
  }

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("role");
  }

  static Future<bool> updateFcmToken(String token) async {
    try {
      final result = await patch("/profile/", {"fcm_token": token});
      if (result != null) {
        print("✅ [RIDER] FCM token updated on backend");
        return true;
      }
      return false;
    } catch (e) {
      print("❌ [RIDER] Failed to update FCM token: $e");
      return false;
    }
  }

  static Map<String, dynamic>? _parseJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = parts[1];
      var normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      return jsonDecode(decoded) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getUserData() async {
    final token = await getToken();
    if (token == null) return null;
    return _parseJwtPayload(token);
  }

  /// Corrected: Backend uses /api/me/ for profile information
  static Future<Map<String, dynamic>?> fetchUserInfo({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedUserInfo != null) return _cachedUserInfo;
    try {
      final result = await get("/me/");
      if (result is Map<String, dynamic>) {
        _cachedUserInfo = result;
        return result;
      }
      return null;
    } catch (e) {
      if (e is SessionInvalidatedException) rethrow;
      print("❌ [RIDER] Failed to fetch user info: $e");
      return null;
    }
  }

  static Future<void> logout() async {
    _cachedUserInfo = null;
    _cachedProfilePhotoUrl = null;
    _profilePhotoFetched = false;
    _cachedServices = null;
    _servicesLoaded = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("access");
    await prefs.remove("refresh"); // Clear refresh token to prevent auto-login
    await prefs.remove("role");
    
    // Clear Hive cache
    try {
      await CacheManager().clearAll();
    } catch (e) {
      debugPrint("Cache clear error: $e");
    }
  }


  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("access");
    print("🔍 [RIDER] getToken() called → ${token != null ? 'FOUND (${token.substring(0, 20)}...)' : 'NULL - NO TOKEN STORED'}");
    return token;
  }

  /// Helper method to retry failed network requests
  static Future<http.Response?> _retryablePost(
    Uri url,
    Map<String, String> headers,
    String body,
  ) async {
    int retries = 0;
    while (retries < maxRetries) {
      try {
        print("📤 POST attempt ${retries + 1}/$maxRetries to: $url");
        final response = await http.post(
          url,
          headers: headers,
          body: body,
        ).timeout(requestTimeout, onTimeout: () {
          throw TimeoutException("Request timeout after $requestTimeout");
        });
        print("📥 Response received: ${response.statusCode}");
        return response;
      } on SocketException catch (e) {
        print("⚠️ Network error (attempt ${retries + 1}): $e");
        retries++;
        if (retries < maxRetries) {
          await Future.delayed(retryDelay);
        }
      } on TimeoutException catch (e) {
        print("⏱️ Timeout (attempt ${retries + 1}): $e");
        retries++;
        if (retries < maxRetries) {
          await Future.delayed(retryDelay);
        }
      }
    }
    return null;
  }

  /// Helper method to retry failed GET requests
  static Future<http.Response?> _retryableGet(
    Uri url,
    Map<String, String> headers,
  ) async {
    int retries = 0;
    while (retries < maxRetries) {
      try {
        print("📤 GET attempt ${retries + 1}/$maxRetries to: $url");
        final response = await http.get(
          url,
          headers: headers,
        ).timeout(requestTimeout, onTimeout: () {
          throw TimeoutException("Request timeout after $requestTimeout");
        });
        print("📥 Response received: ${response.statusCode}");
        return response;
      } on SocketException catch (e) {
        print("⚠️ Network error (attempt ${retries + 1}): $e");
        retries++;
        if (retries < maxRetries) {
          await Future.delayed(retryDelay);
        }
      } on TimeoutException catch (e) {
        print("⏱️ Timeout (attempt ${retries + 1}): $e");
        retries++;
        if (retries < maxRetries) {
          await Future.delayed(retryDelay);
        }
      }
    }
    return null;
  }

  static Future<dynamic> signup({
    required String username,
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
    required String role,
    String? nin, // Made optional (nullable)
    String? referredByCode,
  }) async {
    try {
      final Map<String, dynamic> data = {
        "username": username,
        "email": email,
        "password": password,
        "first_name": firstName,
        "last_name": lastName,
        "phone": phone,
        "role": role,
      };
      
      // Only include NIN if provided (for roadies and mechanics)
      if (nin != null && nin.isNotEmpty) {
        data["nin"] = nin;
      }
      
      // Add referral code if provided
      if (referredByCode != null && referredByCode.isNotEmpty) {
        data["referred_by_code"] = referredByCode;
      }
      
      final response = await post("/register/", data);
      if (response != null && response["id"] != null) {
        // Automatically login after successful signup
        return await login(username, password, role);
      } else if (response != null && response is Map) {
        // Return validation errors if any
        print("❌ Registration failed with errors: $response");
        return response; // Return the error map for handling in UI
      } else {
        print("❌ Registration failed: No valid response");
        return false;
      }
    } catch (e) {
      print(" Signup error: $e");
      return false;
    }
  }

  static Future<bool> login(
    String username,
    String password,
    String role,
  ) async {
    final url = Uri.parse("$baseUrl/login/${role.toLowerCase()}/");
    print(" Login attempt: user=$username, role=$role, url=$url");
    print("🔐 Login attempt: user=$username, role=$role, url=$url");
    try {
      final response = await _retryablePost(
        url,
        {"Content-Type": "application/json"},
        jsonEncode({"username": username, "password": password}),
      );

      if (response == null) {
        print("❌ Login failed: No response after retries");
        return false;
      }

      print("📨 Login response: status=${response.statusCode}");
      print("📦 Response body: ${response.body}");
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await saveToken(data["access"]);
        // Save refresh token if present
        if (data["refresh"] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('refresh_token', data["refresh"]);
        }
        await saveRole(role);
        print("✅ Login successful!");
        return true;
      } else {
        print("❌ Login failed with status ${response.statusCode}");
        if (response.body.isNotEmpty) {
          try {
            final errorData = jsonDecode(response.body);
            print("❌ Error details: $errorData");
          } catch (_) {}
        }
        return false;
      }
    } catch (e) {
      print("❌ Login exception: $e");
      return false;
    }
  }

  /// Token refresh logic
  static Future<bool> _refreshTokenIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh_token');
    if (refreshToken == null) {
      print("⚠️ No refresh token available");
      return false;
    }
    
    try {
      final url = Uri.parse("$baseUrl/refresh/");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"refresh": refreshToken}),
      ).timeout(requestTimeout);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await saveToken(data["access"]);
        print("✅ Token refreshed successfully");
        return true;
      } else {
        print("❌ Token refresh failed: ${response.statusCode}");
        return false;
      }
    } catch (e) {
      print("❌ Token refresh error: $e");
      return false;
    }
  }

  /// Internal helper to check for and handle session invalidation or natural expiration
  static Future<bool> _handleSessionInvalidation(http.Response response) async {
    if (response.statusCode == 401) {
      if (response.body.isNotEmpty) {
        try {
          final errorData = jsonDecode(response.body);
          final detail = errorData['detail'] ?? '';
          final code = errorData['code'] ?? '';
          
          if (detail.contains('session is no longer valid') || 
              detail.contains('Another device') ||
              code == 'session_invalidated') {
            print("🔓 [RIDER] Session invalidated - another device logged in");
            _sessionController.add('You have been logged out because you logged in on another device.');
            await logout();
            return true;
          }
          
          if (code == 'token_not_valid' || detail.contains('given token has expired')) {
            print("🔄 [RIDER] Access token expired. Attempting silent refresh...");
            final refreshed = await _refreshTokenIfNeeded();
            if (refreshed) return false;
          }
        } catch (e) {
          print("Error parsing 401 response: $e");
        }
      }
      await logout();
    }
    return false;
  }

  static Future<dynamic> post(
    String endpoint,
    Map body, {
    bool requiresAuth = true,
  }) async {
    final url = Uri.parse("$baseUrl$endpoint");
    try {
      Future<http.Response?> makeCall() async {
        Map<String, String> headers = {"Content-Type": "application/json"};
        if (requiresAuth) {
          final token = await getToken();
          if (token != null) headers["Authorization"] = "Bearer $token";
        }
        return await _retryablePost(url, headers, jsonEncode(body));
      }

      var response = await makeCall();
      if (response != null && response.statusCode == 401) {
        if (await _handleSessionInvalidation(response)) {
          throw SessionInvalidatedException('You have been logged out because you logged in on another device.');
        }
        // If it wasn't a hard invalidation, it was likely an expired token that was just refreshed. Retry once.
        response = await makeCall();
      }

      if (response == null) {
        print("❌ Networking error: No response received");
        return null;
      }
      
      if (response.statusCode >= 400) {
        print("❌ API error ${response.statusCode} on $endpoint");
        if (response.body.isNotEmpty) {
          try {
            final errorBody = jsonDecode(response.body);
            print("❌ Error body: $errorBody");
            return errorBody; // Return error body for validation handling
          } catch (e) {
            print("❌ Failed to decode error body: $e");
          }
        }
        return null;
      }

      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    } catch (e) {
      if (e is SessionInvalidatedException) rethrow;
      print("❌ POST error: $e");
      return null;
    }
  }

  /// Helper method to retry failed PATCH requests
  static Future<http.Response?> _retryablePatch(
    Uri url,
    Map<String, String> headers,
    String body,
  ) async {
    int retries = 0;
    while (retries < maxRetries) {
      try {
        print("📤 PATCH attempt ${retries + 1}/$maxRetries to: $url");
        final response = await http.patch(
          url,
          headers: headers,
          body: body,
        ).timeout(requestTimeout, onTimeout: () {
          throw TimeoutException("Request timeout after $requestTimeout");
        });
        print("📥 Response received: ${response.statusCode}");
        return response;
      } on SocketException catch (e) {
        print("⚠️ Network error (attempt ${retries + 1}): $e");
        retries++;
        if (retries < maxRetries) {
          await Future.delayed(retryDelay);
        }
      } catch (e) {
        print("❌ PATCH attempt ${retries + 1} failed: $e");
        retries++;
        if (retries < maxRetries) {
          await Future.delayed(retryDelay);
        }
      }
    }
    print("❌ PATCH failed after $maxRetries attempts");
    return null;
  }

  static Future<dynamic> patch(
    String endpoint,
    Map body, {
    bool requiresAuth = true,
  }) async {
    final url = Uri.parse("$baseUrl$endpoint");
    try {
      final String? token = await getToken();
      Map<String, String> headers = {"Content-Type": "application/json"};
      if (token != null) headers["Authorization"] = "Bearer $token";
      
      final response = await _retryablePatch(
        url,
        headers,
        jsonEncode(body),
      );

      if (response == null) {
        print("⚠️ PATCH $endpoint failed after retries");
        return null;
      }

      if (await _handleSessionInvalidation(response)) {
        throw SessionInvalidatedException(
          'You have been logged out because you logged in on another device.'
        );
      }

      if (response.statusCode >= 400) {
        print("📥 [RIDER] PATCH $endpoint returned status ${response.statusCode}");
        if (response.body.isNotEmpty) {
          try {
            return jsonDecode(response.body);
          } catch (_) {}
        }
        return null;
      }

      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    } catch (e) {
      if (e is SessionInvalidatedException) rethrow;
      print("❌ PATCH error: $e");
      return null;
    }
  }

  static Future<dynamic> get(String endpoint) async {
    final token = await getToken();
    if (token == null) {
      print("⚠️ [RIDER] No token available for GET $endpoint");
      return null;
    }
    print("🔐 [RIDER] Adding Authorization header: Bearer ${token.substring(0, 20)}...");
    try {
      final url = Uri.parse("$baseUrl$endpoint");
      print("📡 [RIDER] Making GET request to: $url");
      final response = await _retryableGet(
        url,
        {"Authorization": "Bearer $token"},
      );

      if (response == null) {
        print("⚠️ [RIDER] GET $endpoint failed after retries");
        return null;
      }

      print("📊 [RIDER] Response status: ${response.statusCode}");

      if (response.statusCode == 401) {
        print("🔓 [RIDER] Unauthorized (401)");
        
        // CHECK SESSION FIRST
        if (await _handleSessionInvalidation(response)) {
          throw SessionInvalidatedException(
            'You have been logged out because you logged in on another device.'
          );
        }

        // Try to refresh token if it's a normal expiration
        final refreshed = await _refreshTokenIfNeeded();
        if (refreshed) {
          print("✅ Token refreshed, retrying request");
          final newToken = await getToken();
          if (newToken != null) {
            final retryResponse = await _retryableGet(
              url,
              {"Authorization": "Bearer $newToken"},
            );
            if (retryResponse != null) {
              if (retryResponse.statusCode == 200) {
                return jsonDecode(retryResponse.body);
              } else {
                await _handleSessionInvalidation(retryResponse);
              }
            }
          }
        }
        await logout();
        throw SessionInvalidatedException("Your session has expired. Please log in again.");
      }

      // Handle non-200 status codes
      if (response.statusCode != 200 && response.statusCode != 201) {
        print("❌ [RIDER] GET $endpoint returned status ${response.statusCode}");
        print("📋 Response: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}");
        return null;
      }

      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    } catch (e) {
      if (e is SessionInvalidatedException) rethrow;
      print("❌ GET error: $e");
      return null;
    }
  }

  /// Corrected: Backend uses /api/services/ for general service listing
  static Future<List<dynamic>> getServices() async {
    // Return cached services if already loaded
    if (_servicesLoaded && _cachedServices != null && _cachedServices!.isNotEmpty) {
      print("📦 [RIDER] Returning cached services: ${_cachedServices!.length} services");
      return _cachedServices!;
    }
    
    try {
      print("🔄 [RIDER] Fetching services from API...");
      final response = await get("/services/");
      
      if (response == null) {
        print("⚠️ [RIDER] API returned null for services. Keeping current cache if any.");
        return _cachedServices ?? [];
      }

      List<dynamic> services = [];
      bool success = false;
      if (response is List) {
        services = response;
        success = true;
      } else if (response is Map && response.containsKey('results')) {
        services = response['results'];
        success = true;
      }
      
      if (success) {
        // Cache the services for the entire session
        _cachedServices = services;
        _servicesLoaded = true;
        print("✅ [RIDER] Services cached: ${services.length} services");
        return services;
      }
      
      return _cachedServices ?? [];
    } catch (e) {
      if (e is SessionInvalidatedException) rethrow;
      print("❌ [RIDER] Failed to fetch services: $e");
      return _cachedServices ?? [];
    }
  }

  /// Method to pre-load services during login
  static Future<void> preloadServices() async {
    if (!_servicesLoaded) {
      print("🚀 [RIDER] Pre-loading services during login...");
      await getServices();
    }
  }

  /// Method to clear service cache (for logout or refresh)
  static void clearServiceCache() {
    _cachedServices = null;
    _servicesLoaded = false;
    print("🗑️ [RIDER] Service cache cleared");
  }

  /// Wallet APIs
  static Future<Map<String, dynamic>?> getWallet() async {
    final response = await get("/wallet/");
    return response is Map<String, dynamic> ? response : null;
  }

  /// Initiate a deposit — backend creates the Pesapal order and returns redirect URL.
  /// No amount or phone needed from the app; Pesapal lets user enter amount on their page.
  static Future<Map<String, dynamic>?> depositFunds(double amount) async {
    try {
      final response = await post("/wallet/deposit/", {"amount": amount}, requiresAuth: true);
      return response is Map<String, dynamic> ? response : null;
    } catch (e) {
      debugPrint("[RIDER] Deposit error: $e");
      return null;
    }
  }

  /// Withdraw funds — min UGX 5,000 per transaction.
  static Future<Map<String, dynamic>?> withdrawFunds(double amount, String phoneNumber) async {
    try {
      final response = await post("/wallet/withdraw/", {
        "amount": amount,
        "phone_number": phoneNumber,
      }, requiresAuth: true);
      return response is Map<String, dynamic> ? response : null;
    } catch (e) {
      debugPrint("[RIDER] Withdrawal error: $e");
      return null;
    }
  }

  /// Check payment status by reference.
  static Future<Map<String, dynamic>?> checkPaymentStatus(String reference) async {
    try {
      final response = await get("/payments/status/$reference/");
      return response is Map<String, dynamic> ? response : null;
    } catch (e) {
      debugPrint("[RIDER] Payment status check error: $e");
      return null;
    }
  }

  /// Image Upload API (KYC)
  static Future<dynamic> uploadUserImage(File image, String type) async {
    final token = await getToken();
    if (token == null) return null;

    var request = http.MultipartRequest(
      'POST',
      Uri.parse("$baseUrl/images/user-images/"),
    );
    request.headers['Authorization'] = "Bearer $token";
    request.fields['image_type'] = type;
    request.files.add(await http.MultipartFile.fromPath('image', image.path));

    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);
    return jsonDecode(response.body);
  }

  /// History APIs
  static Future<List<dynamic>> getMyRequests({String? status}) async {
    final endpoint = status != null
        ? "/requests/my/?status=$status"
        : "/requests/my/";
    final response = await get(endpoint);
    return response is List ? response : [];
  }

  /// Referral APIs
  static Future<List<dynamic>> getReferrals() async {
    final response = await get("/referrals/");
    return response is List ? response : [];
  }

  /// Notification APIs
  static Future<List<dynamic>> getNotifications() async {
    final response = await get("/notifications/");
    return response is List ? response : [];
  }

  static Future<bool> markNotificationAsRead(int notificationId) async {
    final response = await patch("/notifications/$notificationId/", {"is_read": true});
    return response != null;
  }

  /// Nearby search
  static Future<List<dynamic>> searchNearbyRoadies(
    double lat,
    double lng,
    int serviceId,
  ) async {
    final endpoint =
        "/requests/nearby/?lat=$lat&lng=$lng&service_id=$serviceId";
    final response = await get(endpoint);
    return response is List ? response : [];
  }

  static Future<dynamic> createRequest({
    required int serviceTypeId,
    required double riderLat,
    required double riderLng,
    String notes = "",
  }) async {
    return await post("/requests/create/", {
      "service_type": serviceTypeId,
      "rider_lat": double.parse(riderLat.toStringAsFixed(6)),
      "rider_lng": double.parse(riderLng.toStringAsFixed(6)),
      "notes": notes,
    }, requiresAuth: true);
  }

  /// Forgot Password APIs
  static Future<Map<String, dynamic>?> sendPasswordResetCode(String email, String role) async {
    try {
      final response = await post("/auth/password-reset/", {
        "email": email,
        "role": role,
      });
      return response is Map<String, dynamic> ? response : null;
    } catch (e) {
      debugPrint("❌ Reset code request error: $e");
      return null;
    }
  }

  static Future<Map<String, dynamic>?> confirmPasswordReset({
    required String email,
    required String role,
    required String code,
    required String newPassword,
  }) async {
    try {
      final response = await post("/auth/password-reset/confirm/", {
        "email": email,
        "role": role,
        "code": code,
        "new_password": newPassword,
      });
      return response is Map<String, dynamic> ? response : null;
    } catch (e) {
      debugPrint("❌ Password confirm error: $e");
      return null;
    }
  }

  static Future<dynamic> cancelRequest(int requestId) async {
    // Note: Backend requires a reason_id (CancellationReason model). 
    // Usually 1 is a safe 'General' default or we should fetch reasons first.
    return await post("/requests/$requestId/cancel/", {
      "reason_id": 1, // Defaulting to 1, ideally should be chosen by user
      "custom_reason_text": "Cancelled by rider via app"
    }, requiresAuth: true);
  }

  /// Profile update API (PATCH /api/profile/)
  static Future<Map<String, dynamic>?> updateProfile(Map<String, dynamic> fields) async {
    final token = await getToken();
    if (token == null) return null;
    try {
      final url = Uri.parse("$baseUrl/profile/");
      final response = await http.patch(
        url,
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode(fields),
      ).timeout(requestTimeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Upload profile photo (POST /api/profile/photo/)
  static Future<Map<String, dynamic>?> uploadProfilePhoto(File image) async {
    final token = await getToken();
    if (token == null) return null;
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("$baseUrl/profile/photo/"),
      );
      request.headers['Authorization'] = "Bearer $token";
      request.files.add(
        await http.MultipartFile.fromPath('profile_photo', image.path),
      );
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get profile photo URL (GET /api/profile/photo/)
  static Future<String?> getProfilePhotoUrl({bool forceRefresh = false}) async {
    if (!forceRefresh && _profilePhotoFetched) return _cachedProfilePhotoUrl;
    try {
      final result = await get("/profile/photo/");
      _profilePhotoFetched = true;
      if (result is Map && result['profile_photo_url'] != null) {
        _cachedProfilePhotoUrl = result['profile_photo_url'];
        return _cachedProfilePhotoUrl;
      }
      _cachedProfilePhotoUrl = null;
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Change password (POST /api/profile/change-password/)
  static Future<Map<String, dynamic>?> changePassword(String currentPassword, String newPassword) async {
    final token = await getToken();
    if (token == null) return null;
    
    try {
      final url = Uri.parse("$baseUrl/profile/change-password/");
      final response = await http.post(
        url,
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "current_password": currentPassword,
          "new_password": newPassword,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 400) {
        // Return error response for validation errors
        final errorData = jsonDecode(response.body);
        return {
          'success': false,
          'error': errorData['error'] ?? errorData['message'] ?? 'Invalid current password',
        };
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<List<dynamic>> fetchChatHistory(int requestId) async {
    final response = await get("/requests/$requestId/chat/");
    return response is List ? response : [];
  }

  /// Account Deletion APIs
  static Future<Map<String, dynamic>?> checkDeletionEligibility() async {
    return await get("/profile/deletion-eligibility/");
  }

  static Future<Map<String, dynamic>?> requestAccountDeletion(String reason) async {
    return await post("/profile/request-deletion/", {"reason": reason}, requiresAuth: true);
  }

  static Future<Map<String, dynamic>?> submitFeedback(String message, {String type = 'app_feedback'}) async {
    try {
      final response = await post("/feedback/", {
        "message": message,
        "type": type,
      }, requiresAuth: true);
      return response is Map<String, dynamic> ? response : null;
    } catch (e) {
      debugPrint("❌ Feedback submission error: $e");
      return null;
    }
  }
}

