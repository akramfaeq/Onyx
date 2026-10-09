import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/singbox_provider.dart';
import '../services/geo_service.dart';
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
    final geoCode = GeoService.userCountryCode;
    final geoName = GeoService.userCountryName;
    final geoFlag = geoCode.isNotEmpty ? _codeToFlag(geoCode) : '🌐';
    final isRestrict = GeoService.isRestrictedCountry;
    final isPartial  = GeoService.isPartialCountry;

    final badgeColor = isRestrict
        ? const Color(0xFFEF4444)
        : isPartial
            ? const Color(0xFFF59E0B)
            : const Color(0xFF1E1E35);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          // ── اسم التطبيق ──────────────────────────────────
          RichText(
            text: const TextSpan(children: [
              TextSpan(
                text: 'Onyx',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
              ),
              TextSpan(
                text: ' VPN',
                style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
              ),
            ]),
          ),
          const Spacer(),
          // ── علم الدولة ───────────────────────────────────
          if (geoCode.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF111120),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: badgeColor.withValues(alpha: isRestrict || isPartial ? 0.4 : 1.0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(geoFlag, style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 6),
                  Text(
                    geoName.isNotEmpty ? geoName : geoCode,
                    style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          // ── زر المعلومات ─────────────────────────────────
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
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        child: Column(
          children: [
            _OrbSection(vpn: vpn),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text(
                    'CONNECTION OPTIONS',
                    style: TextStyle(color: Color(0xFF8B909B), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1),
                  ),
                  const Spacer(),
                  if (vpn.isConnected)
                    const Text('SECURE CONNECTION', style: TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.7)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _ConnectionCards(vpn: vpn),
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
    final vpn        = widget.vpn;
    final connected  = vpn.isConnected;
    final connecting = vpn.isConnecting;

    final color = vpn.isFailed
        ? const Color(0xFFEF4444)
        : connecting
            ? const Color(0xFFF59E0B)
            : connected
                ? const Color(0xFF10B981)
                : const Color(0xFF8B5CF6);

    final label = connected ? 'TAP TO\nDISCONNECT'
        : connecting ? 'CONNECTING'
        : 'TAP TO\nCONNECT';

    return Column(
      children: [
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Transform.scale(
            scale: connected || connecting ? _pulse.value : 1.0,
            child: GestureDetector(
              onTap: () { HapticFeedback.lightImpact(); vpn.connect(); },
              child: SizedBox(
                width: 180, height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer glow
                    if (connected || connecting)
                      Container(
                        width: 180, height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: color.withValues(alpha: 0.08), width: 20),
                        ),
                      ),
                    // Ring 1
                    Container(
                      width: 152, height: 152,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withValues(alpha: 0.15), width: 1),
                      ),
                    ),
                    // Ring 2
                    Container(
                      width: 126, height: 126,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
                      ),
                    ),
                    // Progress
                    if (connecting)
                      SizedBox(
                        width: 126, height: 126,
                        child: CircularProgressIndicator(color: color, strokeWidth: 1.5),
                      ),
                    // Core
                    Container(
                      width: 104, height: 104,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF0D0D1F),
                        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
                        boxShadow: [
                          BoxShadow(color: color.withValues(alpha: connected ? 0.35 : 0.15), blurRadius: 32, spreadRadius: 2),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.power_settings_new_rounded, color: color, size: 34),
                          const SizedBox(height: 5),
                          Text(
                            label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: color.withValues(alpha: 0.85),
                              fontSize: 7.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              height: 1.5,
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
        const SizedBox(height: 16),
        // Status pill
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF111120),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: connected
                  ? const Color(0xFF10B981).withValues(alpha: 0.3)
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
                connected ? 'Connected · ${vpn.formattedTime}'
                    : vpn.isFailed ? vpn.status
                    : connecting ? vpn.status
                    : 'Not connected',
                style: TextStyle(
                  color: connected ? const Color(0xFF10B981) : const Color(0xFF6B7280),
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



class _ConnectionCards extends StatelessWidget {
  final SingboxProvider vpn;
  const _ConnectionCards({required this.vpn});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _ConnectionCard(
            icon: Icons.shield_moon_rounded,
            title: 'WARP+ PSIPHON',
            subtitle: 'Extra access with Cloudflare speed',
            color: const Color(0xFFF97316),
            active: vpn.mode == VpnMode.warpPsiphon,
            busy: vpn.isConnecting && vpn.mode == VpnMode.warpPsiphon,
            onTap: () {
              HapticFeedback.selectionClick();
              if (vpn.isConnected && vpn.mode == VpnMode.warpPsiphon) {
                vpn.disconnect();
              } else {
                vpn.connectWithMode(VpnMode.warpPsiphon);
              }
            },
          ),
          const SizedBox(height: 10),
          _ConnectionCard(
            icon: Icons.bolt_rounded,
            title: 'MAHSA SERVERS',
            subtitle: 'Automatically connects to the fastest server',
            color: const Color(0xFFF472B6),
            active: vpn.mode == VpnMode.mahsa,
            busy: vpn.isConnecting && vpn.mode == VpnMode.mahsa,
            onTap: () {
              HapticFeedback.selectionClick();
              if (vpn.isConnected && vpn.mode == VpnMode.mahsa) {
                vpn.disconnect();
              } else {
                vpn.connectWithMode(VpnMode.mahsa);
              }
            },
          ),
          const SizedBox(height: 10),
          _PythonServersCard(vpn: vpn),
          const SizedBox(height: 10),
          _ConnectionCard(
            icon: Icons.add_link_rounded,
            title: 'CUSTOM LINK',
            subtitle: vpn.customUrl == null || vpn.customUrl!.isEmpty ? 'Add a subscription and choose a server' : 'Choose from your subscription servers',
            color: const Color(0xFF34D399),
            active: vpn.mode == VpnMode.custom,
            onTap: () => _openCustomFlow(context, vpn),
          ),
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool active;
  final bool busy;
  final VoidCallback onTap;

  const _ConnectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.active,
    this.busy = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.09) : const Color(0xFF10111A),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: active ? color.withValues(alpha: 0.48) : const Color(0xFF20212D)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Color(0xFFF3F4F6), fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.35)),
                    const SizedBox(height: 4),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF777B89), fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (busy)
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: color, strokeWidth: 2))
              else if (active)
                Icon(Icons.check_circle_rounded, color: color, size: 19)
              else
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF555967), size: 21),
            ],
          ),
        ),
      ),
    );
  }
}

