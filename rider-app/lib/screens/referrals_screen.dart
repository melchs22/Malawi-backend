import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';

class ReferralsScreen extends StatefulWidget {
  const ReferralsScreen({super.key});

  @override
  State<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends State<ReferralsScreen> {
  List<dynamic> referrals = [];
  String referralCode = "";
  bool isLoading = true;
  double totalEarnings = 0.0;
  int totalReferrals = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = await ApiService.fetchUserInfo();
    final data = await ApiService.getReferrals();
    
    // Calculate earnings (only paid ones)
    double earnings = 0.0;
    for (var referral in data) {
      if (referral["is_credited"] == true) {
        earnings += double.tryParse(referral["amount"].toString()) ?? 0.0;
      }
    }
    
    if (mounted) {
      setState(() {
        referralCode = (user != null ? user["referral_code"] : null) ?? "SRS2024";
        referrals = data;
        totalEarnings = earnings;
        totalReferrals = data.length;
        isLoading = false;
      });
    }
  }

  void _shareNative() async {
    String baseUrl = "https://smartmobilityroadcare.com";
    String message = "🚀 *Invite Drivers and Mechanics & Earn UGX 1,000!*\n\n"
                     "Use my referral code: *$referralCode*\n\n"
                     "Download now: $baseUrl\n"
                     "Share your code and earn UGX 1,000 when new drivers or mechanics complete their first Job/Assist!";
    
    await Share.share(message, subject: 'Join SRS Platform');
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: referralCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text("Code copied: $referralCode"),
          ],
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Referrals'),
        backgroundColor: const Color(0xFF10223D),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        color: Colors.white,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stats Cards
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            "Total Referrals",
                            totalReferrals.toString(),
                            Icons.people_outline,
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            "Total Earned",
                            "UGX ${totalEarnings.toInt()}",
                            Icons.payments_outlined,
                            Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Referral Card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF10223D), Color(0xFF1D3B63)],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10223D).withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.card_giftcard,
                            color: Color(0xFFFF8C00),
                            size: 60,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            "Invite Drivers and Mechanics & Earn",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "Share your code and earn UGX 1,000 when new drivers or mechanics complete their first Job/Assist!",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  referralCode,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.copy,
                                    color: Colors.white,
                                  ),
                                  onPressed: _copyCode,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          
                          // Share Button
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed: _shareNative,
                              icon: const Icon(Icons.share, color: Colors.white),
                              label: const Text(
                                "SHARE MY CODE",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF8C00),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // const SizedBox(height: 40),
                    
                    // How it works (Removed)
                    // _buildHowItWorks(),
                    const SizedBox(height: 10),
                    
                    // Referrals List
                    const Text(
                      "Your Referrals",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10223D),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (referrals.isEmpty)
                      _buildEmptyState()
                    else
                      _buildReferralsList(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
                          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShareButton(IconData icon, String label, Color color, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          children: [
            Icon(
              Icons.people_outline,
              size: 80,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            const Text(
              "No referrals yet.\nStart sharing to earn rewards!",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferralsList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: referrals.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final ref = referrals[index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF10223D),
                child: Text(
                  (ref["referred_user"]["username"]??"")[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ref["referred_user"]["username"]??"Unknown",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      "Joined: ${ref["created_at"].toString().split('T')[0]}",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "UGX ${ref["amount"]}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFFFF8C00),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: ref["is_credited"] == true ? Colors.green.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      ref["is_credited"] == true ? "Earned" : "Pending",
                      style: TextStyle(
                        color: ref["is_credited"] == true ? Colors.green.shade700 : Colors.orange.shade700,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
