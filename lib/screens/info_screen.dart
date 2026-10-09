import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  static const _privacyUrl = 'https://akram-app.github.io/onyxvpn-privacy/';

  Future<void> _openPrivacy() async {
    final uri = Uri.parse(_privacyUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A14),
        title: const Text('About',
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
                    Text('Version 2.0.0',
                        style: TextStyle(
                            color: Color(0xFF6B7280), fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Developer
          const _SectionTitle('Developer'),
          const _Card(
            child: Row(
              children: [
                Icon(Icons.person_rounded, color: Color(0xFF7B5CF0), size: 20),
                SizedBox(width: 12),
                Text('Akram',
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Contact
          const _SectionTitle('Contact'),
          const _Card(
            child: Row(
              children: [
                Icon(Icons.email_rounded,
                    color: Color(0xFF7B5CF0), size: 20),
                SizedBox(width: 12),
                Text('onyxvpn.dev@gmail.com',
                    style:
                        TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Privacy Policy button
          const _SectionTitle('Legal'),
          _Card(
            child: InkWell(
              onTap: _openPrivacy,
              borderRadius: BorderRadius.circular(12),
              child: const Row(
                children: [
                  Icon(Icons.privacy_tip_rounded,
                      color: Color(0xFF7B5CF0), size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Privacy Policy',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded,
                      color: Color(0xFF4B5563), size: 14),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          const Center(
            child: Text(
              '© 2025 OnyxVPN · All rights reserved',
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