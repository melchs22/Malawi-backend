import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import '../services/api_service.dart';
import 'login_screen.dart';
import 'id_verification_screen.dart';
import '../services/notification_service.dart';

class RegisterScreen extends StatefulWidget {
  final String role;
  const RegisterScreen({required this.role, super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final phoneController = TextEditingController();
  final ninController = TextEditingController();
  final referralController = TextEditingController();
  bool isLoading = false;
  bool isPasswordVisible = false;
  bool agreedToTerms = false;

  void _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You must agree to the Privacy Policy and Terms of Service to continue"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => isLoading = true);

    final result = await ApiService.signup(
      username: usernameController.text,
      email: emailController.text,
      password: passwordController.text,
      firstName: firstNameController.text,
      lastName: lastNameController.text,
      phone: phoneController.text,
      role: widget.role,
      nin: ninController.text, // Roadies still provide NIN
      referredByCode: referralController.text.trim().isEmpty ? null : referralController.text.trim(),
    );

    setState(() => isLoading = false);

    if (result == true && mounted) {
      // Register FCM token now that we are registered and logged in
      await NotificationService().refreshRegistration();
      
      if (widget.role == 'RODIE') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You’ll be notified once your SRS account is approved to go online."),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => IDVerificationScreen(role: widget.role),
          ),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Account created successfully! Please log in."),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => LoginScreen(role: widget.role)),
          (route) => false,
        );
      }
    } else if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Center(child: Text("Registration Failed", style: TextStyle(fontWeight: FontWeight.bold))),
          content: Text(
            Platform.isIOS
                ? "Please check if the following details have already been used:\n"
                  "• Username\n"
                  "• Phone Number\n"
                  "• Email Address"
                : "Please check if the following details have already been used:\n"
                  "• Username\n"
                  "• Phone Number\n"
                  "• Email Address\n"
                  "• NIN",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  const Text(
                    "Welcome to SRS",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Let's get you started",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                      fontWeight: FontWeight.w300,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.role == 'RODIE' ? "Create your mechanic account" : "Create your ${widget.role.toLowerCase()} account",
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                      fontWeight: FontWeight.w300,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  _buildField(firstNameController, "First Name", Icons.person_outline),
                  const SizedBox(height: 16),
                  _buildField(lastNameController, "Last Name", Icons.person_outline),
                  const SizedBox(height: 16),
                  _buildField(usernameController, "Username", Icons.account_circle_outlined),
                  const SizedBox(height: 16),
                  _buildField(emailController, "Email", Icons.email_outlined, keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 16),
                  _buildField(phoneController, "Phone Number", Icons.phone_outlined, keyboardType: TextInputType.phone),
                  const SizedBox(height: 16),
                  // On iOS: NIN is optional at sign-up (Apple App Store policy 5.1.1v).
                  // NIN is still collected — but as a voluntary field here.
                  // iOS users who skip it will be prompted to add it before going online.
                  // On Android: NIN remains required at registration.
                  TextFormField(
                    controller: ninController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: Platform.isIOS ? "NIN (14 Characters) – Optional" : "NIN (14 Characters)",
                      labelStyle: const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(Icons.badge_outlined, color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.1),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
                      helperText: Platform.isIOS ? "You can add this later in your profile" : null,
                      helperStyle: const TextStyle(color: Colors.white54),
                    ),
                    // iOS: optional — validate only if something was entered (must be correct length if provided)
                    // Android: required — must be exactly 14 characters
                    validator: (v) {
                      if (Platform.isIOS) {
                        if (v != null && v.isNotEmpty && v.length != 14) {
                          return "NIN must be 14 characters";
                        }
                        return null; // empty is fine on iOS
                      }
                      return (v == null || v.length != 14) ? "NIN must be 14 characters" : null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: referralController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Referral Code (Optional)",
                      labelStyle: const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(Icons.card_giftcard_outlined, color: Colors.white70),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.info_outline, color: Colors.white70),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: const Color(0xFF1D3B63),
                              title: const Text("Referral Code", style: TextStyle(color: Colors.white)),
                              content: const Text(
                                "Enter a referral code to get a welcome bonus!\n\n"
                                "If someone invited you to join SRS, ask them for their referral code.",
                                style: TextStyle(color: Colors.white70),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text("Got it", style: TextStyle(color: Color(0xFFFF8C00))),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.1),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passwordController,
                    obscureText: !isPasswordVisible,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Password",
                      labelStyle: const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(Icons.lock_outline, color: Colors.white70),
                      suffixIcon: IconButton(
                        icon: Icon(isPasswordVisible ? Icons.visibility : Icons.visibility_off, color: Colors.white70),
                        onPressed: () => setState(() => isPasswordVisible = !isPasswordVisible),
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.1),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
                    ),
                    validator: (v) => v!.length < 6 ? "Password too short" : null,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: agreedToTerms,
                        onChanged: (value) {
                          setState(() {
                            agreedToTerms = value ?? false;
                          });
                        },
                        activeColor: const Color(0xFFFF8C00),
                        checkColor: Colors.white,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(color: Colors.white70, fontSize: 14),
                              children: [
                                const TextSpan(text: "I agree to the "),
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.baseline,
                                  baseline: TextBaseline.alphabetic,
                                  child: GestureDetector(
                                    onTap: () async {
                                      final url = Uri.parse('https://smartmobilityroadcare.com/privacy-policy/');
                                      if (await canLaunchUrl(url)) {
                                        await launchUrl(url, mode: LaunchMode.externalApplication);
                                      }
                                    },
                                    child: const Text("Privacy Policy", style: TextStyle(color: Color(0xFFFF8C00), decoration: TextDecoration.underline, fontSize: 14)),
                                  ),
                                ),
                                const TextSpan(text: " and "),
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.baseline,
                                  baseline: TextBaseline.alphabetic,
                                  child: GestureDetector(
                                    onTap: () async {
                                      final url = Uri.parse('https://smartmobilityroadcare.com/terms-of-service/');
                                      if (await canLaunchUrl(url)) {
                                        await launchUrl(url, mode: LaunchMode.externalApplication);
                                      }
                                    },
                                    child: const Text("Terms of Service", style: TextStyle(color: Color(0xFFFF8C00), decoration: TextDecoration.underline, fontSize: 14)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _register,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8C00),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        elevation: 0,
                      ),
                      child: isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text("CREATE ACCOUNT", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Already have an account? ",
                        style: TextStyle(color: Colors.white70),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          "Log In",
                          style: TextStyle(
                            color: Color(0xFFFF8C00),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, {TextInputType? keyboardType}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.1),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
      ),
      validator: (v) => v!.isEmpty ? "Required" : null,
    );
  }
}
