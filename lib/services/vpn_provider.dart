import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';
import 'package:wireguard_flutter/wireguard_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ads_service.dart';
import 'cache_service.dart';

// ─── helpers ──────────────────────────────────────────────────
String cleanCountryName(String raw) =>
    raw.replaceAll(RegExp(r'\s*\(.*?\)'), '').trim();

String formatSpeed(String raw) {
  final num = double.tryParse(raw.replaceAll(RegExp(r'[^0-9.]'), ''));
  if (num == null || num == 0) return '0 B/s';
  if (num >= 1024 * 1024) return '${(num / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  if (num >= 1024) return '${(num / 1024).toStringAsFixed(1)} KB/s';
  return '${num.toStringAsFixed(0)} B/s';
}

// ─── Server Protocol ───────────────────────────────────────────
enum ServerProtocol { openvpn, warp }

// ─── Server Source (للتمييز بين VPNGate و Supabase) ───────────
enum ServerSource { vpngate, supabase }

// ─── WARP Config ──────────────────────────────────────────────
const _warpConfig = '''
[Interface]
PrivateKey = PLACEHOLDER_WILL_BE_GENERATED
Address = 172.16.0.2/32
DNS = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = engage.cloudflareclient.com:2408
PersistentKeepalive = 25
''';

// ─── VpnServer ────────────────────────────────────────────────
class VpnServer {
  final String countryName;
  final String countryCode;
  final String ip;
  final int ping;
  final String ovpnConfig;
  final int numSessions;
  final ServerProtocol protocol;
  final ServerSource source;

  const VpnServer({
    required this.countryName,
    required this.countryCode,
    required this.ip,
    required this.ping,
    required this.ovpnConfig,
    this.numSessions = 0,
    this.protocol = ServerProtocol.openvpn,
    this.source = ServerSource.vpngate,
  });

  static VpnServer get warp => const VpnServer(
        countryName: 'Cloudflare WARP',
        countryCode: 'CF',
        ip: 'engage.cloudflareclient.com',
        ping: 20,
        ovpnConfig: '',
        numSessions: 0,
        protocol: ServerProtocol.warp,
        source: ServerSource.vpngate,
      );

  bool get isWarp => protocol == ServerProtocol.warp;
  bool get isFromSupabase => source == ServerSource.supabase;

  int get score {
    final congestion = (numSessions / 10).clamp(0, 200).toInt();
    return ping + congestion;
  }

  String get flag {
    if (countryCode == 'CF') return '🌐';
    if (countryCode.length != 2) return '🌐';
    return countryCode.toUpperCase().split('').map(
      (c) => String.fromCharCode(c.codeUnitAt(0) + 127397),
    ).join();
  }

  String get pingLabel {
    if (isWarp) return 'Fast & Secure';
    if (ping < 60) return 'Excellent';
    if (ping < 120) return 'Good';
    if (ping < 200) return 'Fair';
    return 'Slow';
  }

  int get bars {
    if (isWarp) return 4;
    if (ping < 60) return 4;
    if (ping < 120) return 3;
    if (ping < 200) return 2;
    return 1;
  }

  Map<String, dynamic> toMap() => {
    'country_name': countryName,
    'country_code': countryCode,
    'ip': ip,
    'ping': ping,
    'ovpn_config': ovpnConfig,
    'num_sessions': numSessions,
    'protocol': protocol.name,
    'source': source.name,
  };

  factory VpnServer.fromMap(Map<String, dynamic> m, {ServerSource src = ServerSource.vpngate}) => VpnServer(
    countryName: cleanCountryName(m['country_name'] ?? ''),
    countryCode: m['country_code'] ?? '',
    ip: m['ip'] ?? '',
    ping: (m['ping'] as num?)?.toInt() ?? 999,
    ovpnConfig: m['ovpn_config'] ?? '',
    numSessions: (m['num_sessions'] as num?)?.toInt() ?? 0,
    protocol: m['protocol'] == 'warp' ? ServerProtocol.warp : ServerProtocol.openvpn,
    source: src,
  );
}

// ─── VpnProvider ──────────────────────────────────────────────
class VpnProvider extends ChangeNotifier {
  // قائمتان منفصلتان
  final List<VpnServer> _vpngateServers = [];
  final List<VpnServer> _supabaseServers = [];