class _PythonServersCard extends StatelessWidget {
  final SingboxProvider vpn;
  const _PythonServersCard({required this.vpn});

  @override
  Widget build(BuildContext context) {
    final choices = _countryChoices(vpn.onyxServers);
    final active = vpn.mode == VpnMode.pythonServers;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        if (vpn.isConnected && vpn.mode == VpnMode.pythonServers) {
          vpn.disconnect();
        } else {
          vpn.connectWithMode(VpnMode.pythonServers);
        }
      },
      child: Container(
      decoration: BoxDecoration(
        color: active ? const Color(0xFF111827) : const Color(0xFF10111A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: active ? const Color(0xFF38BDF8).withValues(alpha: 0.48) : const Color(0xFF20212D)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 3),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: const Color(0xFF38BDF8).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.public_rounded, color: Color(0xFF38BDF8), size: 21),
          ),
          title: const Text('ONYX SERVERS', style: TextStyle(color: Color(0xFFF3F4F6), fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.35)),
          subtitle: Text(
            vpn.loadingOnyx ? 'Loading updated servers…' : 'Fast servers · tap to choose a country',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF777B89), fontSize: 11),
          ),
          iconColor: const Color(0xFF38BDF8),
          collapsedIconColor: const Color(0xFF555967),
          onExpansionChanged: (expanded) {
            if (expanded && vpn.onyxServers.isEmpty && !vpn.loadingOnyx) vpn.loadOnyxServers(forceRefresh: true);
          },
          children: [
            if (vpn.loadingOnyx && choices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8), strokeWidth: 2)),
              )
            else if (choices.isEmpty)
              ListTile(
                dense: true,
                title: const Text('Servers unavailable', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                trailing: IconButton(
                  onPressed: () => vpn.loadOnyxServers(forceRefresh: true),
                  icon: const Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8), size: 18),
                ),
              )
            else
              ...choices.map((choice) {
                final selected = vpn.selectedOnyxServer?.link == choice.server.link;
                return Material(
                  color: selected ? const Color(0xFF172536) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      vpn.connectWithMode(VpnMode.pythonServers, onyxServer: choice.server);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Text(choice.flag, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              choice.country,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: selected ? Colors.white : const Color(0xFFB9BBC5), fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                            ),
                          ),
                          if (selected) const Icon(Icons.check_rounded, color: Color(0xFF38BDF8), size: 17),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    ), // Container
    ); // GestureDetector
  }
}

