import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/vpn_provider.dart';
import '../services/ads_service.dart';
import 'servers_screen.dart';
import 'info_screen.dart';
import 'debug_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  _TopBar(),
                  Expanded(child: _MainContent()),
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
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onLongPress: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DebugScreen()),
            ),
            child: RichText(
              text: const TextSpan(children: [
                TextSpan(
                  text: 'Onyx',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5),
                ),
                TextSpan(
                  text: 'VPN',
                  style: TextStyle(
                      color: Color(0xFF7B5CF0),
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5),
                ),
              ]),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const InfoScreen())),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF12121E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.info_outline_rounded,
                  color: Color(0xFF7B5CF0), size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Main Content ─────────────────────────────────────────────
class _MainContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<VpnProvider>(
      builder: (context, vpn, _) {
        return Column(
          children: [
            const SizedBox(height: 28),
            _PowerOrb(vpn: vpn),
            const SizedBox(height: 16),
            _StatusChip(vpn: vpn),
            const SizedBox(height: 20),
            _StatsRow(vpn: vpn),
            const SizedBox(height: 16),
            _ServersPanel(vpn: vpn),
          ],
        );
      },
    );
  }
}

// ─── Power Orb ────────────────────────────────────────────────
class _PowerOrb extends StatefulWidget {
  final VpnProvider vpn;
  const _PowerOrb({required this.vpn});

  @override
  State<_PowerOrb> createState() => _PowerOrbState();
}

class _PowerOrbState extends State<_PowerOrb>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulse = Tween(begin: 1.0, end: 1.08)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vpn = widget.vpn;
    final connected  = vpn.isConnected;
    final connecting = vpn.isConnecting;
    final failed     = vpn.isFailed;
    final loading    = vpn.loadingServers;

    final color = failed
        ? const Color(0xFFEF4444)
        : connecting
            ? const Color(0xFFF59E0B)
            : connected
                ? const Color(0xFF10B981)
                : const Color(0xFF7B5CF0);

    String label;
    if (loading)         label = 'Loading...';
    else if (failed)     label = vpn.statusMessage;
    else if (connected)  label = 'Tap to\ndisconnect';
    else if (connecting) label = vpn.statusMessage;
    else                 label = 'Quick\nConnect';

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final active = connected || connecting;
        final scale  = active ? _pulse.value : 1.0;
        return Transform.scale(
          scale: scale,
          child: GestureDetector(
            onTap: () {
              if (loading || failed) return;
              if (connected || connecting) {
                vpn.disconnect();
              } else {
                vpn.connectFastest();
              }
            },
            child: SizedBox(
              width: 170, height: 170,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (connected || connecting)
                    Container(
                      width: 170, height: 170,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: color.withValues(alpha: 0.12), width: 18),
                      ),
                    ),
                  Container(
                    width: 142, height: 142,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: color.withValues(alpha: 0.25), width: 2),
                    ),
                  ),
                  if (connecting)
                    SizedBox(
                      width: 142, height: 142,
                      child: CircularProgressIndicator(
                          color: color, strokeWidth: 2),
                    ),
                  Container(
                    width: 110, height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF12121E),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(
                              alpha: connected ? 0.4 : 0.2),
                          blurRadius: 30,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.power_settings_new_rounded,
                            size: 36, color: color),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: color.withValues(alpha: 0.85),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Status Chip ──────────────────────────────────────────────
class _StatusChip extends StatelessWidget {
  final VpnProvider vpn;
  const _StatusChip({required this.vpn});

  @override
  Widget build(BuildContext context) {
    final connected  = vpn.isConnected;
    final connecting = vpn.isConnecting;

    final color = connecting
        ? const Color(0xFFF59E0B)
        : connected
            ? const Color(0xFF10B981)
            : const Color(0xFF6B7280);

    final text = connected
        ? vpn.selectedServer?.countryName ?? 'Connected'
        : vpn.statusMessage.isNotEmpty
            ? vpn.statusMessage
            : 'Not Connected';

    final flag = (connected || connecting)
        ? vpn.selectedServer?.flag ?? ''
        : '';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 7, height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          if (flag.isNotEmpty) ...[
            Text(flag, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
          ],
          Text(text,
              style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─── Stats Row ────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final VpnProvider vpn;
  const _StatsRow({required this.vpn});

  @override
  Widget build(BuildContext context) {
    final active = vpn.isConnected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _StatCard(
              icon: Icons.arrow_downward_rounded,
              label: 'Download',
              value: active ? vpn.downloadSpeed : '--',
              color: const Color(0xFF10B981)),
          const SizedBox(width: 10),
          _StatCard(
              icon: Icons.arrow_upward_rounded,
              label: 'Upload',
              value: active ? vpn.uploadSpeed : '--',
              color: const Color(0xFF7B5CF0)),
          const SizedBox(width: 10),
          _StatCard(
              icon: Icons.timer_rounded,
              label: 'Time',
              value: active ? vpn.formattedTime : '--:--',
              color: const Color(0xFF3B82F6)),
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
  const _StatCard(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF12121E),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF6B7280), fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

// ─── Servers Panel ────────────────────────────────────────────
enum _ServerFilter { all, port443, fast }

class _ServersPanel extends StatefulWidget {
  final VpnProvider vpn;
  const _ServersPanel({required this.vpn});

  @override
  State<_ServersPanel> createState() => _ServersPanelState();
}

class _ServersPanelState extends State<_ServersPanel> {
  _ServerFilter _filter = _ServerFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.vpn.servers.isEmpty) widget.vpn.fetchServers();
    });
  }