  List<VpnServer> get vpngateServers => _vpngateServers;
  List<VpnServer> get supabaseServers => _supabaseServers;

  // للتوافق مع الكود القديم
  List<VpnServer> get servers => _vpngateServers;
  int get totalServers => _vpngateServers.length + _supabaseServers.length;

  bool _hasMore = false;
  bool get hasMore => _hasMore;
  bool _loadingMore = false;
  bool get loadingMore => _loadingMore;

  VpnServer? _selected;
  VpnServer? get selectedServer => _selected;

  bool _loadingServers = false;
  bool get loadingServers => _loadingServers;

  String? _serversError;
  String? get serversError => _serversError;

  VPNStage _stage = VPNStage.disconnected;

  bool get isConnected => _stage == VPNStage.connected || _warpConnected;
  bool get isConnecting =>
      _stage == VPNStage.connecting ||
      _stage == VPNStage.authenticating ||
      _stage == VPNStage.vpn_generate_config ||
      _stage == VPNStage.prepare ||
      _warpConnecting;

  bool _warpConnected = false;
  bool _warpConnecting = false;

  String _statusMessage = '';
  String get statusMessage => _statusMessage;

  String _downloadSpeed = '0 B/s';
  String _uploadSpeed = '0 B/s';
  String get downloadSpeed => _downloadSpeed;
  String get uploadSpeed => _uploadSpeed;

  Duration connectionDuration = Duration.zero;
  DateTime? _connectedAt;
  Timer? _statsTimer;
  Timer? _connectionTimeout;
  Timer? _reconnectTimer;

  OpenVPN? _vpn;
  final _wg = WireGuardFlutter.instance;

  VpnServer? _lastSuccessfulServer;
  final List<String> _triedIps = [];
  final List<String> _trustedIps = [];

  bool _userDisconnected = false;
  bool _isSwitchingServer = false;
  bool _isReconnecting = false;
  bool get isReconnecting => _isReconnecting;

  static const int _timeoutSeconds = 20;
  static const int _pageSize = 20;

  VpnProvider() {
    _initOpenVpn();
    // ✅ إصلاح ١: لا نتصل تلقائياً عند البداية
  }

  // ─── Init OpenVPN ──────────────────────────────────────────
  void _initOpenVpn() {
    _vpn = OpenVPN(
      onVpnStageChanged: (stage, _) {
        // ✅ إصلاح ٢: تجاهل أحداث OpenVPN لو WARP شغّال
        if (_selected?.isWarp == true) return;

        _stage = stage;

        if (stage == VPNStage.connected) {
          _connectionTimeout?.cancel();
          _reconnectTimer?.cancel();
          _isReconnecting = false;
          _triedIps.clear();
          _lastSuccessfulServer = _selected;
          _statusMessage = '';

          if (_selected != null && !_trustedIps.contains(_selected!.ip)) {
            _trustedIps.insert(0, _selected!.ip);
            if (_trustedIps.length > 10) _trustedIps.removeLast();
          }

          _connectedAt = DateTime.now();
          _startStats();
          AdsService.showInterstitialAfterSuccess(1);
        } else if (stage == VPNStage.disconnected) {
          _connectionTimeout?.cancel();
          _stopStats();

          if (_userDisconnected) {
            _isReconnecting = false;
            _statusMessage = '';
          } else if (!_isSwitchingServer) {
            // ✅ إصلاح ٤: الاتصال الذكي — يكمّل حتى Connected
            _isReconnecting = true;
            _statusMessage = 'Connecting...';
            _scheduleReconnect();
          }
        } else if (stage == VPNStage.connecting) {
          _statusMessage = 'Connecting...';
        } else if (stage == VPNStage.authenticating) {
          _statusMessage = 'Authenticating...';
        } else if (stage == VPNStage.prepare) {
          _statusMessage = 'Connecting...';
        }

        notifyListeners();
      },
      onVpnStatusChanged: (status) {
        if (status != null && _selected?.isWarp != true) {
          _downloadSpeed = formatSpeed(status.byteIn ?? '0');
          _uploadSpeed = formatSpeed(status.byteOut ?? '0');
          notifyListeners();
        }
      },
    );

    _vpn!.initialize(
      groupIdentifier: 'com.onyxvpn.onyx_vpn',
      providerBundleIdentifier: 'com.onyxvpn.onyx_vpn',
      localizedDescription: 'OnyxVPN',
    );
  }

