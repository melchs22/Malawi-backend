import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import '../services/api_service.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF10223D),
      ),
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How can we help you?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF10223D),
              ),
            ),
            SizedBox(height: 32),
            _SupportMenuItem(
              title: 'Contact Us',
              subtitle: 'Get in touch with our support team',
              icon: Icons.contact_support,
              screen: ContactUsScreen(),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ContactUsScreen()),
                );
              },
            ),
            const SizedBox(height: 16),
            _SupportMenuItem(
              title: 'Privacy Policy',
              subtitle: 'Learn about how we protect your data',
              icon: Icons.privacy_tip,
              onTap: () async {
                final url = Uri.parse('https://smartmobilityroadcare.com/privacy-policy/');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
            ),
            const SizedBox(height: 16),
            _SupportMenuItem(
              title: 'Terms & Conditions',
              subtitle: 'Read our terms of service',
              icon: Icons.description,
              onTap: () async {
                final url = Uri.parse('https://smartmobilityroadcare.com/terms-of-service/');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportMenuItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? screen;
  final VoidCallback onTap;

  const _SupportMenuItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.screen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF10223D), size: 28),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class ContactUsScreen extends StatelessWidget {
  const ContactUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact Us'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF10223D),
      ),
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Get in Touch',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF10223D),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'We\'re here to help! Reach out to us through any of the following channels:',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            _ContactCard(
              icon: Icons.email,
              title: 'Email',
              subtitle: 'support@smartmobilityroadcare.com',
              onTap: () async {
                final url = Uri.parse('mailto:support@smartmobilityroadcare.com');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                }
              },
            ),
            const SizedBox(height: 16),
            _ContactCard(
              icon: Icons.phone,
              title: 'Direct Phone',
              subtitle: '+256794812199',
              onTap: () async {
                final url = Uri.parse('tel:+256794812199');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                }
              },
            ),
            const SizedBox(height: 16),
            _ContactCard(
              icon: Icons.message,
              title: 'WhatsApp',
              subtitle: '+256706795451',
              onTap: () async {
                final url = Uri.parse('https://wa.me/256706795451');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
            ),
            const SizedBox(height: 16),
            _ContactCard(
              icon: Icons.star_rate,
              title: 'Rate Us',
              subtitle: 'Rate our app on the store',
              onTap: () async {
                final String urlString = Platform.isIOS 
                    ? 'https://apps.apple.com/app/id6772772972?action=write-review'
                    : 'https://play.google.com/store/apps/details?id=com.smartmobility.rider_app';
                final url = Uri.parse(urlString);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
            ),
            const SizedBox(height: 16),
            _ContactCard(
              icon: Icons.feedback,
              title: 'Give Feedback or Inquiries',
              subtitle: 'Send feedback/inquiries directly to support',
              onTap: () {
                _showFeedbackForm(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFeedbackForm(BuildContext context) {
    final TextEditingController feedbackController = TextEditingController();
    bool isSending = false;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Send Feedback/Inquiries'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Please share your feedback/inquiries with us'),
              const SizedBox(height: 16),
              TextField(
                controller: feedbackController,
                maxLines: 5,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter your Message here...',
                ),
                enabled: !isSending,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSending ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSending ? null : () async {
                final message = feedbackController.text.trim();
                if (message.isNotEmpty) {
                  setState(() => isSending = true);
                  
                  final success = await ApiService.submitFeedback(message);
                  
                  if (context.mounted) {
                    Navigator.pop(context);
                    if (success != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Got it! We'll reply within 24 hours."),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Failed to send feedback. Please try again later.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              child: isSending 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF10223D),
      ),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Privacy Policy',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF10223D),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Last updated: March 18, 2026',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            _buildSection('1. Information We Collect', [
              'Personal information (name, email, phone number)',
              'Location data for service matching',
              'Payment information',
              'Usage data and app analytics',
            ]),
            _buildSection('2. How We Use Your Information', [
              'To provide and improve our services',
              'To match you with service providers',
              'To process payments',
              'To communicate with you',
            ]),
            _buildSection('3. Information Sharing', [
              'We do not sell your personal information',
              'We share information with service providers only as necessary',
              'We may share data with law enforcement when required',
            ]),
            _buildSection('4. Data Security', [
              'We implement industry-standard security measures',
              'Your data is encrypted in transit and at rest',
              'We regularly review our security practices',
            ]),
            _buildSection('5. Your Rights', [
              'You can access your data',
              'You can request deletion of your data',
              'You can opt-out of marketing communications',
            ]),
            _buildSection('6. Contact Us', [
              'If you have questions about this Privacy Policy, contact us at support@smartmobilityroadcare.com',
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<String> points) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF10223D),
          ),
        ),
        const SizedBox(height: 8),
        ...points.map((point) => Padding(
          padding: const EdgeInsets.only(left: 16.0, bottom: 4.0),
          child: Text('• $point', style: const TextStyle(fontSize: 14)),
        )),
        const SizedBox(height: 16),
      ],
    );
  }
}

class TermsConditionsScreen extends StatelessWidget {
  const TermsConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms & Conditions'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF10223D),
      ),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Terms & Conditions',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF10223D),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Last updated: March 18, 2026',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            _buildSection('1. Acceptance of Terms', [
              'By using SRS, you agree to these Terms & Conditions.',
            ]),
            _buildSection('2. Service Description', [
              'SRS is a platform connecting drivers with mechanics.',
            ]),
            _buildSection('3. User Responsibilities', [
              'Provide accurate information',
              'Use the service responsibly',
              'Respect other users and service providers',
              'Pay for services rendered',
            ]),
            _buildSection('4. Service Provider Responsibilities', [
              'Provide professional services',
              'Maintain accurate availability status',
              'Communicate promptly with customers',
            ]),
            _buildSection('5. Payment Terms', [
              'Payment is processed through the app',
              'Refunds are subject to our refund policy',
              'Service fees are clearly displayed',
            ]),
            _buildSection('6. Prohibited Activities', [
              'Using the service for illegal activities',
              'Harassment or abuse of other users',
              'Fraudulent behavior',
              'Violating local laws',
            ]),
            _buildSection('7. Limitation of Liability', [
              'SRS is a platform, not a direct service provider',
              'We are not liable for the actions of independent service providers',
              'Our liability is limited as described in these terms',
            ]),
            _buildSection('8. Dispute Resolution', [
              'Contact support for issues',
              'We will attempt to mediate disputes',
              'Legal disputes are governed by applicable laws',
            ]),
            _buildSection('9. Account Termination', [
              'We reserve the right to terminate accounts for violations',
              'You can terminate your account at any time',
            ]),
            _buildSection('10. Changes to Terms', [
              'We may update these terms periodically',
              'Continued use indicates acceptance of changes',
            ]),
            _buildSection('Contact Us', [
              'Contact us at support@smartmobilityroadcare.com for questions about these terms.',
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<String> points) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF10223D),
          ),
        ),
        const SizedBox(height: 8),
        ...points.map((point) => Padding(
          padding: const EdgeInsets.only(left: 16.0, bottom: 4.0),
          child: Text('• $point', style: const TextStyle(fontSize: 14)),
        )),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _ContactCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _ContactCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF10223D)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: onTap != null ? const Icon(Icons.chevron_right) : null,
        onTap: onTap,
        enabled: onTap != null,
      ),
    );
  }
}
