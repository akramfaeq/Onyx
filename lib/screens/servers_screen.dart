import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/vpn_provider.dart';

class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key});

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A14),
        title: const Text('All Servers',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF7B5CF0),
          labelColor: const Color(0xFF7B5CF0),
          unselectedLabelColor: const Color(0xFF6B7280),
          tabs: [
            Tab(text: 'Recommended (${vpn.supabaseServers.length})'),
            Tab(text: 'VPN Gate (${vpn.vpngateServers.length})'),
          ],
        ),
      ),
      body: RefreshIndicator(
        color: const Color(0xFF7B5CF0),
        backgroundColor: const Color(0xFF12121E),
        onRefresh: () => vpn.fetchServers(forceRefresh: true),
        child: vpn.loadingServers
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF7B5CF0)))
            : TabBarView(
                controller: _tabController,
                children: [
                  // ── تاب Supabase (Recommended) ──
                  _ServerList(
                    servers: vpn.supabaseServers,
                    vpn: vpn,
                    emptyMessage: 'No recommended servers yet.\nPull down to refresh.',
                  ),
                  // ── تاب VPNGate ──
                  _ServerList(
                    servers: vpn.vpngateServers,
                    vpn: vpn,
                    emptyMessage: 'No VPN Gate servers.\nPull down to refresh.',
                  ),
                ],
              ),
      ),
    );
  }
}

class _ServerList extends StatelessWidget {
  final List<VpnServer> servers;
  final VpnProvider vpn;
  final String emptyMessage;

  const _ServerList({
    required this.servers,
    required this.vpn,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (servers.isEmpty) {
      return Center(
        child: Text(emptyMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: servers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final s = servers[i];
        final selected = vpn.selectedServer?.ip == s.ip;
        final connected = vpn.isConnected && selected;
        final connecting = vpn.isConnecting && selected;

        return GestureDetector(
          onTap: () {
            vpn.connectTo(s);
            Navigator.pop(context);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF15152A)
                  : const Color(0xFF12121E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: connected
                    ? const Color(0xFF10B981)
                    : connecting
                        ? const Color(0xFFF59E0B)
                        : selected
                            ? const Color(0xFF7B5CF0)
                            : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Text(s.flag, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.countryName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                      Text('${s.ping} ms · ${s.pingLabel}',
                          style: const TextStyle(
                              color: Color(0xFF6B7280), fontSize: 11)),
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(4, (j) {
                      return Container(
                        width: 4,
                        height: 5.0 + (j * 3.5),
                        margin: const EdgeInsets.only(left: 2),
                        decoration: BoxDecoration(
                          color: j < s.bars
                              ? const Color(0xFF7B5CF0)
                              : const Color(0xFF2A2A3E),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
