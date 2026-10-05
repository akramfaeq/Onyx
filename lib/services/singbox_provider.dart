import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vpn_mode.dart';
import 'v2ray_configs.dart';
import 'warp_service.dart';
import 'mahsa_service.dart';
import 'geo_service.dart';

export 'v2ray_configs.dart';

enum VpnState { disconnected, connecting, connected, failed }

class SingboxProvider extends ChangeNotifier {

  // ─── Channels ─────────────────────────────────────────────
  static const _method = MethodChannel('com.onyxvpn/vpn');
  static const _events = EventChannel('com.onyxvpn/status');

  // ─── State ────────────────────────────────────────────────
  VpnState     _state        = VpnState.disconnected;
  VpnMode      _mode         = VpnMode.warp;
  String       _status       = '';
  String       _downSpeed    = '0 B/s';
  String       _upSpeed      = '0 B/s';
  String?      _customUrl;
  Duration     _duration     = Duration.zero;
  List<String> _excludedApps = [];
  bool         _blockAds       = true;
  bool         _autoSpeedTest  = false;

  VpnState     get state        => _state;
  VpnMode      get mode         => _mode;
  String       get status       => _status;
  String       get downSpeed    => _downSpeed;
  String       get upSpeed      => _upSpeed;
  String?      get customUrl    => _customUrl;
  Duration     get duration     => _duration;
  List<String> get excludedApps => _excludedApps;
  bool         get blockAds      => _blockAds;
  bool         get autoSpeedTest => _autoSpeedTest;

  bool get isConnected  => _state == VpnState.connected;
  bool get isConnecting => _state == VpnState.connecting;
  bool get isFailed     => _state == VpnState.failed;

  Timer?              _durationTimer;
  Timer?              _statsTimer;
  DateTime?           _connectedAt;
  StreamSubscription? _statusSub;

  static const _prefCustomUrl    = 'custom_url';
  static const _prefExcludedApps = 'excluded_apps';
  static const _prefBlockAds     = 'block_ads';
  static const _prefLastConfig    = 'last_config_v2';
  static const _prefAutoSpeedTest = 'auto_speed_test';

  SingboxProvider() { _init(); }

  Future<void> _init() async {
    final prefs   = await SharedPreferences.getInstance();
    _customUrl    = prefs.getString(_prefCustomUrl);
    _blockAds      = prefs.getBool(_prefBlockAds) ?? true;
    _autoSpeedTest = prefs.getBool(_prefAutoSpeedTest) ?? false;
    final saved   = prefs.getStringList(_prefExcludedApps);
    if (saved != null) _excludedApps = saved;

    try {
      await _method.invokeMethod('setup', {'grpcPort': 9090});
    } catch (e) {
      debugPrint('setup error: $e');
    }

    _statusSub = _events.receiveBroadcastStream().listen(_onNativeStatus);

    await GeoService.load();
    _mode = _bestMode();
    WarpService.getKeys();
    MahsaService.getLinks();

    notifyListeners();
  }

  VpnMode _bestMode() {
    switch (GeoService.recommendedMode) {
      case 'psiphon': return VpnMode.psiphon;
      default:        return VpnMode.warp;
    }
  }

  // ─── Native Status Handler ────────────────────────────────
  void _onNativeStatus(dynamic event) {
    final s = event.toString();
    debugPrint('native status: $s');

    if (s == 'connected') {
      _state       = VpnState.connected;
      _status      = '';
      _connectedAt ??= DateTime.now();
      _startTimer();
      _startStatsTimer();
    } else if (s == 'disconnected') {
      _state       = VpnState.disconnected;
      _status      = '';
      _stopTimers();
      _connectedAt = null;
      _downSpeed   = '0 B/s';
      _upSpeed     = '0 B/s';
    } else if (s.startsWith('failed')) {
      final msg = s.contains(':') ? s.split(':').skip(1).join(':') : 'Connection failed';
      _setFailed(msg.trim());
    } else if (s == 'permission_requested') {
      _status = 'Waiting for permission...';
    } else if (s.startsWith('stats:')) {
      _parseStats(s.substring(6));
    }
    notifyListeners();
  }

