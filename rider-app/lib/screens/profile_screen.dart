import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/api_service.dart';
import 'change_password_screen.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? user;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  String? _profilePhotoUrl;
  final ImagePicker _picker = ImagePicker();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    setState(() => _isLoading = true);
    final data = await ApiService.fetchUserInfo(forceRefresh: true);
    final photoUrl = await ApiService.getProfilePhotoUrl(forceRefresh: true);
    if (mounted) {
      setState(() {
        user = data;
        _profilePhotoUrl = photoUrl;
        _isLoading = false;
        if (data != null) {
          _firstNameController.text = data['first_name'] ?? '';
          _lastNameController.text = data['last_name'] ?? '';
          _usernameController.text = data['username'] ?? '';
          _emailController.text = data['email'] ?? '';
          _phoneController.text = data['phone'] ?? '';
        }
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!mounted) return;
    setState(() => _isSaving = true);

      final newFirstName = _firstNameController.text.trim();
      final newLastName = _lastNameController.text.trim();
      final newEmail = _emailController.text.trim();
      final newPhone = _phoneController.text.trim();
      
      final currentFirstName = user?['first_name'] ?? '';
      final currentLastName = user?['last_name'] ?? '';
      final currentEmail = user?['email'] ?? '';
      final currentPhone = user?['phone'] ?? '';

      // Check if anything has changed
      final firstNameChanged = newFirstName != currentFirstName;
      final lastNameChanged = newLastName != currentLastName;
      final emailChanged = newEmail != currentEmail;
      final phoneChanged = newPhone != currentPhone;

      if (!firstNameChanged && !lastNameChanged && !emailChanged && !phoneChanged) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No changes to save")),
          );
        }
        setState(() => _isSaving = false);
        return;
      }

      try {
        // Validate inputs
        if (firstNameChanged && newFirstName.isEmpty) {
          throw Exception("First name cannot be empty");
        }
        
        // Validate email format if changed
        if (emailChanged && !_isValidEmail(newEmail)) {
          throw Exception("Please enter a valid email address");
        }

        // Validate phone format if changed
        if (phoneChanged && !_isValidPhone(newPhone)) {
          throw Exception("Please enter a valid phone number");
        }

        final updatedData = <String, String>{};
        if (firstNameChanged) updatedData['first_name'] = newFirstName;
        if (lastNameChanged) updatedData['last_name'] = newLastName;
        if (emailChanged) updatedData['email'] = newEmail;
        if (phoneChanged) updatedData['phone'] = newPhone;

        final result = await ApiService.updateProfile(updatedData);
        
        if (mounted) {
          // If updateProfile returns the user object or success: true
          if (result != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Profile updated successfully!"),
                backgroundColor: Colors.green,
              ),
            );
            _loadUser(); // Refresh to show updated data
          } else {
            throw Exception("Failed to update profile");
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceAll('Exception: ', '')),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
    }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  bool _isValidPhone(String phone) {
    // Basic phone validation - adjust according to your requirements
    return RegExp(r'^[\d\+\-\(\)\s]+$').hasMatch(phone) && phone.length >= 10;
  }

  Future<void> _pickAndUploadPhoto() async {
    // Show choice dialog
    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text("Select Image Source"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text("Take Photo"),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text("Choose from Gallery"),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    // Check permissions
    bool hasPermission = false;
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      hasPermission = status.isGranted;
    } else {
      if (Platform.isAndroid) {
        hasPermission = await Permission.photos.request().isGranted || await Permission.storage.request().isGranted;
      } else {
        hasPermission = await Permission.photos.request().isGranted || await Permission.photos.isLimited;
      }
    }

    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Permission denied. Please enable in settings.")),
        );
      }
      return;
    }

    final XFile? image = await _picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (image == null) return;

    setState(() => _isUploadingPhoto = true);

    final result = await ApiService.uploadProfilePhoto(File(image.path));

    if (mounted) {
      setState(() => _isUploadingPhoto = false);
      if (result != null && result['success'] == true) {
        setState(() {
          _profilePhotoUrl = result['profile_photo_url'];
        });
        // Update cache so drawer shows new photo immediately
        ApiService.getProfilePhotoUrl(forceRefresh: true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Profile photo updated"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to upload photo"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF10223D),
        title: const Text('My Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : user == null
              ? const Center(child: Text("Failed to load profile"))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
                      // Profile Photo
                      GestureDetector(
                        onTap: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 55,
                              backgroundColor: const Color(0xFF10223D).withValues(alpha: 0.1),
                              backgroundImage: _profilePhotoUrl != null
                                  ? NetworkImage(_profilePhotoUrl!)
                                  : null,
                              child: _profilePhotoUrl == null
                                  ? Text(
                                      _getInitials(),
                                      style: const TextStyle(
                                        fontSize: 36,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF10223D),
                                      ),
                                    )
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF8C00),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: _isUploadingPhoto
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.camera_alt,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Tap photo to change",
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                      const SizedBox(height: 24),

                      // Account Information Section
                      _buildAccountInfoSection(),
                      
                      const SizedBox(height: 32),

                      // ID Verification Section REMOVED for Riders
                      // _buildIdVerificationSection(),

                      const SizedBox(height: 32),
                      // Profile Fields
                      _buildReadOnlyField(_firstNameController, "First Name", Icons.person_outline),
                      const SizedBox(height: 16),
                      _buildReadOnlyField(_lastNameController, "Last Name", Icons.person_outline),
                      const SizedBox(height: 16),
                      _buildReadOnlyField(_usernameController, "Username", Icons.account_circle_outlined),
                      const SizedBox(height: 16),
                      _buildEditableField(_emailController, "Email Address", Icons.email_outlined, TextInputType.emailAddress),
                      const SizedBox(height: 16),
                      _buildEditableField(_phoneController, "Phone Number", Icons.phone_outlined, TextInputType.phone),
                      const SizedBox(height: 32),
                      
                      // Change Password Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ChangePasswordScreen(),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF10223D),
                            side: const BorderSide(color: Color(0xFF10223D)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_outline, size: 20),
                              SizedBox(width: 8),
                              Text(
                                "CHANGE PASSWORD",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 32),
                      // Save Button
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).padding.bottom + 16,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF8C00),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 4,
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    "SAVE CHANGES",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      
                      // Delete Account Section
                      _buildDeleteAccountSection(),
                      
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }

  Widget _buildAccountInfoSection() {
    // Calculate time on platform
    final createdAt = user?['created_at'];
    String timeOnPlatform = "New Member";
    if (createdAt != null) {
      try {
        final createDateTime = DateTime.parse(createdAt);
        final now = DateTime.now();
        final difference = now.difference(createDateTime);
        
        if (difference.inDays >= 365) {
          final years = (difference.inDays / 365).floor();
          timeOnPlatform = "$years Year${years > 1 ? 's' : ''} with SRS";
        } else if (difference.inDays >= 30) {
          final months = (difference.inDays / 30).floor();
          timeOnPlatform = "$months Month${months > 1 ? 's' : ''} with SRS";
        } else {
          timeOnPlatform = "${difference.inDays} Day${difference.inDays > 1 ? 's' : ''} with SRS";
        }
      } catch (e) {
        // Keep default if parsing fails
      }
    }

    return Column(
      children: [
        // Account ID Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF10223D),
                const Color(0xFF10223D).withValues(alpha: 0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10223D).withValues(alpha: 0.2),
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
                  Icon(
                    Icons.fingerprint,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Account ID",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[300],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                user?['external_id']?.toString() ?? user?['id']?.toString() ?? "N/A",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Unique identifier for your account",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[400],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Statistics Cards
        Row(
          children: [
            // Rating Card
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.star,
                      color: Color(0xFFFF8C00),
                      size: 24,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      user?['rating']?.toStringAsFixed(1) ?? "0.0",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10223D),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Rating",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            
            // Total Rides Card
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.directions_car,
                      color: Color(0xFF10223D),
                      size: 24,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      user?['total_rides']?.toString() ?? "0",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10223D),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Total Assists",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Time on Platform Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFF8C00).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFF8C00).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.access_time,
                color: const Color(0xFFFF8C00),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      timeOnPlatform,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10223D),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Member since ${createdAt != null ? DateTime.parse(createdAt).toString().split(' ')[0] : 'Unknown'}",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _deleteAccount() async {
    if (mounted) {
      setState(() => _isSaving = true);
    }
    
    try {
      // 1. Check eligibility
      final eligibility = await ApiService.checkDeletionEligibility();
      
      if (!mounted) return;
      setState(() => _isSaving = false);
      
      if (eligibility == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to check account eligibility")),
        );
        return;
      }
      
      if (eligibility['eligible'] == false) {
        final List<dynamic> reasons = eligibility['reasons'] ?? [];
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Account Cannot Be Deleted'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('The following issues must be resolved before you can delete your account:'),
                const SizedBox(height: 12),
                ...reasons.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(child: Text(r.toString())),
                    ],
                  ),
                )),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      // 2. Show deletion confirmation dialog if eligible
      final reasonController = TextEditingController();
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Request Account Deletion'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Are you sure you want to request account deletion? You will be logged out immediately.',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning, color: Colors.red, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Final Notice:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• You will be logged out immediately\n'
                        '• You will not be able to log in again\n'
                        '• This action cannot be undone once processed\n'
                        '• Permanent deletion occurs after 30 days',
                        style: TextStyle(fontSize: 13, color: Colors.red),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Optional: Reason for leaving SRS?',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Tell us why you are leaving...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('CONFIRM DELETION'),
            ),
          ],
        ),
      );

      if (result == true && mounted) {
        setState(() => _isSaving = true);
        
        final deletionReason = reasonController.text.trim();
        try {
          await ApiService.requestAccountDeletion(deletionReason);
          await ApiService.logout();
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen(role: 'RIDER', message: 'Your account has been successfully deleted and session closed.')),
              (route) => false,
            );
          }
        } catch (e) {
          await ApiService.logout();
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen(role: 'RIDER', message: 'Your account has been successfully deleted and session closed.')),
              (route) => false,
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildDeleteAccountSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.delete_outline,
                color: Colors.red,
                size: 24,
              ),
              const SizedBox(width: 8),
              const Text(
                "Delete Account",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "Request to permanently delete your SRS account and data. This action is irreversible once fully processed.",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _isSaving ? null : _deleteAccount,
              icon: const Icon(Icons.delete_forever, size: 20),
              label: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.red,
                      ),
                    )
                  : const Text(
                      "DELETE ACCOUNT",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials() {
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();
    if (first.isNotEmpty && last.isNotEmpty) {
      return '${first[0]}${last[0]}'.toUpperCase();
    }
    if (first.isNotEmpty) return first[0].toUpperCase();
    final username = _usernameController.text.trim();
    return username.isNotEmpty ? username[0].toUpperCase() : '?';
  }



  Widget _buildReadOnlyField(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      enabled: false, // Makes the field read-only
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey[600]),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.grey),
        ),
        filled: true,
        fillColor: Colors.grey[100],
        labelStyle: TextStyle(color: Colors.grey[600]),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      style: const TextStyle(color: Colors.black87),
    );
  }

  Widget _buildEditableField(TextEditingController controller, String label, IconData icon, TextInputType? keyboardType) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF10223D)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF8C00)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}

