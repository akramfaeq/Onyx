import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/singbox_provider.dart';
import '../models/vpn_mode.dart';
import '../services/ads_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08080F),
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  const _TopBar(),
                  Expanded(child: _Body()),
                ],
              ),
            ),
          ),
          const BannerAdWidget(),
        ],
      ),
    );
  }
}

// ─── Top Bar ──────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          RichText(
            text: const TextSpan(children: [
              TextSpan(
                text: 'Onyx',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.8),
              ),
              TextSpan(
                text: 'VPN',
                style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.8),
              ),
            ]),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/info'),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF111120),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E1E35)),
              ),
              child: const Icon(Icons.info_outline_rounded, color: Color(0xFF6D28D9), size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────
class _Body extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<SingboxProvider>(
      builder: (_, vpn, __) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            _OrbSection(vpn: vpn),
            const SizedBox(height: 20),
            _StatsRow(vpn: vpn),
            const SizedBox(height: 20),
            _Divider(),
            const SizedBox(height: 16),
            const _ModeLabel(),
            const SizedBox(height: 12),
            _ModeGrid(vpn: vpn),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ─── Orb Section ──────────────────────────────────────────────
class _OrbSection extends StatefulWidget {
  final SingboxProvider vpn;
  const _OrbSection({required this.vpn});

  @override
  State<_OrbSection> createState() => _OrbSectionState();
}

class _OrbSectionState extends State<_OrbSection> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulse = Tween(begin: 1.0, end: 1.06)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final vpn = widget.vpn;
    final connected  = vpn.isConnected;
    final connecting = vpn.isConnecting;

    final color = vpn.isFailed
        ? const Color(0xFFEF4444)
        : connecting
            ? const Color(0xFFF59E0B)
            : connected
                ? const Color(0xFF10B981)
                : const Color(0xFF8B5CF6);

    final label = connected
        ? 'TAP TO\nDISCONNECT'
        : connecting
            ? 'CONNECTING'
            : 'CONNECT';

    return Column(
      children: [
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Transform.scale(
            scale: connected || connecting ? _pulse.value : 1.0,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                vpn.connect();
              },
              child: SizedBox(
                width: 172, height: 172,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Glow ring
                    if (connected || connecting)
                      Container(
                        width: 172, height: 172,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: color.withOpacity(0.1), width: 18),
                        ),
                      ),
                    // Ring 1
                    Container(
                      width: 148, height: 148,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withOpacity(0.18), width: 1),
                      ),
                    ),
                    // Ring 2
                    Container(
                      width: 124, height: 124,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withOpacity(0.28), width: 1),
                      ),
                    ),
                    // Progress ring
                    if (connecting)
                      SizedBox(
                        width: 124, height: 124,
                        child: CircularProgressIndicator(color: color, strokeWidth: 1.5),
                      ),
                    // Core
                    Container(
                      width: 100, height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF0D0D1F),
                        border: Border.all(color: color.withOpacity(0.35), width: 1),
                        boxShadow: [
                          BoxShadow(color: color.withOpacity(connected ? 0.3 : 0.15), blurRadius: 28, spreadRadius: 1),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.power_settings_new_rounded, color: color, size: 32),
                          const SizedBox(height: 5),
                          Text(
                            label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: color.withOpacity(0.8),
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        // Status pill
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF111120),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: connected
                  ? const Color(0xFF10B981).withOpacity(0.35)
                  : const Color(0xFF1E1E35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected
                      ? const Color(0xFF10B981)
                      : connecting
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF374151),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                connected
                    ? 'Connected · ${vpn.formattedTime}'
                    : vpn.isFailed
                        ? vpn.status
                        : connecting
                            ? vpn.status
                            : 'Not connected',
                style: TextStyle(
                  color: connected
                      ? const Color(0xFF10B981)
                      : const Color(0xFF6B7280),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Stats Row ────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final SingboxProvider vpn;
  const _StatsRow({required this.vpn});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _StatCard(
            icon: Icons.arrow_downward_rounded,
            label: 'DOWN',
            value: vpn.isConnected ? vpn.downSpeed : '--',
            color: const Color(0xFF10B981),
          ),
          const SizedBox(width: 8),
          _StatCard(
            icon: Icons.arrow_upward_rounded,
            label: 'UP',
            value: vpn.isConnected ? vpn.upSpeed : '--',
            color: const Color(0xFF8B5CF6),
          ),
          const SizedBox(width: 8),
          _StatCard(
            icon: Icons.timer_rounded,
            label: 'TIME',
            value: vpn.isConnected ? vpn.formattedTime : '--:--',
            color: const Color(0xFF3B82F6),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E1C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1A1A2E)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 11, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: Color(0xFF374151), fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        ],
      ),
    ),
  );
}

