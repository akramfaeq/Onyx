import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:openvpn_flutter/openvpn_flutter.dart';
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

// ─── Server Source ────────────────────────────────────────────
enum ServerSource { vpngate, supabase }

// ─── VpnServer ────────────────────────────────────────────────
class VpnServer {
  final String countryName;
  final String countryCode;
  final String ip;
  final int ping;
  final String ovpnConfig;
  final int numSessions;
  final ServerSource source;

  const VpnServer({
    required this.countryName,
    required this.countryCode,
    required this.ip,
    required this.ping,
    required this.ovpnConfig,
    this.numSessions = 0,
    this.source = ServerSource.vpngate,
  });

  int get score {
    final congestion = (numSessions / 10).clamp(0, 200).toInt();
    return ping + congestion;
  }

  String get flag {
    if (countryCode.length != 2) return '🌐';
    return countryCode.toUpperCase().split('').map(
      (c) => String.fromCharCode(c.codeUnitAt(0) + 127397),
    ).join();
  }

  String get pingLabel {
    if (ping < 60) return 'Excellent';
    if (ping < 120) return 'Good';
    if (ping < 200) return 'Fair';
    return 'Slow';
  }

  int get bars {
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
    'source': source.name,
  };

  factory VpnServer.fromMap(Map<String, dynamic> m,
      {ServerSource src = ServerSource.vpngate}) =>
      VpnServer(
        countryName: cleanCountryName(m['country_name'] ?? ''),
        countryCode: m['country_code'] ?? '',
        ip: m['ip'] ?? '',
        ping: (m['ping'] as num?)?.toInt() ?? 999,
        ovpnConfig: m['ovpn_config'] ?? '',
        numSessions: (m['num_sessions'] as num?)?.toInt() ?? 0,
        source: m['source'] == 'supabase'
            ? ServerSource.supabase
            : (src == ServerSource.supabase
                ? ServerSource.supabase
                : ServerSource.vpngate),
      );
}

// ─── VpnProvider ──────────────────────────────────────────────
class VpnProvider extends ChangeNotifier {
  // ✅ قائمتان منفصلتان
  final List<VpnServer> _vpngateServers = [];
  final List<VpnServer> _supabaseServers = [];

  List<VpnServer> get vpngateServers => _vpngateServers;
  List<VpnServer> get supabaseServers => _supabaseServers;

  // للتوافق مع الكود القديم
  List<VpnServer> get servers => [..._supabaseServers, ..._vpngateServers];

  VpnServer? _selected;
  VpnServer? get selectedServer => _selected;

  bool _loadingServers = false;
  bool get loadingServers => _loadingServers;

  String? _serversError;
  String? get serversError => _serversError;

  VPNStage _stage = VPNStage.disconnected;

  bool get isConnected => _stage == VPNStage.connected;
  bool get isConnecting =>
      _stage == VPNStage.connecting ||
      _stage == VPNStage.authenticating ||
      _stage == VPNStage.vpn_generate_config ||
      _stage == VPNStage.prepare;

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

  VpnServer? _lastSuccessfulServer;
  final List<String> _triedIps = [];
  final List<String> _trustedIps = [];

  bool _userDisconnected = false;
  bool _isSwitchingServer = false;
  bool _isReconnecting = false;
  bool get isReconnecting => _isReconnecting;

  static const int _timeoutSeconds = 20;
  static const int _pageSize = 20;

  // ✅ إصلاح ١: ما نتصل تلقائياً — بس نهيئ OpenVPN
  VpnProvider() {
    _initOpenVpn();
  }

