import 'package:flutter/material.dart';

class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A14),
        title: const Text('About & Privacy',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // App info card
          _Card(
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B5CF0).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.shield_rounded,
                      color: Color(0xFF7B5CF0), size: 28),
                ),
                const SizedBox(width: 16),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('OnyxVPN',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    Text('Version 1.0.0',
                        style: TextStyle(
                            color: Color(0xFF6B7280), fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _SectionTitle('Privacy Policy'),
          _Card(
            child: const Text(
              'OnyxVPN is committed to protecting your privacy.\n\n'
              '• We do not log your browsing activity, DNS queries, IP addresses, or connection timestamps.\n\n'
              '• We do not sell, rent, or share your personal data with third parties.\n\n'
              '• VPN servers are provided by VPNGate, a public VPN relay service operated by the University of Tsukuba, Japan.\n\n'
              '• Ads are served by Unity Ads. Their privacy policy applies to ad interactions.\n\n'
              '• We use Supabase to cache server lists only — no personal data is stored.\n\n'
              '• The app does not require account registration or any personal information.',
              style: TextStyle(
                  color: Color(0xFF9CA3AF), fontSize: 13, height: 1.6),
            ),
          ),
          const SizedBox(height: 16),

          _SectionTitle('Terms of Use'),
          _Card(
            child: const Text(
              '• OnyxVPN is provided for legitimate privacy and security purposes only.\n\n'
              '• You agree not to use this app for any illegal activities.\n\n'
              '• VPN speeds depend on the public relay servers and your internet connection. We do not guarantee specific speeds.\n\n'
              '• The service is provided "as is" without warranty of any kind.',
              style: TextStyle(
                  color: Color(0xFF9CA3AF), fontSize: 13, height: 1.6),
            ),
          ),
          const SizedBox(height: 32),

          const Center(
            child: Text(
              'all rights reserved onyxVPN 2025.',
              style: TextStyle(color: Color(0xFF4B5563), fontSize: 12),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF6B7280),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12121E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}