  // ─── WARP Connect ──────────────────────────────────────────
  // ✅ إصلاح ٢: WARP منفصل تماماً عن OpenVPN — لا تضارب
  Future<void> connectWarp() async {
    // قطع OpenVPN إذا شغّال
    if (_stage != VPNStage.disconnected) {
      _isSwitchingServer = true;
      _vpn?.disconnect();
      await Future.delayed(const Duration(milliseconds: 500));
      _stage = VPNStage.disconnected;
      _isSwitchingServer = false;
    }

    // قطع WARP القديم إذا شغّال
    if (_warpConnected || _warpConnecting) {
      await _disconnectWarp();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    _userDisconnected = false;
    _selected = VpnServer.warp;
    _warpConnecting = true;
    _warpConnected = false;
    _statusMessage = 'Connecting...';
    notifyListeners();

    try {
      await _wg.initialize(interfaceName: 'warp0');
      await _wg.startVpn(
        serverAddress: 'engage.cloudflareclient.com',
        wgQuickConfig: _warpConfig,
        providerBundleIdentifier: 'com.onyxvpn.onyx_vpn',
      );

      _warpConnecting = false;
      _warpConnected = true;
      _statusMessage = '';
      _connectedAt = DateTime.now();
      _startStats();
      AdsService.showInterstitialAfterSuccess(1);
      notifyListeners();
    } catch (e) {
      _warpConnecting = false;
      _warpConnected = false;
      _selected = null;
      _statusMessage = '';
      notifyListeners();
    }
  }

  Future<void> _disconnectWarp() async {
    try {
      await _wg.stopVpn();
    } catch (_) {}
    _warpConnected = false;
    _warpConnecting = false;
    _stopStats();
  }

  // ─── Connect To ────────────────────────────────────────────
  Future<void> connectTo(VpnServer server, {bool isAutoReconnect = false}) async {
    if (server.isWarp) {
      await connectWarp();
      return;
    }

    // ✅ إصلاح ٢: قطع WARP أولاً إذا شغّال
    if (_warpConnected || _warpConnecting) {
      await _disconnectWarp();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (isConnected || isConnecting) {
      _userDisconnected = false;
      _isSwitchingServer = true;
      _isReconnecting = false;
      _vpn?.disconnect();
      _stage = VPNStage.disconnected;
      _stopStats();
      _connectionTimeout?.cancel();
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 300));
      _isSwitchingServer = false;
    }

    _userDisconnected = false;
    _selected = server;
    _stage = VPNStage.prepare;
    _statusMessage = 'Connecting...';
    notifyListeners();

    if (server.ovpnConfig.isEmpty) {
      _tryNextServer(server);
      return;
    }

    if (!_triedIps.contains(server.ip)) {
      _triedIps.add(server.ip);
    }

    _connectionTimeout?.cancel();
    _connectionTimeout = Timer(
      const Duration(seconds: _timeoutSeconds),
      () {
        if (isConnecting) {
          _isSwitchingServer = true;
          _vpn?.disconnect();
          _isSwitchingServer = false;
          _stage = VPNStage.prepare;
          _statusMessage = 'Connecting...';
          notifyListeners();
          _tryNextServer(server);
        }
      },
    );

    try {
      _vpn?.connect(
        server.ovpnConfig,
        server.countryName,
        username: 'vpn',
        password: 'vpn',
        certIsRequired: false,
      );
    } catch (_) {
      _stage = VPNStage.disconnected;
      _connectionTimeout?.cancel();
      _statusMessage = '';
      notifyListeners();
      _tryNextServer(server);
    }
  }

  // ✅ إصلاح ٥: الدائرة للـ WARP فقط
  Future<void> connectFastest() async {
    await connectWarp();
  }

  // ─── Disconnect ────────────────────────────────────────────
  Future<void> disconnect() async {
    _userDisconnected = true;
    _isSwitchingServer = false;
    _isReconnecting = false;
    _reconnectTimer?.cancel();
    _connectionTimeout?.cancel();
    _triedIps.clear();

    if (_warpConnected || _warpConnecting) {
      await _disconnectWarp();
    } else {
      _vpn?.disconnect();
    }

    _stage = VPNStage.disconnected;
    _selected = null;
    _statusMessage = '';
    _stopStats();
    notifyListeners();
  }