// ─── Divider ──────────────────────────────────────────────────
class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 20),
    height: 1,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.transparent, Color(0xFF1E1E35), Colors.transparent],
      ),
    ),
  );
}

class _ModeLabel extends StatelessWidget {
  const _ModeLabel();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 22),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'SELECT MODE',
        style: TextStyle(color: Color(0xFF374151), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
      ),
    ),
  );
}

// ─── Mode Grid - الـ 4 خيارات ─────────────────────────────────
class _ModeGrid extends StatelessWidget {
  final SingboxProvider vpn;
  const _ModeGrid({required this.vpn});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _ModeCard(info: VpnModeInfo.warp,    vpn: vpn, iconBg: const Color(0xFF1A1200), tagColor: const Color(0xFFF97316)),
          _ModeCard(info: VpnModeInfo.psiphon, vpn: vpn, iconBg: const Color(0xFF001428), tagColor: const Color(0xFF60A5FA)),
          _ModeCard(info: VpnModeInfo.mahsa,   vpn: vpn, iconBg: const Color(0xFF1A0028), tagColor: const Color(0xFFF472B6)),
          _AddCard(vpn: vpn),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final VpnModeInfo info;
  final SingboxProvider vpn;
  final Color iconBg;
  final Color tagColor;
  const _ModeCard({required this.info, required this.vpn, required this.iconBg, required this.tagColor});

  @override
  Widget build(BuildContext context) {
    final selected = vpn.mode == info.mode;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        vpn.selectMode(info.mode);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF11112A) : const Color(0xFF0E0E1C),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF8B5CF6).withOpacity(0.45) : const Color(0xFF1A1A2E),
            width: 1.5,
          ),
          boxShadow: selected
              ? [BoxShadow(color: const Color(0xFF8B5CF6).withOpacity(0.08), blurRadius: 20)]
              : [],
        ),
        child: Stack(
          children: [
            // Top accent line
            if (selected)
              Positioned(
                top: -14, left: -14, right: -14,
                child: Container(
                  height: 2,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Color(0xFF8B5CF6), Colors.transparent],
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                ),
              ),
            // Tag
            if (info.tag.isNotEmpty)
              Positioned(
                top: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: tagColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: tagColor.withOpacity(0.25)),
                  ),
                  child: Text(info.tag, style: TextStyle(color: tagColor, fontSize: 9, fontWeight: FontWeight.w700)),
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
                  child: Center(child: Text(info.emoji, style: const TextStyle(fontSize: 20))),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.name, style: const TextStyle(color: Color(0xFFE5E7EB), fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(info.subtitle, style: const TextStyle(color: Color(0xFF4B5563), fontSize: 10, fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Add Card ─────────────────────────────────────────────────
class _AddCard extends StatelessWidget {
  final SingboxProvider vpn;
  const _AddCard({required this.vpn});

  @override
  Widget build(BuildContext context) {
    final hasUrl = vpn.customUrl != null && vpn.customUrl!.isNotEmpty;
    final selected = vpn.mode == VpnMode.custom;

    return GestureDetector(
      onTap: () => _showAddDialog(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF11112A) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFF8B5CF6).withOpacity(0.45)
                : const Color(0xFF1E1E35),
            width: selected ? 1.5 : 1.5,
            style: selected ? BorderStyle.solid : BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withOpacity(0.08),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.35)),
              ),
              child: const Icon(Icons.add_rounded, color: Color(0xFF8B5CF6), size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              hasUrl ? 'Custom' : 'Add Link',
              style: const TextStyle(color: Color(0xFF6D28D9), fontSize: 12, fontWeight: FontWeight.w700),
            ),
            Text(
              hasUrl ? 'Tap to change' : 'Subscription URL',
              style: const TextStyle(color: Color(0xFF374151), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final vpn = context.read<SingboxProvider>();
    final ctrl = TextEditingController(text: vpn.customUrl ?? '');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111120),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Add Subscription', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Paste your subscription URL or v2ray link:', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'https://example.com/sub.txt',
                hintStyle: const TextStyle(color: Color(0xFF374151)),
                filled: true,
                fillColor: const Color(0xFF0E0E1C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1E1E35)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1E1E35)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF8B5CF6)),
                ),
              ),
              maxLines: 3,
              minLines: 1,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                vpn.setCustomUrl(ctrl.text.trim());
                vpn.selectMode(VpnMode.custom);
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