  // ─── Init OpenVPN ──────────────────────────────────────────
  void _initOpenVpn() {
    _vpn = OpenVPN(
      onVpnStageChanged: (stage, _) {
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
            // ✅ إصلاح ٤: يكمل يجرب حتى يتصل
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
        if (status != null) {
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

  // ─── Connect To (OpenVPN فقط) ──────────────────────────────
  Future<void> connectTo(VpnServer server,
      {bool isAutoReconnect = false}) async {
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
      _tryNextServer();
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
          _tryNextServer();
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
      _tryNextServer();
    }
  }

  // ✅ إصلاح ٥: الدائرة = سيرفر عشوائي من أفضل السيرفرات
  Future<void> connectFastest() async {
    final all = [..._supabaseServers, ..._vpngateServers]
        .where((s) => s.ovpnConfig.isNotEmpty)
        .toList();

    if (all.isEmpty) {
      await fetchServers();
      final retried = [..._supabaseServers, ..._vpngateServers]
          .where((s) => s.ovpnConfig.isNotEmpty)
          .toList();
      if (retried.isNotEmpty) {
        await connectTo(retried.first);
      }
      return;
    }

    // اختار أفضل سيرفر (أقل ping)
    all.sort((a, b) => a.score.compareTo(b.score));
    await connectTo(all.first);
  }

  // ─── Disconnect ────────────────────────────────────────────
  Future<void> disconnect() async {
    _userDisconnected = true;
    _isSwitchingServer = false;
    _isReconnecting = false;
    _reconnectTimer?.cancel();
    _connectionTimeout?.cancel();
    _triedIps.clear();

    _vpn?.disconnect();
    _stage = VPNStage.disconnected;
    _selected = null;
    _statusMessage = '';
    _stopStats();
    notifyListeners();
  }

  // ─── Try Next Server ───────────────────────────────────────
  Future<void> _tryNextServer() async {
    final all = [..._supabaseServers, ..._vpngateServers]
        .where((s) => s.ovpnConfig.isNotEmpty && !_triedIps.contains(s.ip))
        .take(1)
        .toList();

    if (all.isNotEmpty) {
      await connectTo(all.first);
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

      final all = [..._supabaseServers, ..._vpngateServers]
          .where((s) => s.ovpnConfig.isNotEmpty && !_triedIps.contains(s.ip))
          .take(1)
          .toList();

      if (all.isNotEmpty) {
        _selected = all.first;
        _stage = VPNStage.prepare;
        _statusMessage = 'Connecting...';
        notifyListeners();
        await connectTo(all.first, isAutoReconnect: true);
      } else {
        _triedIps.clear();
        final restart = _lastSuccessfulServer ?? _selected;
        if (restart != null) {
          await connectTo(restart, isAutoReconnect: true);
        } else {
          _isReconnecting = false;
          _statusMessage = '';
          notifyListeners();
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

  // ─── Fetch Servers ─────────────────────────────────────────
  Future<void> fetchServers({bool forceRefresh = false}) async {
    _serversError = null;

    if (!forceRefresh) {
      final cached = CacheService.getCachedServers();
      if (cached != null && cached.isNotEmpty) {
        _applyCached(cached);
        _loadingServers = false;
        notifyListeners();
        if (!CacheService.isCacheValid) _backgroundRefresh();
        return;
      }
    }

    _loadingServers = true;
    _vpngateServers.clear();
    _supabaseServers.clear();
    notifyListeners();

    final results = await Future.wait([
      _fetchVpnGate(),
      _fetchSupabase().catchError((e) {
        debugPrint('❌ Supabase catchError: $e');
        return <VpnServer>[];
      }),
    ]);

    final vpngateList = results[0];
    final supabaseList = results[1];

    debugPrint('📊 VPNGate: ${vpngateList.length} | Supabase: ${supabaseList.length}');

    if (vpngateList.isNotEmpty || supabaseList.isNotEmpty) {
      _applyVpngate(vpngateList);
      _applySupabase(supabaseList);

      final allForCache = [
        ..._supabaseServers.map((s) => {...s.toMap(), 'source': 'supabase'}),
        ..._vpngateServers.map((s) => {...s.toMap(), 'source': 'vpngate'}),
      ];
      await CacheService.saveServers(allForCache);
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
      _applyVpngate(results[0]);
      _applySupabase(results[1]);
      final allForCache = [
        ..._supabaseServers.map((s) => {...s.toMap(), 'source': 'supabase'}),
        ..._vpngateServers.map((s) => {...s.toMap(), 'source': 'vpngate'}),
      ];
      await CacheService.saveServers(allForCache);
      notifyListeners();
    } catch (_) {}
  }

  void _applyCached(List<Map<String, dynamic>> cached) {
    _vpngateServers.clear();
    _supabaseServers.clear();
    for (final m in cached) {
      final src = m['source'] == 'supabase'
          ? ServerSource.supabase
          : ServerSource.vpngate;
      final s = VpnServer.fromMap(m, src: src);
      if (s.ovpnConfig.isEmpty || s.ping > 300) continue;
      if (src == ServerSource.supabase) {
        _supabaseServers.add(s);
      } else {
        _vpngateServers.add(s);
      }
    }
    _sortAndLimit(_vpngateServers);
    _sortAndLimit(_supabaseServers);
  }

  void _applyVpngate(List<VpnServer> list) {
    _vpngateServers.clear();
    final filtered = list
        .where((s) => s.ping <= 300 && s.ovpnConfig.isNotEmpty)
        .toList();
    _sortAndLimit(filtered);
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

  void _applySupabase(List<VpnServer> list) {
    _supabaseServers.clear();
    final filtered = list
        .where((s) => s.ping <= 300 && s.ovpnConfig.isNotEmpty)
        .toList();
    _sortAndLimit(filtered);
    final seenIps = <String>{};
    for (final s in filtered) {
      if (seenIps.contains(s.ip)) continue;
      seenIps.add(s.ip);
      _supabaseServers.add(s);
    }
  }

  void _sortAndLimit(List<VpnServer> list) {
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
        final res = await http
            .get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0'})
            .timeout(const Duration(seconds: 12));

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
  // ✅ إصلاح ٣: نجيب من Supabase بشكل صحيح
  Future<List<VpnServer>> _fetchSupabase() async {
    try {
      debugPrint('🔄 Fetching from Supabase...');
      final res = await Supabase.instance.client
          .from('servers')
          .select()
          .eq('is_active', true)
          .lte('ping', 300)
          .order('ping', ascending: true)
          .limit(80);

      debugPrint('📦 Supabase raw result count: ${(res as List).length}');

      final servers = (res)
          .map((r) => VpnServer.fromMap(
                Map<String, dynamic>.from(r),
                src: ServerSource.supabase,
              ))
          .where((s) => s.ovpnConfig.isNotEmpty)
          .toList();

      debugPrint('✅ Supabase servers after filter: ${servers.length}');
      return servers;
    } catch (e) {
      debugPrint('❌ Supabase fetch error: $e');
      return [];
    }
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _connectionTimeout?.cancel();
    _reconnectTimer?.cancel();
    super.dispose();
  }
}