  // ─── Stats Polling ────────────────────────────────────────
  void _startStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!isConnected) { _statsTimer?.cancel(); return; }
      try {
        final result = await _method.invokeMethod('getStats');
        if (result is Map) {
          final down = result['down'] as int? ?? 0;
          final up   = result['up']   as int? ?? 0;
          _downSpeed = _formatSpeed(down);
          _upSpeed   = _formatSpeed(up);
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  void _parseStats(String raw) {
    try {
      final parts = raw.split(':');
      if (parts.length >= 2) {
        _downSpeed = _formatSpeed(int.tryParse(parts[0]) ?? 0);
        _upSpeed   = _formatSpeed(int.tryParse(parts[1]) ?? 0);
      }
    } catch (_) {}
  }

  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec < 1024)        return '$bytesPerSec B/s';
    if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  // ─── Connect / Disconnect ─────────────────────────────────
  Future<void> connect() async {
    if (_state == VpnState.connecting || _state == VpnState.connected) {
      await disconnect();
      return;
    }

    _state  = VpnState.connecting;
    _status = 'Building config...';
    notifyListeners();

    try {
      final cc = GeoService.userCountryCode.toLowerCase().isNotEmpty
          ? GeoService.userCountryCode.toLowerCase()
          : 'iq';

      final config = await _buildConfig(cc);
      if (config == null || config.isEmpty) {
        _setFailed('No servers available');
        return;
      }

      await _saveLastConfig(config);

      _status = 'Connecting...';
      notifyListeners();

      final result = await _method.invokeMethod('start', {'config': config});
      debugPrint('start result: $result');

    } on PlatformException catch (e) {
      debugPrint('PlatformException: ${e.code} — ${e.message}');
      _setFailed('${e.message}');
    } catch (e) {
      debugPrint('connect error: $e');
      _setFailed('Error: $e');
    }
  }

  Future<void> disconnect() async {
    try {
      await _method.invokeMethod('stop');
    } catch (e) {
      debugPrint('disconnect error: $e');
    }
    _stopTimers();
    _connectedAt = null;
    _state     = VpnState.disconnected;
    _status    = '';
    _duration  = Duration.zero;
    _downSpeed = '0 B/s';
    _upSpeed   = '0 B/s';
    notifyListeners();
  }

  // ─── Last Config (Reboot Recovery) ───────────────────────
  Future<void> _saveLastConfig(String config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLastConfig, config);
  }

  Future<String?> getLastConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefLastConfig);
  }

  // ─── Build Config ─────────────────────────────────────────
  Future<String?> _buildConfig(String cc) async {
    switch (_mode) {
      case VpnMode.warp:
        _status = 'Fetching Warp keys...';
        notifyListeners();
        return await V2RayConfigs.warp(
          countryCode: cc,
          excludedApps: _excludedApps,
          blockAds: _blockAds,
        );

      case VpnMode.psiphon:
        _status = 'Building Psiphon config...';
        notifyListeners();
        return await V2RayConfigs.psiphon(
          countryCode: cc,
          excludedApps: _excludedApps,
          blockAds: _blockAds,
        );

      case VpnMode.warpPsiphon:
        _status = 'Fetching Warp keys...';
        notifyListeners();
        return await V2RayConfigs.warpViaPsiphon(
          countryCode: cc,
          excludedApps: _excludedApps,
          blockAds: _blockAds,
        );

      case VpnMode.mahsa:
        _status = 'Fetching Mahsa servers...';
        notifyListeners();
        return await V2RayConfigs.mahsa(
          countryCode: cc,
          excludedApps: _excludedApps,
          blockAds: _blockAds,
        );

      case VpnMode.custom:
        if (_customUrl == null || _customUrl!.isEmpty) return null;
        _status = 'Fetching custom servers...';
        notifyListeners();
        return await V2RayConfigs.custom(
          url: _customUrl!,
          countryCode: cc,
          excludedApps: _excludedApps,
          blockAds: _blockAds,
        );
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
    await prefs.setBool(_prefAutoSpeedTest, v);
    notifyListeners();
  }

  Future<void> refreshWarpKeys() async {
    await WarpService.clearKeys();
    await WarpService.getKeys(forceRefresh: true);
  }

  Future<void> refreshMahsa() async {
    await MahsaService.clearCache();
    await MahsaService.getLinks();
  }

  // ─── Timers ───────────────────────────────────────────────
  void _startTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_connectedAt != null) {
        _duration = DateTime.now().difference(_connectedAt!);
        notifyListeners();
      }
    });
  }

  void _stopTimers() {
    _durationTimer?.cancel();
    _statsTimer?.cancel();
    _durationTimer = null;
    _statsTimer    = null;
    _duration      = Duration.zero;
  }

  void _setFailed(String msg) {
    _state  = VpnState.failed;
    _status = msg;
    _stopTimers();
    notifyListeners();
  }

  String get formattedTime {
    final h = _duration.inHours.toString().padLeft(2, '0');
    final m = _duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _stopTimers();
    super.dispose();
  }
}