  List<VpnServer> _filtered(VpnProvider vpn) {
    switch (_filter) {
      case _ServerFilter.port443:
        return vpn.serversPort443;
      case _ServerFilter.fast:
        return vpn.serversFast;
      case _ServerFilter.all:
        return vpn.servers;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vpn = widget.vpn;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          // ── بادجات الفلتر ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                _FilterBadge(
                  label: 'All',
                  icon: Icons.language_rounded,
                  active: _filter == _ServerFilter.all,
                  activeColor: const Color(0xFF7B5CF0),
                  onTap: () => setState(() => _filter = _ServerFilter.all),
                ),
                const SizedBox(width: 8),
                _FilterBadge(
                  label: 'Port 443',
                  icon: Icons.lock_outline_rounded,
                  active: _filter == _ServerFilter.port443,
                  activeColor: const Color(0xFF1D9E75),
                  onTap: () =>
                      setState(() => _filter = _ServerFilter.port443),
                ),
                const SizedBox(width: 8),
                _FilterBadge(
                  label: 'Fast',
                  icon: Icons.bolt_rounded,
                  active: _filter == _ServerFilter.fast,
                  activeColor: const Color(0xFFF48120),
                  onTap: () => setState(() => _filter = _ServerFilter.fast),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── قائمة السيرفرات ────────────────────────────────
          Expanded(
            child: vpn.loadingServers
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF7B5CF0)))
                : vpn.servers.isEmpty
                    ? _emptyView(vpn)
                    : Builder(builder: (ctx) {
                        final list = _filtered(vpn);
                        if (list.isEmpty) {
                          return Center(
                            child: Text(
                              'No servers match this filter',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  fontSize: 13),
                            ),
                          );
                        }
                        // نأخذ أول 8 سيرفرات من الفلتر الحالي
                        final displayList = list.take(8).toList();
                        return RefreshIndicator(
                          color: const Color(0xFF7B5CF0),
                          backgroundColor: const Color(0xFF12121E),
                          onRefresh: () =>
                              vpn.fetchServers(forceRefresh: true),
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24),
                            itemCount: displayList.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final s   = displayList[i];
                              final sel = vpn.selectedServer?.ip == s.ip;
                              return _ServerTile(
                                    server: s,
                                    selected: sel,
                                    connecting:
                                        vpn.isConnecting && sel,
                                    connected: vpn.isConnected && sel,
                                    onTap: () => vpn.connectTo(s),
                                  );
                            },
                          ),
                        );
                      }),
          ),
        ],
      ),
    );
  }

  Widget _emptyView(VpnProvider vpn) {
    return RefreshIndicator(
      color: const Color(0xFF7B5CF0),
      backgroundColor: const Color(0xFF12121E),
      onRefresh: () => vpn.fetchServers(forceRefresh: true),
      child: ListView(children: [
        const SizedBox(height: 60),
        Column(
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: Color(0xFF6B7280), size: 44),
            const SizedBox(height: 10),
            Text(
              vpn.serversError ?? 'No servers found.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF6B7280), fontSize: 13),
            ),
            const SizedBox(height: 6),
            const Text('Pull down to retry',
                style: TextStyle(
                    color: Color(0xFF7B5CF0), fontSize: 12)),
          ],
        ),
      ]),
    );
  }
}

// ─── Filter Badge ─────────────────────────────────────────────
class _FilterBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _FilterBadge({
    required this.label,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 52, // ارتفاع ثابت لكل الباجات
          decoration: BoxDecoration(
            color: active
                ? activeColor.withValues(alpha: 0.12)
                : const Color(0xFF12121E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? activeColor.withValues(alpha: 0.4)
                  : const Color(0xFF1E1E2E),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: active ? activeColor : const Color(0xFF6B7280)),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color:
                        active ? activeColor : const Color(0xFF6B7280),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Server Tile ──────────────────────────────────────────────
class _ServerTile extends StatelessWidget {
  final VpnServer server;
  final bool selected;
  final bool connecting;
  final bool connected;
  final VoidCallback onTap;

  const _ServerTile({
    required this.server,
    required this.selected,
    required this.connecting,
    required this.connected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = connected
        ? const Color(0xFF10B981)
        : connecting
            ? const Color(0xFFF59E0B)
            : selected
                ? const Color(0xFF7B5CF0)
                : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF15152A)
              : const Color(0xFF12121E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Row(
          children: [
            Text(server.flag, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(server.countryName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                      if (server.isHardToBlock) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1D9E75)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: const Color(0xFF1D9E75)
                                    .withValues(alpha: 0.4)),
                          ),
                          child: const Text('443',
                              style: TextStyle(
                                  color: Color(0xFF1D9E75),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${server.effectivePing > 0 && server.effectivePing < 9999 ? server.effectivePing : server.ping} ms · ${server.pingLabel}',
                    style: const TextStyle(
                        color: Color(0xFF6B7280), fontSize: 11)),
                ],
              ),
            ),
            if (connecting)
              const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFFF59E0B)))
            else if (connected)
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF10B981), size: 20)
            else
              _SignalBars(bars: server.bars),
          ],
        ),
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  final int bars;
  const _SignalBars({required this.bars});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        return Container(
          width: 4,
          height: 5.0 + (i * 3.5),
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
            color: i < bars
                ? const Color(0xFF7B5CF0)
                : const Color(0xFF2A2A3E),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
