import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../screens/profile_screen.dart';
import '../screens/history_screen.dart';
import '../screens/referrals_screen.dart';
import '../screens/support_screen.dart';
import '../screens/login_screen.dart';

import '../screens/wallet_screen.dart';


class AppDrawer extends StatefulWidget {
  final Map<String, dynamic>? userData;
  
  const AppDrawer({super.key, this.userData});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  Map<String, dynamic>? userData;
  String? _profilePhotoUrl;

  @override
  void initState() {
    super.initState();
    // Read from cache synchronously first — no flicker
    userData = widget.userData ?? ApiService.cachedUserInfo;
    _profilePhotoUrl = ApiService.cachedProfilePhotoUrl;

    // Only hit the network if cache is empty
    if (userData == null) _loadUserData();
    if (_profilePhotoUrl == null) _loadProfilePhoto();
  }

  Future<void> _loadUserData() async {
    final data = await ApiService.fetchUserInfo();
    if (mounted) setState(() => userData = data);
  }

  Future<void> _loadProfilePhoto() async {
    final url = await ApiService.getProfilePhotoUrl();
    if (mounted && url != null) setState(() => _profilePhotoUrl = url);
  }

  @override
  Widget build(BuildContext context) {
    String displayName =
        userData?['first_name']?.toString().trim().isNotEmpty == true
        ? userData!['first_name']
        : (userData?['username'] ?? 'User');
    String email = userData?['email'] ?? '';
    String phone = userData?['phone'] ?? '';

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF10223D)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 35,
                  backgroundColor: Colors.white,
                  backgroundImage: _profilePhotoUrl != null
                      ? NetworkImage(_profilePhotoUrl!)
                      : const AssetImage('assets/smart_mobility_logo.png') as ImageProvider,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (phone.isNotEmpty)
                        Text(
                          phone,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person, color: Color(0xFF10223D)),
            title: const Text('My Profile'),
            onTap: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Assist History'),
            onTap: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(MaterialPageRoute(builder: (_) => const HistoryScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.group),
            title: const Text('Referrals'),
            onTap: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(MaterialPageRoute(builder: (_) => const ReferralsScreen()));
            },
          ),


          ListTile(
            leading: const Icon(Icons.account_balance_wallet, color: Color(0xFF10223D)),
            title: const Text('My Wallet'),
            onTap: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(MaterialPageRoute(builder: (_) => const WalletScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.support, color: Color(0xFF10223D)),
            title: const Text('Support'),
            onTap: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(MaterialPageRoute(builder: (_) => const SupportScreen()));
            },
          ),
          const SizedBox(height: 32),
          ListTile(
            leading: const Icon(Icons.exit_to_app),
            title: const Text('Logout'),
            onTap: () async {
              final ws = WebSocketService();
              ws.disconnect();
              final navigator = Navigator.of(context);
              navigator.pop();
              String? role = await ApiService.getRole();
              await ApiService.logout();
              if (!mounted) return;
              navigator.pushReplacement(
                MaterialPageRoute(
                  builder: (_) => LoginScreen(role: role ?? 'RIDER'),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Version 1.0',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }
}