class _CountryServerChoice {
  final String country;
  final String flag;
  final VpnServer server;
  const _CountryServerChoice({required this.country, required this.flag, required this.server});
}

String _codeToFlag(String code) {
  if (code.length != 2) return '🌐';
  final base = 0x1F1E6 - 0x41;
  final c = code.toUpperCase().codeUnits;
  return String.fromCharCode(base + c[0]) + String.fromCharCode(base + c[1]);
}

List<_CountryServerChoice> _countryChoices(List<VpnServer> servers) {
  final ranked = servers.asMap().entries.toList()
    ..sort((a, b) {
      final aPing = a.value.ping;
      final bPing = b.value.ping;
      if (aPing <= 0 && bPing > 0) return 1;
      if (bPing <= 0 && aPing > 0) return -1;
      if (aPing > 0 && bPing > 0) {
        final byPing = aPing.compareTo(bPing);
        if (byPing != 0) return byPing;
      }
      return a.key.compareTo(b.key);
    });

  final countries = <String, _CountryServerChoice>{};
  for (final entry in ranked) {
    final server = entry.value;
    final country = server.country.trim().isNotEmpty ? server.country.trim() : server.name.trim();
    countries.putIfAbsent(
      country.toLowerCase(),
      () => _CountryServerChoice(
        country: country,
        flag: server.flag.trim().isNotEmpty ? server.flag.trim() : '🌐',
        server: server,
      ),
    );
  }
  return countries.values.toList();
}

