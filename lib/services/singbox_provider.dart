import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_singbox_client/flutter_singbox_client.dart';
import '../models/vpn_mode.dart';
import 'singbox_configs.dart';
import 'geo_service.dart';
import 'notification_service.dart';

enum VpnState { disconnected, connecting, connected, failed }

class SingboxProvider extends ChangeNotifier {

  VpnState        _state         = VpnState.disconnected;
  VpnMode         _mode          = VpnMode.warp;
  String          _status        = '';
  String          _downSpeed     = '0 B/s';
  String          _upSpeed       = '0 B/s';
  String?         _customUrl;
  Duration        _duration      = Duration.zero;
  List<String>    _excludedApps  = [];
  bool            _blockAds      = true;
  bool            _autoSpeedTest = true;

  VpnState     get state         => _state;
  VpnMode      get mode          => _mode;
  String       get status        => _status;
  String       get downSpeed     => _downSpeed;
  String       get upSpeed       => _upSpeed;
  String?      get customUrl     => _customUrl;
  Duration     get duration      => _duration;
  List<String> get excludedApps  => _excludedApps;
  bool         get blockAds      => _blockAds;
  bool         get autoSpeedTest => _autoSpeedTest;

  bool get isConnected  => _state == VpnState.connected;
  bool get isConnecting => _state == VpnState.connecting;
  bool get isFailed     => _state == VpnState.failed;

  // ─── الـ API الصحيح: SingboxClient ───────────────────────
  final _client = SingboxClient();
  Timer? _statsTimer;
  Timer? _verifyTimer;
  DateTime? _connectedAt;

  static const _prefCustomUrl    = 'custom_url';
  static const _prefExcludedApps = 'excluded_apps';
  static const _prefBlockAds     = 'block_ads';
  static const _prefAutoSpeed    = 'auto_speed_test';

  SingboxProvider() { _init(); }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _customUrl     = prefs.getString(_prefCustomUrl);
    _blockAds      = prefs.getBool(_prefBlockAds)    ?? true;
    _autoSpeedTest = prefs.getBool(_prefAutoSpeed)   ?? true;

    final saved = prefs.getStringList(_prefExcludedApps);
    if (saved != null) _excludedApps = saved;

    // تهيئة المكتبة
    await _client.initialize();

    // نحمل الدولة
    await GeoService.load();
    _mode = _bestMode();

    // نستمع للأحداث
    _client.serviceStateStream.listen(_onStateChanged);
    _client.trafficStatsStream.listen(_onTraffic);
    _client.faultStream.listen((err) {
      debugPrint('SingBox fault: $err');
      _setFailed(err.toString());
    });

