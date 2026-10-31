import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  // Controllers
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final ninController = TextEditingController();

  // Form key for validation
  final _formKey = GlobalKey<FormState>();

  bool loading = false;
  bool obscurePassword = true;

  @override
  void dispose() {
    // Dispose controllers to prevent memory leaks
    firstNameController.dispose();
    lastNameController.dispose();
    usernameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    ninController.dispose();
    super.dispose();
  }

  Future<void> signup() async {
    // Validate form
    if (!_formKey.currentState!.validate()) return;

    setState(() => loading = true);

    final payload = {
      "first_name": firstNameController.text.trim(),
      "last_name": lastNameController.text.trim(),
      "username": usernameController.text.trim(),
      "email": emailController.text.trim(),
      "phone": phoneController.text.trim(),
      "password": passwordController.text,
      "role": "RODIE",
      "nin": ninController.text.trim(),
    };

    // print removed

    try {
      final response = await ApiService.post(
        "/register/",
        payload,
        requiresAuth: false,
      );

      // print removed

      // Check if response has an error field
      if (response is Map && response.containsKey('error')) {
        throw Exception(response['error']);
      }

      // Check for success (adjust based on your API response structure)
      if (response["id"] != null ||
          response["user"] != null ||
          response["success"] == true) {
        _showSnackBar("Registration successful! Please log in.", isError: false);

        // Navigate to login screen after short delay
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const LoginScreen(role: "RODIE"),
              ),
            );
          }
        });
      } else {
        // Show specific error from API if available
        String errorMsg =
            response["detail"] ??
            response["message"] ??
            response["error"] ??
            "Registration failed";
        _showSnackBar(errorMsg);
      }
    } catch (e) {
      // print removed
      _showSnackBar("Error: ${e.toString().replaceAll('Exception:', '')}");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF10223D),
        foregroundColor: Colors.white,
        title: const Text("Mechanic Signup"),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),

                // First Name
                TextFormField(
                  controller: firstNameController,
                  decoration: InputDecoration(
                    labelText: "First Name",
                    prefixIcon: const Icon(
                      Icons.person_outline,
                      color: Color(0xFF10223D),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFFFF8C00),
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "First name is required";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 15),

                // Last Name
                TextFormField(
                  controller: lastNameController,
                  decoration: InputDecoration(
                    labelText: "Last Name",
                    prefixIcon: const Icon(
                      Icons.person_outline,
                      color: Color(0xFF10223D),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFFFF8C00),
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "Last name is required";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 15),

                // Username
                TextFormField(
                  controller: usernameController,
                  decoration: InputDecoration(
                    labelText: "Username",
                    prefixIcon: const Icon(
                      Icons.badge_outlined,
                      color: Color(0xFF10223D),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFFFF8C00),
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "Username is required";
                    }
                    if (value.length < 3) {
                      return "Username must be at least 3 characters";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 15),

                // Email
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: "Email",
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: Color(0xFF10223D),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFFFF8C00),
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "Email is required";
                    }
                    if (!RegExp(
                      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                    ).hasMatch(value)) {
                      return "Enter a valid email";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 15),

                // Phone
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: "Phone",
                    prefixIcon: const Icon(
                      Icons.phone_outlined,
                      color: Color(0xFF10223D),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFFFF8C00),
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "Phone number is required";
                    }
                    if (value.length < 10) {
                      return "Enter a valid phone number";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 15),

                // Password
                TextFormField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    labelText: "Password",
                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      color: Color(0xFF10223D),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: const Color(0xFF10223D),
                      ),
                      onPressed: () {
                        setState(() => obscurePassword = !obscurePassword);
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFFFF8C00),
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Password is required";
                    }
                    if (value.length < 6) {
                      return "Password must be at least 6 characters";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 15),

                // NIN
                TextFormField(
                  controller: ninController,
                  decoration: InputDecoration(
                    labelText: "NIN (National ID)",
                    prefixIcon: const Icon(
                      Icons.credit_card_outlined,
                      color: Color(0xFF10223D),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFFFF8C00),
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "NIN is required";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 30),

                // Signup Button
                loading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: signup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8C00),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          "Sign Up",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                const SizedBox(height: 15),

                // Login link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Already have an account? "),
                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(role: "RODIE"),
                          ),
                        );
                      },
                      child: const Text("Log In"),
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
}
