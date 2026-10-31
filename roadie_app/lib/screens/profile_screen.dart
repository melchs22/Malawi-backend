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
  bool _isUploadingIdFront = false;
  bool _isUploadingIdBack = false;
  bool _isUploadingLicense = false;
  bool _isUploadingVehicle = false;
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
    final data = await ApiService.fetchUserInfo();
    if (mounted) {
      setState(() {
        user = data;
        _firstNameController.text = data?['first_name'] ?? '';
        _lastNameController.text = data?['last_name'] ?? '';
        _usernameController.text = data?['username'] ?? '';
        _emailController.text = data?['email'] ?? '';
        _phoneController.text = data?['phone'] ?? '';
        _isLoading = false;
      });
    }
  }

  Future<void> _uploadImage(String type) async {
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
      // For gallery, handling varies by OS but permission_handler handles it
      if (Platform.isAndroid) {
        // Android 13+ uses different permissions for photos
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

    final XFile? image = await _picker.pickImage(source: source, imageQuality: 70);
    if (image == null) return;

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("Uploading $type...")));

    final response = await ApiService.uploadUserImage(File(image.path), type);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response != null
                ? "Successfully uploaded $type"
                : "Failed to upload $type",
          ),
          backgroundColor: response != null ? Colors.green : Colors.red,
        ),
      );
      if (response != null) _loadUser(); // Refresh user data
    }
  }

  Future<void> _uploadIdImage(String idSide) async {
    // Show choice dialog for camera or gallery
    final String title = idSide == 'License' || idSide == 'Vehicle' ? idSide : "$idSide ID";
    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Upload $title"),
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
        );
      },
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

    // Set loading state
    setState(() {
      if (idSide == 'Front') {
        _isUploadingIdFront = true;
      } else if (idSide == 'Back') {
        _isUploadingIdBack = true;
      } else if (idSide == 'License') {
        _isUploadingLicense = true;
      } else if (idSide == 'Vehicle') {
        _isUploadingVehicle = true;
      }
    });

    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      
      if (image == null) {
        if (mounted) {
          setState(() {
            if (idSide == 'Front') {
              _isUploadingIdFront = false;
            } else if (idSide == 'Back') {
              _isUploadingIdBack = false;
            } else if (idSide == 'License') {
              _isUploadingLicense = false;
            } else if (idSide == 'Vehicle') {
              _isUploadingVehicle = false;
            }
          });
        }
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Uploading $title...")),
      );

      String type;
      if (idSide == 'Front') {
        type = 'NIN_FRONT';
      } else if (idSide == 'Back') {
        type = 'NIN_BACK';
      } else if (idSide == 'License') {
        type = 'LICENSE';
      } else if (idSide == 'Vehicle') {
        type = 'VEHICLE';
      } else {
        type = 'OTHER';
      }

      final response = await ApiService.uploadUserImage(
        File(image.path), 
        type
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response != null
                  ? "Successfully uploaded $title"
                  : "Failed to upload $title",
            ),
            backgroundColor: response != null ? Colors.green : Colors.red,
          ),
        );
        if (response != null) _loadUser(); // Refresh user data
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error uploading $title: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (idSide == 'Front') {
            _isUploadingIdFront = false;
          } else if (idSide == 'Back') {
            _isUploadingIdBack = false;
          } else if (idSide == 'License') {
            _isUploadingLicense = false;
          } else if (idSide == 'Vehicle') {
            _isUploadingVehicle = false;
          }
        });
      }
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

    // Check what has actually changed
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
      // Validate email format if changed
      if (emailChanged && !_isValidEmail(newEmail)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Please enter a valid email address"),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isSaving = false);
        return;
      }

      // Validate phone format if changed
      if (phoneChanged && !_isValidPhone(newPhone)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Please enter a valid phone number"),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isSaving = false);
        return;
      }

      final updatedData = <String, String>{};
      
      if (firstNameChanged) {
        updatedData['first_name'] = newFirstName;
      }
      
      if (lastNameChanged) {
        updatedData['last_name'] = newLastName;
      }
      
      if (emailChanged) {
        updatedData['email'] = newEmail;
      }
      
      if (phoneChanged) {
        updatedData['phone'] = newPhone;
      }

      final response = await ApiService.patch("/profile/", updatedData, requiresAuth: true);
      
      if (mounted) {
        if (response != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Profile updated successfully!"),
              backgroundColor: Colors.green,
            ),
          );
          _loadUser(); // Refresh to show updated data
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Failed to update profile. This information might already be in use."),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = "Error updating profile";
        
        // Check for specific duplicate errors in exception
        if (e.toString().toLowerCase().contains('already exists') || 
            e.toString().toLowerCase().contains('unique constraint')) {
          if (e.toString().toLowerCase().contains('email')) {
            errorMessage = "This email address is already registered";
          } else if (e.toString().toLowerCase().contains('phone')) {
            errorMessage = "This phone number is already registered";
          } else {
            errorMessage = "This information is already in use";
          }
        } else {
          errorMessage = "Error: $e";
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text("My Profile"),
        backgroundColor: const Color(0xFF10223D),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF8C00)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Profile Photo Section
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: Colors.grey[300],
                          backgroundImage: user?['profile_photo'] != null
                              ? NetworkImage(user!['profile_photo'])
                              : null,
                          child: user?['profile_photo'] == null
                              ? const Icon(Icons.person, size: 60, color: Colors.grey)
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () => _uploadImage('PROFILE'),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF8C00),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Account Information Section
                  _buildAccountInfoSection(),

                  const SizedBox(height: 24),

                  // Profile Form
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildReadOnlyField(_firstNameController, "First Name", Icons.person),
                          _buildReadOnlyField(_lastNameController, "Last Name", Icons.person_outline),
                          _buildReadOnlyField(_usernameController, "Username", Icons.alternate_email),
                          _buildTextField(_emailController, "Email Address", Icons.email),
                          _buildTextField(_phoneController, "Phone Number", Icons.phone),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

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

                  const SizedBox(height: 24),

                  // ID Verification Section
                  _buildIdVerificationSection(),

                  // Delete Account Section
                  _buildDeleteAccountSection(),

                  // Save Button
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom + 16,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8C00),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _isSaving
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text(
                                "Save Changes",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ),
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
                    Icon(
                      Icons.star,
                      color: const Color(0xFFFF8C00),
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
            
            // Total Jobs Card
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
                    Icon(
                      Icons.work,
                      color: const Color(0xFF10223D),
                      size: 24,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      user?['total_jobs']?.toString() ?? "0",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10223D),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Total Jobs",
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
              MaterialPageRoute(builder: (_) => const LoginScreen(role: 'RODIE', message: 'Your account has been successfully deleted and session closed.')),
              (route) => false,
            );
          }
        } catch (e) {
          await ApiService.logout();
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen(role: 'RODIE', message: 'Your account has been successfully deleted and session closed.')),
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

  Widget _buildIdVerificationSection() {
    final bool isVerified = user?['is_verified'] == true;
    final String? idFrontUrl = user?['id_card_front'];
    final String? idBackUrl = user?['id_card_back'];
    
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isVerified ? Icons.verified : Icons.pending,
                color: isVerified ? Colors.green : Colors.orange,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                "ID Verification",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isVerified ? Colors.green : Colors.orange,
                ),
              ),
              const Spacer(),
              if (isVerified)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "Verified",
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "Pending",
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isVerified 
                ? "Your ID has been verified by SRS administrators."
                : "Upload clear images of your ID card for account verification.",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          
          // Front ID Card
          _buildIdCardItem(
            title: "Front of ID",
            imageUrl: idFrontUrl,
            isLoading: _isUploadingIdFront,
            onTap: () => _uploadIdImage('Front'),
          ),
          
          const SizedBox(height: 12),
          
          // Back ID Card
          _buildIdCardItem(
            title: "Back of ID",
            imageUrl: idBackUrl,
            isLoading: _isUploadingIdBack,
            onTap: () => _uploadIdImage('Back'),
          ),
          
          if (!isVerified) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Clear ID images are required for account approval. You can retake or upload new images if needed.",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIdCardItem({
    required String title,
    String? imageUrl,
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          // ID Image or Placeholder
          if (imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageUrl,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildIdPlaceholder(title);
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: Colors.grey[100],
                    child: const Center(
                      child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
                    ),
                  );
                },
              ),
            )
          else
            _buildIdPlaceholder(title),
          
          // Upload Button Overlay
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: isLoading ? null : onTap,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Title at bottom
                      Positioned(
                        bottom: 8,
                        left: 8,
                        right: 8,
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // Upload/Loading indicator at center
                      Center(
                        child: isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              )
                            : Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  imageUrl != null ? Icons.refresh : Icons.camera_alt,
                                  color: const Color(0xFFFF8C00),
                                  size: 24,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdPlaceholder(String title) {
    return Container(
      color: Colors.grey[100],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.credit_card,
            size: 40,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyField(TextEditingController controller, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        enabled: false, // Makes the field read-only
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.grey[600]),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.grey),
          ),
          filled: true,
          fillColor: Colors.grey[100],
          labelStyle: TextStyle(color: Colors.grey[600]),
        ),
        style: const TextStyle(color: Colors.black87),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: const Color(0xFF10223D)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFFF8C00)),
          ),
        ),
      ),
    );
  }
}
