import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
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
      nin: widget.role == 'RIDER' ? null : ninController.text,
      referredByCode: referralController.text.trim().isEmpty ? null : referralController.text.trim(),
    );

    setState(() => isLoading = false);

    if (result == true && mounted) {
      // Register FCM token now that we are registered and logged in
      await NotificationService().refreshRegistration();

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen(role: widget.role)),
        (route) => false,
      );
    } else if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Center(child: Text("Registration Failed", style: TextStyle(fontWeight: FontWeight.bold))),
          content: const Text(
            "Please check if the following details have already been used:\n"
            "• Username\n"
            "• Phone Number\n"
            "• Email Address",
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          // Exit the app instead of going back to login
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF10223D)),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const Text(
                    "Welcome to SRS",
                    style: TextStyle(
                      color: Color(0xFF10223D),
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Let's get you started",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.role == 'RIDER' ? "Create your driver account" : "Create your mechanic account",
                    style: const TextStyle(
                      color: Color(0xFF10223D),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 40),
                  _buildInputField(
                    usernameController,
                    "Username",
                    Icons.person_outline,
                  ),
                  const SizedBox(height: 16),
                  _buildInputField(
                    firstNameController,
                    "First Name",
                    Icons.person_outline,
                  ),
                  const SizedBox(height: 16),
                  _buildInputField(
                    lastNameController,
                    "Last Name",
                    Icons.person_outline,
                  ),
                  const SizedBox(height: 16),
                  _buildInputField(
                    emailController,
                    "Email",
                    Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  _buildInputField(
                    phoneController,
                    "Phone Number",
                    Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  if (widget.role != 'RIDER') ...[
                    const SizedBox(height: 16),
                    _buildInputField(
                      ninController,
                      "NIN (Required for Mechanics)",
                      Icons.credit_card,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildPasswordField(),
                  const SizedBox(height: 16),
                  _buildReferralField(),
                  const SizedBox(height: 24),
                  // Terms and Conditions Checkbox
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
                          child: GestureDetector(
                            onTap: () {
                              // Handle tap on the entire text area if needed
                            },
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(color: Colors.grey, fontSize: 14),
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
                                        child: const Text(
                                          "Privacy Policy",
                                          style: TextStyle(
                                            color: Color(0xFF10223D),
                                            decoration: TextDecoration.underline,
                                            fontSize: 14,
                                          ),
                                        ),
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
                                        child: const Text(
                                          "Terms of Service",
                                          style: TextStyle(
                                            color: Color(0xFF10223D),
                                            decoration: TextDecoration.underline,
                                            fontSize: 14,
                                          ),
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
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _register,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8C00),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              "Create Account",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Already have an account? ",
                        style: TextStyle(color: Colors.grey),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          "Log In",
                          style: TextStyle(
                            color: Color(0xFF10223D),
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

  Widget _buildInputField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(color: Color(0xFF10223D)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5)),
          prefixIcon: Icon(icon, color: Colors.grey.withValues(alpha: 0.5)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
        validator: (v) => v!.isEmpty ? "Required" : null,
      ),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: TextFormField(
        controller: passwordController,
        obscureText: !isPasswordVisible,
        style: const TextStyle(color: Color(0xFF10223D)),
        decoration: InputDecoration(
          hintText: "Password",
          hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5)),
          prefixIcon: Icon(
            Icons.lock_outline,
            color: Colors.grey.withValues(alpha: 0.5),
          ),
          suffixIcon: IconButton(
            icon: Icon(
              isPasswordVisible ? Icons.visibility : Icons.visibility_off,
              color: Colors.grey.withValues(alpha: 0.5),
            ),
            onPressed: () =>
                setState(() => isPasswordVisible = !isPasswordVisible),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
        validator: (v) => v!.length < 6 ? "Password too short" : null,
      ),
    );
  }

  Widget _buildReferralField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: TextFormField(
        controller: referralController,
        style: const TextStyle(color: Color(0xFF10223D)),
        decoration: InputDecoration(
          hintText: "Referral Code (Optional)",
          hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5)),
          prefixIcon: Icon(
            Icons.card_giftcard_outlined,
            color: Colors.grey.withValues(alpha: 0.5),
          ),
          suffixIcon: IconButton(
            icon: Icon(
              Icons.info_outline,
              color: Colors.grey.withValues(alpha: 0.5),
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Referral Code"),
                  content: const Text(
                    "Enter a referral code to get a welcome bonus!\n\n"
                    "If someone invited you to join SRS, ask them for their referral code.",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Got it"),
                    ),
                  ],
                ),
              );
            },
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
        // No validation - referral code is optional
      ),
    );
  }
}