  // ─── Try Next Server ───────────────────────────────────────
  // ✅ إصلاح ٤: يجرب كل السيرفرات (VPNGate + Supabase)
  Future<void> _tryNextServer(VpnServer failed) async {
    final allOpenvpn = [..._vpngateServers, ..._supabaseServers]
        .where((s) => !s.isWarp && s.ovpnConfig.isNotEmpty && !_triedIps.contains(s.ip))
        .take(1)
        .toList();

    if (allOpenvpn.isNotEmpty) {
      await connectTo(allOpenvpn.first);
    } else {
      _triedIps.clear();
      _stage = VPNStage.disconnected;
      _statusMessage = '';
      _isReconnecting = false;
      notifyListeners();
    }
  }

  // ─── Reconnect ─────────────────────────────────────────────
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () async {
      if (isConnected || isConnecting || _userDisconnected) {
        _isReconnecting = false;
        notifyListeners();
        return;
      }

      final allOpenvpn = [..._vpngateServers, ..._supabaseServers]
          .where((s) => !s.isWarp && s.ovpnConfig.isNotEmpty && !_triedIps.contains(s.ip))
          .take(1)
          .toList();

      if (allOpenvpn.isNotEmpty) {
        _selected = allOpenvpn.first;
        _stage = VPNStage.prepare;
        _statusMessage = 'Connecting...';
        notifyListeners();
        await connectTo(allOpenvpn.first, isAutoReconnect: true);
      } else {
        _triedIps.clear();
        final restart = _lastSuccessfulServer ?? _selected;
        if (restart != null && !restart.isWarp) {
          await connectTo(restart, isAutoReconnect: true);
        } else {
          await connectWarp();
        }
      }
    });
  }

  // ─── Stats ─────────────────────────────────────────────────
  void _startStats() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_connectedAt != null) {
        connectionDuration = DateTime.now().difference(_connectedAt!);
        notifyListeners();
      }
    });
  }

  void _stopStats() {
    _statsTimer?.cancel();
    _connectedAt = null;
    connectionDuration = Duration.zero;
    _downloadSpeed = '0 B/s';
    _uploadSpeed = '0 B/s';
  }

  String get formattedTime {
    final h = connectionDuration.inHours.toString().padLeft(2, '0');
    final m = connectionDuration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = connectionDuration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // ─── Load More ─────────────────────────────────────────────
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 100));
    _hasMore = false;
    _loadingMore = false;
    notifyListeners();
  }

  // ─── Fetch Servers ─────────────────────────────────────────
  Future<void> fetchServers({bool forceRefresh = false}) async {
    _serversError = null;

    if (!forceRefresh) {
      final cached = CacheService.getCachedServers();
      if (cached != null && cached.isNotEmpty) {
        _applyServersFromCache(cached);
        _loadingServers = false;
        notifyListeners();
        if (!CacheService.isCacheValid) _backgroundRefresh();
        return;
      }
    }

    _loadingServers = true;
    _vpngateServers.clear();
    _supabaseServers.clear();
    _hasMore = false;
    notifyListeners();

    final results = await Future.wait([
      _fetchVpnGate(),
      _fetchSupabase().catchError((_) => <VpnServer>[]),
    ]);

    final vpngateList = results[0];
    final supabaseList = results[1];

    if (vpngateList.isNotEmpty || supabaseList.isNotEmpty) {
      _applyVpngateServers(vpngateList);
      _applySupabaseServers(supabaseList);

      final allForCache = [..._vpngateServers, ..._supabaseServers];
      await CacheService.saveServers(allForCache.map((s) => s.toMap()).toList());
    } else {
      _serversError = 'Could not fetch servers. Pull down to retry.';
    }

    _loadingServers = false;
    notifyListeners();
  }

  Future<void> _backgroundRefresh() async {
    try {
      final results = await Future.wait([
        _fetchVpnGate(),
        _fetchSupabase().catchError((_) => <VpnServer>[]),
      ]);
      _applyVpngateServers(results[0]);
      _applySupabaseServers(results[1]);
      final allForCache = [..._vpngateServers, ..._supabaseServers];
      await CacheService.saveServers(allForCache.map((s) => s.toMap()).toList());
      notifyListeners();
    } catch (_) {}
  }

  void _applyServersFromCache(List<Map<String, dynamic>> cached) {
    _vpngateServers.clear();
    _supabaseServers.clear();
    for (final m in cached) {
      final src = m['source'] == 'supabase' ? ServerSource.supabase : ServerSource.vpngate;
      final s = VpnServer.fromMap(m, src: src);
      if (s.isWarp || s.ovpnConfig.isEmpty || s.ping > 300) continue;
      if (src == ServerSource.supabase) {
        _supabaseServers.add(s);
      } else {
        _vpngateServers.add(s);
      }
    }
    _sortList(_vpngateServers);
    _sortList(_supabaseServers);
  }

  void _applyVpngateServers(List<VpnServer> list) {
    _vpngateServers.clear();
    final filtered = list.where((s) => !s.isWarp && s.ping <= 300 && s.ovpnConfig.isNotEmpty).toList();
    _sortList(filtered);
    final seenIps = <String>{};
    final countryCount = <String, int>{};
    for (final s in filtered) {
      if (seenIps.contains(s.ip)) continue;
      seenIps.add(s.ip);
      final count = countryCount[s.countryCode] ?? 0;
      if (count < 3) {
        _vpngateServers.add(s);
        countryCount[s.countryCode] = count + 1;
      }
    }
  }

  void _applySupabaseServers(List<VpnServer> list) {
    _supabaseServers.clear();
    final filtered = list.where((s) => !s.isWarp && s.ping <= 300 && s.ovpnConfig.isNotEmpty).toList();
    _sortList(filtered);
    final seenIps = <String>{};
    for (final s in filtered) {
      if (seenIps.contains(s.ip)) continue;
      seenIps.add(s.ip);
      _supabaseServers.add(s);
    }
  }

  void _sortList(List<VpnServer> list) {
    list.sort((a, b) {
      final aTrusted = _trustedIps.contains(a.ip);
      final bTrusted = _trustedIps.contains(b.ip);
      if (aTrusted && !bTrusted) return -1;
      if (!aTrusted && bTrusted) return 1;
      return a.score.compareTo(b.score);
    });
  }

  // ─── Fetch VPNGate ─────────────────────────────────────────
  Future<List<VpnServer>> _fetchVpnGate() async {
    final urls = [
      'https://www.vpngate.net/api/iphone/',
      'https://vpngate.net/api/iphone/',
    ];

    for (final url in urls) {
      try {
        final res = await http.get(
          Uri.parse(url),
          headers: {'User-Agent': 'Mozilla/5.0'},
        ).timeout(const Duration(seconds: 12));

        if (res.statusCode != 200) continue;

        final lines = res.body.split('\n');
        final csv = lines.skip(1).join('\n');
        final rows = const CsvToListConverter().convert(csv);
        final result = <VpnServer>[];

        for (final r in rows.skip(1)) {
          if (r.length <= 14 || r[14].toString().isEmpty) continue;
          try {
            final ping = int.tryParse(r[3].toString()) ?? 999;
            if (ping > 300) continue;
            final config = utf8.decode(base64.decode(r[14].toString()));
            final name = cleanCountryName(r[5].toString());
            if (name.isEmpty) continue;
            final sessions = int.tryParse(r[7].toString()) ?? 0;

            result.add(VpnServer(
              countryName: name,
              countryCode: r[6].toString().toUpperCase(),
              ip: r[1].toString(),
              ping: ping,
              ovpnConfig: config,
              numSessions: sessions,
              source: ServerSource.vpngate,
            ));
            if (result.length >= 80) break;
          } catch (_) {}
        }
        if (result.isNotEmpty) return result;
      } catch (_) {}
    }
    return [];
  }

  // ─── Fetch Supabase ────────────────────────────────────────
  Future<List<VpnServer>> _fetchSupabase() async {
    final res = await Supabase.instance.client
        .from('servers')
        .select()
        .eq('is_active', true)
        .lte('ping', 300)
        .order('ping', ascending: true)
        .limit(80);
    return (res as List).map((r) => VpnServer.fromMap(r, src: ServerSource.supabase)).toList();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _connectionTimeout?.cancel();
    _reconnectTimer?.cancel();
    super.dispose();
  }
}