Future<void> _openCustomFlow(BuildContext context, SingboxProvider vpn) async {
  if (vpn.state != VpnState.disconnected) await vpn.disconnect();
  if (!context.mounted) return;
  vpn.selectMode(VpnMode.custom);
  if (vpn.customUrl == null || vpn.customUrl!.isEmpty) {
    showDialog(context: context, builder: (_) => _UrlDialog(vpn: vpn));
    return;
  }
  if (vpn.servers.isEmpty && !vpn.loadingServers) vpn.fetchServers();
  if (!context.mounted) return;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ServersSheet(vpn: vpn),
  );
}
class _ServersSheet extends StatelessWidget {
  final SingboxProvider vpn;
  const _ServersSheet({required this.vpn});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: vpn,
      child: Consumer<SingboxProvider>(
        builder: (ctx, vpn, _) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: Color(0xFF0E0E1C),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Select Server',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    _SheetBtn(
                      icon: vpn.loadingServers
                          ? const SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(color: Color(0xFF8B5CF6), strokeWidth: 1.5))
                          : const Icon(Icons.refresh_rounded, color: Color(0xFF6B7280), size: 16),
                      onTap: () => vpn.fetchServers(),
                    ),
                    const SizedBox(width: 8),
                    _SheetBtn(
                      icon: const Icon(Icons.edit_rounded, color: Color(0xFF6B7280), size: 16),
                      onTap: () {
                        Navigator.pop(context);
                        Future.delayed(const Duration(milliseconds: 200), () {
                          if (context.mounted) {
                            showDialog(context: context, builder: (_) => _UrlDialog(vpn: vpn));
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
              if (vpn.servers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('${vpn.servers.length} servers available',
                      style: const TextStyle(color: Color(0xFF4B5563), fontSize: 12)),
                  ),
                ),
              // Auto
              _SheetServerTile(
                flag: '⚡',
                name: 'Auto (Fastest)',
                subtitle: 'Automatically selects best server',
                selected: vpn.selectedServer == null,
                onTap: () { Navigator.pop(context); vpn.connectWithMode(VpnMode.custom); },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Divider(color: Color(0xFF1E1E35), height: 1),
              ),
              Expanded(
                child: vpn.loadingServers && vpn.servers.isEmpty
                    ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        CircularProgressIndicator(color: Color(0xFF8B5CF6), strokeWidth: 2),
                        SizedBox(height: 12),
                        Text('Fetching servers...', style: TextStyle(color: Color(0xFF4B5563), fontSize: 13)),
                      ]))
                    : vpn.servers.isEmpty
                        ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.cloud_off_rounded, color: Color(0xFF374151), size: 40),
                            SizedBox(height: 12),
                            Text('No servers found', style: TextStyle(color: Color(0xFF4B5563), fontSize: 13)),
                            SizedBox(height: 4),
                            Text('Check your subscription URL', style: TextStyle(color: Color(0xFF374151), fontSize: 11)),
                          ]))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: vpn.servers.length,
                            itemBuilder: (_, i) {
                              final s = vpn.servers[i];
                              final sel = vpn.selectedServer?.name == s.name;
                              return _SheetServerTile(
                                flag: s.flag.isNotEmpty && s.flag != '??' ? s.flag : '🌐',
                                name: s.name,
                                subtitle: _subtitle(s),
                                selected: sel,
                                onTap: () {
                                  Navigator.pop(context);
                                  vpn.connectWithMode(VpnMode.custom, customServer: s);
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(VpnServer s) {
    if (s.rawOutbound != null) {
      final type = s.rawOutbound!['type'] as String? ?? '';
      final host = s.rawOutbound!['server'] as String? ?? '';
      final port = s.rawOutbound!['server_port']?.toString() ?? '';
      return '${type.toUpperCase()} · $host:$port';
    }
    if (s.link.isNotEmpty) {
      final uri = Uri.tryParse(s.link);
      if (uri != null) return '${uri.scheme.toUpperCase()} · ${uri.host}:${uri.port}';
    }
    return 'Custom server';
  }
}

class _SheetBtn extends StatelessWidget {
  final Widget icon;
  final VoidCallback onTap;
  const _SheetBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFF111120),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E1E35)),
      ),
      child: Center(child: icon),
    ),
  );
}

class _SheetServerTile extends StatelessWidget {
  final String flag;
  final String name;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _SheetServerTile({required this.flag, required this.name, required this.subtitle, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF11112A) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? const Color(0xFF8B5CF6).withValues(alpha: 0.4) : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Text(flag, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                  style: TextStyle(
                    color: selected ? const Color(0xFFE5E7EB) : const Color(0xFF9CA3AF),
                    fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(subtitle,
                  style: const TextStyle(color: Color(0xFF374151), fontSize: 11),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (selected)
            const Icon(Icons.check_circle_rounded, color: Color(0xFF8B5CF6), size: 18),
        ],
      ),
    ),
  );
}

// ─── URL Dialog ───────────────────────────────────────────────
class _UrlDialog extends StatelessWidget {
  final SingboxProvider vpn;
  const _UrlDialog({required this.vpn});

  @override
  Widget build(BuildContext context) {
    final ctrl = TextEditingController(text: vpn.customUrl ?? '');
    return AlertDialog(
      backgroundColor: const Color(0xFF111120),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Subscription URL',
        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'https://example.com/sub',
          hintStyle: const TextStyle(color: Color(0xFF374151)),
          filled: true,
          fillColor: const Color(0xFF0E0E1C),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E35))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E35))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF8B5CF6))),
        ),
        maxLines: 3, minLines: 1,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
        ),
        ElevatedButton(
          onPressed: () async {
            final url = ctrl.text.trim();
            if (url.isNotEmpty) {
              Navigator.pop(context);
              await vpn.setCustomUrl(url);
              vpn.selectMode(VpnMode.custom);
              if (context.mounted) {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _ServersSheet(vpn: vpn),
                );
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF8B5CF6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Save', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