    notifyListeners();
  }

  VpnMode _bestMode() {
    switch (GeoService.recommendedMode) {
      case 'psiphon': return VpnMode.psiphon;
      default:        return VpnMode.warp;
    }
  }

  // ─── Settings ─────────────────────────────────────────────
  void selectMode(VpnMode m) {
    if (_state != VpnState.disconnected) return;
    _mode = m;
    notifyListeners();
  }

  Future<void> setCustomUrl(String url) async {
    _customUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCustomUrl, _customUrl!);
    notifyListeners();
  }

  Future<void> addExcludedApp(String pkg) async {
    if (!_excludedApps.contains(pkg)) {
      _excludedApps = [..._excludedApps, pkg];
      await _saveExcluded();
      notifyListeners();
    }
  }

  Future<void> removeExcludedApp(String pkg) async {
    _excludedApps = _excludedApps.where((a) => a != pkg).toList();
    await _saveExcluded();
    notifyListeners();
  }

  Future<void> _saveExcluded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefExcludedApps, _excludedApps);
  }

  Future<void> setBlockAds(bool v) async {
    _blockAds = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefBlockAds, v);
    notifyListeners();
  }

  Future<void> setAutoSpeedTest(bool v) async {
    _autoSpeedTest = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoSpeed, v);
    notifyListeners();
  }

  // ─── Connect / Disconnect ─────────────────────────────────
  Future<void> connect() async {
    if (_state == VpnState.connecting || _state == VpnState.connected) {
      await disconnect();
      return;
    }

    _state  = VpnState.connecting;
    _status = 'Connecting...';
    notifyListeners();

    try {
      final config = await _buildConfig();
      if (config == null) { _setFailed('No config available'); return; }

      // طلب صلاحية VPN
      if (!await _client.requestVPNPermission()) {
        _setFailed('VPN permission denied');
        return;
      }

      // الاتصال بالـ API الصحيح
      await _client.connect(SessionOptions(
        config: config,
        networkMode: NetworkMode.vpn,
        perAppProxy: PerAppProxyOptions(
          mode: _excludedApps.isEmpty
              ? PerAppProxyMode.off
              : PerAppProxyMode.exclude,
          packages: _excludedApps,
        ),
        notification: NotificationConfig(
          title: 'OnyxVPN',
          showTrafficStats: true,
          showStopButton: true,
          stopButtonLabel: 'Disconnect',
        ),
      ));

    } catch (e) {
      debugPrint('Connect error: $e');
      _setFailed('Connection failed');
    }
  }

  Future<void> disconnect() async {
    _verifyTimer?.cancel();
    _statsTimer?.cancel();
    await _client.disconnect();
    _connectedAt = null;
    _state     = VpnState.disconnected;
    _status    = '';
    _duration  = Duration.zero;
    _downSpeed = '0 B/s';
    _upSpeed   = '0 B/s';
    await NotificationService.hide();
    notifyListeners();
  }

  // ─── Build Config ─────────────────────────────────────────
  Future<String?> _buildConfig() async {
    final country = GeoService.userCountryCode.toLowerCase().isNotEmpty
        ? GeoService.userCountryCode.toLowerCase()
        : 'iq';

    switch (_mode) {
      case VpnMode.warp:
        return SingboxConfigs.warp(countryCode: country, excludedApps: _excludedApps);
      case VpnMode.psiphon:
        return SingboxConfigs.psiphon(countryCode: country, excludedApps: _excludedApps);
      case VpnMode.mahsa:
        return await _fetchAndBuild(SingboxConfigs.mahsaUrl, countryCode: country, excludedApps: _excludedApps);
      case VpnMode.custom:
        if (_customUrl == null || _customUrl!.isEmpty) return null;
        return await _fetchAndBuild(_customUrl!, countryCode: country, excludedApps: _excludedApps);
    }
  }

  Future<String?> _fetchAndBuild(String url, {required String countryCode, required List<String> excludedApps}) async {
    try {
      _status = 'Fetching servers...';
      notifyListeners();

      final res = await http.get(Uri.parse(url), headers: {'User-Agent': 'sing-box/1.0'})
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return null;
      final body = res.body.trim();

      if (body.startsWith('{')) return body;

      try {
        final decoded = utf8.decode(base64.decode(body + '=' * ((4 - body.length % 4) % 4)));
        if (decoded.startsWith('{')) return decoded;
        return _linksToConfig(decoded.split('\n'), countryCode: countryCode, excludedApps: excludedApps);
      } catch (_) {}

      return _linksToConfig(body.split('\n'), countryCode: countryCode, excludedApps: excludedApps);
    } catch (e) {
      debugPrint('Fetch error: $e');
      return null;
    }
  }

  String? _linksToConfig(List<String> lines, {required String countryCode, required List<String> excludedApps}) {
    final outbounds = <Map<String, dynamic>>[];
    for (final line in lines) {
      final l = line.trim();
      if (l.isEmpty) continue;
      final o = _parseLink(l);
      if (o != null) outbounds.add(o);
      if (outbounds.length >= 5) break;
    }
    if (outbounds.isEmpty) return null;
    return SingboxConfigs.mahsaConfig(outbounds: outbounds, countryCode: countryCode, excludedApps: excludedApps);
  }

  Map<String, dynamic>? _parseLink(String link) {
    try {
      final uri = Uri.parse(link);
      final tag = uri.fragment.isNotEmpty ? uri.fragment : 'srv-${link.hashCode.abs()}';

      if (link.startsWith('vless://')) {
        final p = uri.queryParameters;
        return {
          'type': 'vless', 'tag': tag, 'server': uri.host, 'server_port': uri.port,
          'uuid': uri.userInfo, 'flow': p['flow'] ?? '',
          'tls': {
            'enabled': p['security'] == 'tls' || p['security'] == 'reality',
            'server_name': p['sni'] ?? p['host'] ?? uri.host,
            if (p['security'] == 'reality') 'reality': {'enabled': true, 'public_key': p['pbk'] ?? '', 'short_id': p['sid'] ?? ''},
            'utls': {'enabled': true, 'fingerprint': p['fp'] ?? 'chrome'},
          },
          'transport': _parseTransport(p),
          'packet_encoding': 'xudp',
        };
      }
      if (link.startsWith('trojan://')) {
        final p = uri.queryParameters;
        return {
          'type': 'trojan', 'tag': tag, 'server': uri.host, 'server_port': uri.port,
          'password': uri.userInfo,
          'tls': {'enabled': true, 'server_name': p['sni'] ?? uri.host, 'utls': {'enabled': true, 'fingerprint': p['fp'] ?? 'chrome'}},
        };
      }
      if (link.startsWith('vmess://')) {
        final decoded = jsonDecode(utf8.decode(base64.decode(link.substring(8) + '=' * ((4 - link.substring(8).length % 4) % 4))));
        return {
          'type': 'vmess', 'tag': decoded['ps'] ?? tag, 'server': decoded['add'],
          'server_port': int.tryParse(decoded['port'].toString()) ?? 443,
          'uuid': decoded['id'], 'alter_id': int.tryParse(decoded['aid'].toString()) ?? 0,
          'security': decoded['scy'] ?? 'auto', 'tls': {'enabled': decoded['tls'] == 'tls'},
          if (decoded['net'] != 'tcp') 'transport': {'type': decoded['net'], 'path': decoded['path'] ?? '/', if (decoded['host'] != null) 'headers': {'Host': decoded['host']}},
        };
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic>? _parseTransport(Map<String, String> p) {
    final type = p['type'];
    if (type == null || type == 'tcp') return null;
    if (type == 'ws') return {'type': 'ws', 'path': p['path'] ?? '/', if (p['host'] != null) 'headers': {'Host': p['host']}};
    if (type == 'grpc') return {'type': 'grpc', 'service_name': p['serviceName'] ?? ''};
    return {'type': type};
  }

  // ─── Callbacks من المكتبة ─────────────────────────────────
  void _onStateChanged(ServiceState state) {
    switch (state) {
      case ServiceState.connected:
        _state       = VpnState.connected;
        _status      = '';
        _connectedAt = DateTime.now();
        _verifyTimer?.cancel();
        _verifyTimer = Timer(const Duration(seconds: 3), _verifyAndFallback);
        _startTimer();
        NotificationService.showConnected(
          modeName: _mode.name,
          modeEmoji: VpnModeInfo.all.firstWhere((i) => i.mode == _mode).emoji,
        );
        break;
      case ServiceState.disconnected:
        if (_state == VpnState.connecting) {
          _setFailed('Connection failed');
        } else {
          _state  = VpnState.disconnected;
          _status = '';
        }
        _statsTimer?.cancel();
        _connectedAt = null;
        break;
      case ServiceState.connecting:
        _state  = VpnState.connecting;
        _status = 'Connecting...';
        break;
      default:
        break;
    }
    notifyListeners();
  }

  void _onTraffic(TrafficStats stats) {
    _downSpeed = _formatSpeed(stats.downlinkBps);
    _upSpeed   = _formatSpeed(stats.uplinkBps);
    notifyListeners();
  }

  // ─── فحص الاتصال الحقيقي ─────────────────────────────────
  Future<void> _verifyAndFallback() async {
    final works = await _verifyConnection();
    if (!works && _state == VpnState.connected) {
      await disconnect();
      if (_mode == VpnMode.warp) {
        _mode   = VpnMode.psiphon;
        _status = 'Warp failed, trying Psiphon...';
        notifyListeners();
        await Future.delayed(const Duration(seconds: 1));
        await connect();
      } else {
        _setFailed('Server unreachable, try another mode');
      }
    }
  }

  Future<bool> _verifyConnection() async {
    const urls = ['https://www.google.com/generate_204', 'https://connectivitycheck.gstatic.com/generate_204'];
    for (final url in urls) {
      try {
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
        if (res.statusCode == 204 || res.statusCode == 200) return true;
      } catch (_) { continue; }
    }
    return false;
  }

  void _setFailed(String msg) {
    _state  = VpnState.failed;
    _status = msg;
    _statsTimer?.cancel();
    notifyListeners();
  }

  void _startTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_connectedAt != null) {
        _duration = DateTime.now().difference(_connectedAt!);
        notifyListeners();
      }
    });
  }

  String get formattedTime {
    final h = _duration.inHours.toString().padLeft(2, '0');
    final m = _duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatSpeed(int bps) {
    final bytes = bps ~/ 8;
    if (bytes <= 0) return '0 B/s';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB/s';
    return '$bytes B/s';
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _verifyTimer?.cancel();
    super.dispose();
  }
}
