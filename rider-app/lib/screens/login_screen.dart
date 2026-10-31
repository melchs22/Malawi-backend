import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'home_screen.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import '../services/notification_service.dart';

class LoginScreen extends StatefulWidget {
  final String role;
  final String? message;
  const LoginScreen({required this.role, this.message, super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false;
  bool isPasswordVisible = false;
  final WebSocketService ws = WebSocketService();

  @override
  void initState() {
    super.initState();
    if (widget.message != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.message!),
            backgroundColor: const Color(0xFF10223D),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      });
    }
  }

  void login() async {
    if (usernameController.text.isEmpty || passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all fields")),
      );
      return;
    }

    setState(() => isLoading = true);

    final success = await ApiService.login(
      usernameController.text,
      passwordController.text,
      widget.role,
    );

    if (success && mounted) {
      // Pre-load services for faster home screen experience
      if (widget.role == "RIDER") {
        await ApiService.preloadServices();
        // Register FCM token now that we are logged in
        await NotificationService().refreshRegistration();
      }
      
      setState(() => isLoading = false);
      
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen(role: widget.role, ws: ws)),
        (route) => false,
      );
    } else if (mounted) {
      setState(() => isLoading = false);
      
      // Show more detailed error message
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Center(child: Text("Log In Failed", style: TextStyle(fontWeight: FontWeight.bold))),
          content: const Text(
            "Unable to log in. Please ensure:\n"
            "- Username, email, phone number, and password are correct\n"
            "- You are logging into the correct user role (Driver or Mechanic)",
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
      backgroundColor: Colors.white,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.white,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              children: [
                const SizedBox(height: 60),
                Hero(
                  tag: 'app_logo',
                  child: Image.asset(
                    'assets/smart_mobility_logo.png',
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 40),
                const Text(
                  "Stranded on the road? Get help in minutes.",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF10223D),
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  "Find reliable emergency roadside assistance near you and get moving again.",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF10223D),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                Text(
                  widget.role == "RODIE" ? "Welcome Mechanic" : "Welcome Driver",
                  style: TextStyle(
                    color: Color(0xFF10223D),
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 60),
                _buildInputField(
                  controller: usernameController,
                  hint: "Username, Email, or Phone",
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 20),
                _buildInputField(
                  controller: passwordController,
                  hint: "Password",
                  icon: Icons.lock_outline,
                  isPassword: true,
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8C00),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                      shadowColor: const Color(
                        0xFFFF8C00,
                      ).withValues(alpha: 0.4),
                    ),
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            "LOG IN",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ForgotPasswordScreen(role: widget.role),
                        ),
                      );
                    },
                    child: const Text(
                      "Forgot Password?",
                      style: TextStyle(
                        color: Color(0xFFFF8C00),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Don't have an account? ",
                      style: TextStyle(color: Color(0xFF10223D)),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RegisterScreen(role: widget.role),
                          ),
                        );
                      },
                      child: const Text(
                        "Sign Up",
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
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword && !isPasswordVisible,
        style: const TextStyle(color: Color(0xFF10223D)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.7)),
          prefixIcon: Icon(icon, color: Colors.grey.withValues(alpha: 0.7)),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                    color: Colors.grey.withValues(alpha: 0.7),
                  ),
                  onPressed: () =>
                      setState(() => isPasswordVisible = !isPasswordVisible),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}
