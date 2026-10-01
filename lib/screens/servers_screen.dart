import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/vpn_provider.dart';

class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A14),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A0A14),
          title: Text(
            'Servers (${vpn.servers.length})',
            style: const TextStyle(color: Colors.white, fontSize: 17),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: const TabBar(
            indicatorColor: Color(0xFF7B5CF0),
            labelColor: Color(0xFF7B5CF0),
            unselectedLabelColor: Color(0xFF6B7280),
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('🔒', style: TextStyle(fontSize: 14)),
                    SizedBox(width: 6),
                    Text('Proxy', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 14),
                    SizedBox(width: 6),
                    Text('OpenVPN', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: vpn.loadingServers
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF7B5CF0)))
            : TabBarView(
                children: [
                  // ─── Tab 1: VLESS / Cloudflare ──────────────
                  _ServerList(
                    servers: vpn.vlessServers,
                    vpn: vpn,
                    emptyIcon: Icons.cloud_off_rounded,
                    emptyMessage: 'No Cloudflare servers found.',
                    headerColor: const Color(0xFF3B82F6),
                    headerLabel: 'Anti-censorship · VLESS / Trojan',
                  ),
                  // ─── Tab 2: OpenVPN ──────────────────────────
                  _ServerList(
                    servers: vpn.openvpnServers,
                    vpn: vpn,
                    emptyIcon: Icons.cloud_off_rounded,
                    emptyMessage: 'No OpenVPN servers found.\nPull down to retry.',
                    headerColor: const Color(0xFF10B981),
                    headerLabel: 'Stable · OpenVPN',
                  ),
                ],
              ),
      ),
    );
  }
}

// ─── Reusable Server List ─────────────────────────────────────
class _ServerList extends StatelessWidget {
  final List<VpnServer> servers;
  final VpnProvider vpn;
  final IconData emptyIcon;
  final String emptyMessage;
  final Color headerColor;
  final String headerLabel;

  const _ServerList({
    required this.servers,
    required this.vpn,
    required this.emptyIcon,
    required this.emptyMessage,
    required this.headerColor,
    required this.headerLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (servers.isEmpty) {
      return RefreshIndicator(
        color: const Color(0xFF7B5CF0),
        backgroundColor: const Color(0xFF12121E),
        onRefresh: () => vpn.fetchServers(forceRefresh: true),
        child: ListView(children: [
          const SizedBox(height: 120),
          Column(children: [
            Icon(emptyIcon, color: const Color(0xFF6B7280), size: 44),
            const SizedBox(height: 12),
            Text(
              emptyMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
            ),
            const SizedBox(height: 6),
            const Text('Pull down to retry',
                style: TextStyle(color: Color(0xFF7B5CF0), fontSize: 12)),
          ]),
        ]),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF7B5CF0),
      backgroundColor: const Color(0xFF12121E),
      onRefresh: () => vpn.fetchServers(forceRefresh: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        itemCount: servers.length + 1, // +1 للـ header
        separatorBuilder: (_, i) =>
            i == 0 ? const SizedBox(height: 12) : const SizedBox(height: 8),
        itemBuilder: (_, i) {
          // ─── Header ───────────────────────────────────────
          if (i == 0) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: headerColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: headerColor.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                Icon(Icons.info_outline_rounded,
                    size: 13, color: headerColor),
                const SizedBox(width: 6),
                Text(headerLabel,
                    style: TextStyle(
                        color: headerColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
              ]),
            );
          }

          final s = servers[i - 1];
          final selected = vpn.selectedServer?.ip == s.ip;
          final connected = vpn.isConnected && selected;
          final connecting = vpn.isConnecting && selected;

          return _ServerTile(
            server: s,
            selected: selected,
            connecting: connecting,
            connected: connected,
            onTap: () {
              vpn.connectTo(s);
              Navigator.pop(context);
            },
          );
        },
      ),
    );
  }
}

// ─── Server Tile ─────────────────────────────────────────────
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

    // VLESS له لون مميز خاص
    final tileColor = server.isVless
        ? (selected
            ? const Color(0xFF0F1B2D)
            : const Color(0xFF0D1520))
        : (selected
            ? const Color(0xFF15152A)
            : const Color(0xFF12121E));

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: tileColor,
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
                  Row(children: [
                    Text(server.countryName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    if (server.isVless) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('VLESS',
                            style: TextStyle(
                                color: Color(0xFF3B82F6),
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                  Text(
                    '${server.effectivePing > 0 && server.effectivePing < 9999 ? server.effectivePing : server.ping} ms · ${server.pingLabel}',
                    style: const TextStyle(
                        color: Color(0xFF6B7280), fontSize: 11),
                  ),
                ],
              ),
            ),
            if (connecting)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFFF59E0B)),
              )
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
