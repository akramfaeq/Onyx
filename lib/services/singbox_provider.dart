import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vpn_mode.dart';
import 'v2ray_configs.dart';
import 'warp_service.dart';
import 'mahsa_service.dart';
import 'geo_service.dart';
import 'ads_service.dart';
import 'patterniha_service.dart';

export 'v2ray_configs.dart';

enum VpnState { disconnected, connecting, connected, failed }

class SingboxProvider extends ChangeNotifier {

  // â”€â”€â”€ Channels â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static const _method = MethodChannel('com.onyxvpn/vpn');
  static const _events = EventChannel('com.onyxvpn/status');

  // â”€â”€â”€ State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  VpnState     _state        = VpnState.disconnected;
  VpnMode      _mode         = VpnMode.warp;
  String       _status       = '';
  String       _downSpeed    = '0 B/s';
  String       _upSpeed      = '0 B/s';
  String?      _customUrl;
  Duration     _duration     = Duration.zero;
  List<String> _excludedApps = [];
  bool         _blockAds     = true;
  bool         _autoSpeedTest = false;

  // â”€â”€â”€ Connected Country (IP lookup after connect) â”€â”€â”€â”€â”€â”€â”€â”€â”€
  String _connectedCountry = '';
  String _connectedFlag    = '';
  String _connectedIp      = '';

  String get connectedCountry => _connectedCountry;
  String get connectedFlag    => _connectedFlag;
  String get connectedIp      => _connectedIp;

  // â”€â”€â”€ Custom Subscription servers (Ù†ÙØ³ Ù‡Ø§ÙŠØ¯ÙØ§ÙŠ) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<VpnServer> _servers        = [];
  VpnServer?      _selectedServer;
  bool            _loadingServers = false;

  // Ù„Ùˆ Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù… ØºÙŠÙ‘Ø± Ø§Ù„Ù€ mode ÙŠØ¯ÙˆÙŠØ§Ù‹ â†’ Ù…Ø§ Ù†ØºÙŠØ±Ù‡ ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹
  bool _userChangedMode = false;

  // Ù„Ùˆ Ø§Ù„ÙØµÙ„ Ø¬Ø§Ø¡ Ù…Ù† Ø§Ù„Ù€ ad timer â†’ Ù†Ø¹ÙŠØ¯ Ø§Ù„Ø§ØªØµØ§Ù„ ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹ Ø¨Ø¹Ø¯ Ø§Ù„ÙØµÙ„
  bool _pendingAdReconnect = false;

  VpnState        get state          => _state;
  VpnMode         get mode           => _mode;
  String          get status         => _status;
  String          get downSpeed      => _downSpeed;
  String          get upSpeed        => _upSpeed;
  String?         get customUrl      => _customUrl;
  Duration        get duration       => _duration;
  List<String>    get excludedApps   => _excludedApps;
  bool            get blockAds       => _blockAds;
  bool            get autoSpeedTest  => _autoSpeedTest;
  List<VpnServer> get servers        => _servers;
  VpnServer?      get selectedServer => _selectedServer;
  bool            get loadingServers => _loadingServers;

  bool get isConnected  => _state == VpnState.connected;
  bool get isConnecting => _state == VpnState.connecting;
  bool get isFailed     => _state == VpnState.failed;

  Timer?              _durationTimer;
  Timer?              _statsTimer;
  DateTime?           _connectedAt;
  StreamSubscription? _statusSub;
  int _connectionRevision = 0;

  // â”€â”€â”€ Ù…ÙØ§ØªÙŠØ­ SharedPreferences â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static const _prefCustomUrl     = 'custom_url';
  static const _prefExcludedApps  = 'excluded_apps';
  static const _prefBlockAds      = 'block_ads';
  static const _prefAutoSpeedTest = 'auto_speed_test';
  // Ø§Ù„ÙƒÙˆÙ†ÙÙŠØº Ø§Ù„ÙƒØ§Ù…Ù„ + ÙˆÙ‚Øª Ø­ÙØ¸Ù‡ (Ù†ÙØ³ Ù…Ù†Ù‡Ø¬ÙŠØ© Ù‡Ø§ÙŠØ¯ÙØ§ÙŠ)
  static const _prefLastConfig    = 'last_config_v2';
  static const _prefLastConfigAt  = 'last_config_saved_at';
  static const _prefLastConfigMode = 'last_config_mode';
  static const _configMaxAgeHours = 6; // Ù†ÙØ³ Ù‡Ø§ÙŠØ¯ÙØ§ÙŠ

  SingboxProvider() { _init(); }

  Future<void> _init() async {
    final prefs    = await SharedPreferences.getInstance();
    _customUrl     = prefs.getString(_prefCustomUrl);
    _blockAds      = prefs.getBool(_prefBlockAds) ?? true;
    _autoSpeedTest = prefs.getBool(_prefAutoSpeedTest) ?? false;
    final saved    = prefs.getStringList(_prefExcludedApps);
    if (saved != null) _excludedApps = saved;

    try {
      await _method.invokeMethod('setup', {'grpcPort': 9090});
    } catch (e) {
      debugPrint('setup error: $e');
    }

    _statusSub = _events.receiveBroadcastStream().listen(_onNativeStatus);

    await GeoService.load();
    _mode = _bestMode();

    // â”€â”€â”€ ØªÙ‡ÙŠØ¦Ø© Ø§Ù„Ø¥Ø´Ø¹Ø§Ø±Ø§Øª â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    // â”€â”€â”€ ØªØ­Ù…ÙŠÙ„ ØµØ§Ù…Øª ÙÙŠ Ø§Ù„Ø®Ù„ÙÙŠØ© â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    WarpService.getKeys();
    MahsaService.backgroundRefresh();
    PatternihaService.backgroundRefresh(); // تجديد صامت في الخلفية (24 ساعة)

    // â”€â”€â”€ Ø¬Ù„Ø¨ Ø³ÙŠØ±ÙØ±Ø§Øª Onyx Ù…Ù† GitHub â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    loadOnyxServers();

    notifyListeners();
  }

  VpnMode _bestMode() {
    // Ø¯ÙˆÙ„ Ù…Ø­Ø¬ÙˆØ¨Ø© ØªÙ…Ø§Ù…Ø§Ù‹ â†’ Warp+Psiphon Ø£Ù‚ÙˆÙ‰ Ø®ÙŠØ§Ø±
    if (GeoService.isRestrictedCountry) return VpnMode.warpPsiphon;

    // Ø¨Ø§Ù‚ÙŠ Ø§Ù„Ø¯ÙˆÙ„ (Ø¨Ù…Ø§ ÙÙŠÙ‡Ø§ Ø§Ù„Ø¹Ø±Ø§Ù‚ ÙˆØ§Ù„Ø¯ÙˆÙ„ Ø§Ù„Ø¬Ø²Ø¦ÙŠØ©) â†’ Mahsa Ø£Ø³Ø±Ø¹
    return VpnMode.mahsa;
  }
  // â”€â”€â”€ Native Status Handler â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _onNativeStatus(dynamic event) {
    final s = event.toString();
    debugPrint('native status: $s');

    if (s == 'connected') {
      _state       = VpnState.connected;
      _status      = '';
      _connectedAt ??= DateTime.now();
      _startTimer();
      _startStatsTimer();
      _fetchConnectedCountry();

      // â”€â”€â”€ Ø¥Ø´Ø¹Ø§Ø±: Ù…ØªØµÙ„ â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

      // â”€â”€â”€ Ø¥Ø¹Ù„Ø§Ù† ÙƒÙ„ Ø³Ø§Ø¹Ø©: ÙØµÙ„ â†’ Ø¥Ø¹Ù„Ø§Ù† â†’ Ø¥Ø¹Ø§Ø¯Ø© Ø§ØªØµØ§Ù„ â”€â”€â”€â”€â”€
      AdsService.startHourlyAdTimer(
        onDisconnect: disconnect,
        onReconnect: () async {
          // Ù†Ø­Ø· Ø§Ù„ÙÙ„Ø§Ù‚ ÙˆÙ†Ø³ØªÙ†Ù‰ Ø§Ù„Ù€ disconnected event ÙŠØ¬ÙŠ Ù…Ù† Ø§Ù„Ù€ native
          // Ø¨Ø¹Ø¯ÙŠÙ† _onNativeStatus ÙŠØªØµÙ„ ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹
          _pendingAdReconnect = true;
        },
      );

      // â”€â”€â”€ Ø¥Ø¹Ù„Ø§Ù† Ø¨Ø¹Ø¯ Ø§Ù„Ø§ØªØµØ§Ù„ Ø§Ù„Ù†Ø§Ø¬Ø­ â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    } else if (s == 'disconnected') {
      _state            = VpnState.disconnected;
      _status           = '';
      _stopTimers();
      _connectedAt      = null;
      _downSpeed        = '0 B/s';
      _upSpeed          = '0 B/s';
      _connectedCountry = '';
      _connectedFlag    = '';
      _connectedIp      = '';

      // â”€â”€â”€ Ø¥Ø´Ø¹Ø§Ø±: Ø§Ù†Ù‚Ø·Ø¹ + Ø¥ÙŠÙ‚Ø§Ù timer Ø§Ù„Ø¥Ø¹Ù„Ø§Ù†Ø§Øª â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      AdsService.stopHourlyAdTimer();

      // â”€â”€â”€ Ø¥Ø¹Ø§Ø¯Ø© Ø§ØªØµØ§Ù„ ØªÙ„Ù‚Ø§Ø¦ÙŠØ© Ø¨Ø¹Ø¯ Ø¥Ø¹Ù„Ø§Ù† Ø§Ù„Ù€ ad timer â”€â”€â”€â”€
      if (_pendingAdReconnect) {
        _pendingAdReconnect = false;
        // Ù†Ø³ØªÙ†Ù‰ Ø´ÙˆÙŠØ© Ø¨Ø¹Ø¯ Ø§Ù„ÙØµÙ„ Ø§Ù„ÙƒØ§Ù…Ù„ Ù‚Ø¨Ù„ Ø§Ù„Ø§ØªØµØ§Ù„
        Future.delayed(const Duration(milliseconds: 800), () {
          if (_state == VpnState.disconnected) {
            connect();
          }
        });
      }

    } else if (s.startsWith('failed')) {
      final msg = s.contains(':') ? s.split(':').skip(1).join(':') : 'Connection failed';
      _setFailed(_friendlyConnectionError(msg.trim()));
      AdsService.stopHourlyAdTimer();
    } else if (s == 'permission_requested') {
      _status = 'Waiting for permission...';
    } else if (s.startsWith('stats:')) {
      _parseStats(s.substring(6));
    }
    notifyListeners();
  }

  // â”€â”€â”€ Connected Country Lookup â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _fetchConnectedCountry() async {
    const apis = [
      'https://ipapi.co/json/',
      'https://ip-api.com/json/?fields=countryCode,country,query',
      'https://ipwho.is/?fields=country_code,country,ip',
    ];
    for (final url in apis) {
      try {
        final res = await http.get(Uri.parse(url))
            .timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final j    = jsonDecode(res.body) as Map<String, dynamic>;
          final code = (j['country_code'] ?? j['countryCode'] ?? '').toString().toUpperCase();
          final name = (j['country'] ?? j['country_name'] ?? '').toString();
          final ip   = (j['ip'] ?? j['query'] ?? '').toString();
          if (code.isNotEmpty) {
            _connectedCountry = name.isNotEmpty ? name : code;
            _connectedFlag    = _codeToFlag(code);
            _connectedIp      = ip;
            notifyListeners();
            return;
          }
        }
      } catch (_) { continue; }
    }
  }

  static String _codeToFlag(String code) {
    if (code.length != 2) return 'ðŸŒ';
    final base = 0x1F1E6 - 0x41;
    final chars = code.toUpperCase().codeUnits;
    return String.fromCharCode(base + chars[0]) + String.fromCharCode(base + chars[1]);
  }

  // â”€â”€â”€ Stats Polling â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

  Future<void> connectWithMode(
    VpnMode mode, {
    VpnServer? onyxServer,
    VpnServer? customServer,
  }) async {
    final request = ++_connectionRevision;
    if (_state != VpnState.disconnected) await _stopConnection();
    if (request != _connectionRevision) return;

    _mode = mode;
    _userChangedMode = true;
    if (mode == VpnMode.pythonServers) _selectedOnyxServer = onyxServer;
    if (mode == VpnMode.custom) _selectedServer = customServer;

    await _clearConfigCache();
    if (request != _connectionRevision) return;
    notifyListeners();
    await _connect(request);
  }
  // â”€â”€â”€ Connect / Disconnect â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> connect() async {
    if (_state == VpnState.connecting || _state == VpnState.connected) {
      // Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù… Ø¶ØºØ· ÙˆÙ‡Ùˆ Ù…ØªØµÙ„ â†’ ÙØµÙ„ + Ø§ØªØµØ§Ù„ ØªÙ„Ù‚Ø§Ø¦ÙŠ
      _pendingAdReconnect = false; // Ø¥Ù„ØºØ§Ø¡ Ø£ÙŠ reconnect Ù‚Ø§Ø¯Ù… Ù…Ù† Ø§Ù„Ù€ ad timer
      await disconnect();
      return;
    }
    // Ù„Ùˆ ÙØ´Ù„ Ø³Ø§Ø¨Ù‚Ø§Ù‹ â†’ Ø§Ù…Ø³Ø­ Ø§Ù„ÙƒØ§Ø´ ÙˆØ­Ø§ÙˆÙ„ Ù…Ø¬Ø¯Ø¯Ø§Ù‹
    if (_state == VpnState.failed) await _clearConfigCache();
    await _connect(++_connectionRevision);
  }

  Future<void> _connect(int request) async {
    // â”€â”€â”€ Ø§Ø®ØªÙŠØ§Ø± ØªÙ„Ù‚Ø§Ø¦ÙŠ Ù„Ø£ÙØ¶Ù„ mode Ø­Ø³Ø¨ Ø§Ù„Ø¨Ù„Ø¯ â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // ÙÙ‚Ø· Ù„Ùˆ Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù… Ù…Ø§ ØºÙŠÙ‘Ø± Ø§Ù„Ù€ mode ÙŠØ¯ÙˆÙŠØ§Ù‹
    if (!_userChangedMode) {
      final auto = _bestMode();
      if (_mode != auto) {
        _mode = auto;
        debugPrint('SingboxProvider: auto-selected mode â†’ $auto');
      }
    }

    _state  = VpnState.connecting;
    _status = 'Preparing...';
    notifyListeners();

    try {
      final cc = GeoService.userCountryCode.toLowerCase().isNotEmpty
          ? GeoService.userCountryCode.toLowerCase()
          : 'iq';

      // â”€â”€â”€ Ù†ÙØ³ Ù…Ù†Ù‡Ø¬ÙŠØ© Ù‡Ø§ÙŠØ¯ÙØ§ÙŠ: Ù‚Ø±Ø£ Ø§Ù„ÙƒÙˆÙ†ÙÙŠØº Ù…Ù† Ø§Ù„ÙƒØ§Ø´ Ø£ÙˆÙ„Ø§Ù‹ â”€â”€
      String? config = await _loadCachedConfig();

      if (config != null) {
        // ÙƒØ§Ø´ Ù…ÙˆØ¬ÙˆØ¯ ÙˆØ­Ø¯ÙŠØ« â†’ Ø§ØªØµØ§Ù„ ÙÙˆØ±ÙŠ Ø¨Ø¯ÙˆÙ† Ø´Ø¨ÙƒØ©
        debugPrint('SingboxProvider: using cached config');
        _status = 'Connecting...';
        notifyListeners();
      } else {
        // Ù„Ø§ ÙƒØ§Ø´ â†’ Ø§Ø¨Ù†Ù ÙƒÙˆÙ†ÙÙŠØº Ø¬Ø¯ÙŠØ¯ Ù…Ù† Ø§Ù„Ø´Ø¨ÙƒØ©
        debugPrint('SingboxProvider: building fresh config');
        _status = 'Fetching servers...';
        notifyListeners();
        config = await _buildConfig(cc);

        if (request != _connectionRevision) return;

        if (config == null || config.isEmpty) {
          _setFailed('No servers available');
          return;
        }
        // Ø§Ø­ÙØ¸ Ø§Ù„ÙƒÙˆÙ†ÙÙŠØº Ø§Ù„Ø¬Ø¯ÙŠØ¯ (Ù†ÙØ³ Ù…Ø§ ÙŠÙØ¹Ù„Ù‡ Ù‡Ø§ÙŠØ¯ÙØ§ÙŠ Ø¨Ø¹Ø¯ upsertRemote)
        await _saveCachedConfig(config);
      }

      if (request != _connectionRevision) return;

      _status = 'Connecting...';
      notifyListeners();

      final result = await _method.invokeMethod('start', {
        'config': config,
        // Hiddify's Mahsa free profile adds its WARP security layer on top.
        'warpOverProxy': _mode == VpnMode.warpPsiphon || _mode == VpnMode.mahsa,
      });
      debugPrint('start result: $result');

      // â”€â”€â”€ ØªØ¬Ø¯ÙŠØ¯ ØµØ§Ù…Øª ÙÙŠ Ø§Ù„Ø®Ù„ÙÙŠØ© Ø¨Ø¹Ø¯ Ø§Ù„Ø§ØªØµØ§Ù„ â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      // Ù†ÙØ³ ForegroundProfilesUpdateNotifier â€” ÙŠØ¬Ø¯Ø¯ Ù„Ùˆ Ø§Ù„ÙƒØ§Ø´ Ù‚Ø¯ÙŠÙ…
      _scheduleBackgroundRefresh(cc);

    } on PlatformException catch (e) {
      if (request != _connectionRevision) return;
      debugPrint('PlatformException: ${e.code} â€” ${e.message}');
      if (e.code == 'INVALID_CONFIG') await _clearConfigCache();
      _setFailed(_friendlyConnectionError(e.message ?? 'Connection failed'));
    } catch (e) {
      if (request != _connectionRevision) return;
      debugPrint('connect error: $e');
      _setFailed('Error: $e');
    }
  }

  Future<void> disconnect() async {
    ++_connectionRevision;
    await _stopConnection();
  }

  Future<void> _stopConnection() async {
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

  // â”€â”€â”€ ÙƒØ§Ø´ Ø§Ù„ÙƒÙˆÙ†ÙÙŠØº (Ù†ÙØ³ ProfilePathResolver ÙÙŠ Ù‡Ø§ÙŠØ¯ÙØ§ÙŠ) â”€â”€
  // Ù‡Ø§ÙŠØ¯ÙØ§ÙŠ ÙŠØ­ÙØ¸ Ø§Ù„ÙƒÙˆÙ†ÙÙŠØº ÙƒÙ…Ù„Ù JSON Ø¹Ù„Ù‰ Ø§Ù„Ù€ disk
  // Ù†Ø­Ù† Ù†Ø­ÙØ¸Ù‡ ÙÙŠ SharedPreferences Ù…Ø¹ timestamp â€” Ø£Ø¨Ø³Ø· Ù„ØªØ·Ø¨ÙŠÙ‚Ù†Ø§

  Future<String?> _loadCachedConfig() async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      final config  = prefs.getString(_prefLastConfig);
      final savedAt = prefs.getString(_prefLastConfigAt);
      final savedMode = prefs.getString(_prefLastConfigMode);
      if (config == null || savedAt == null || savedMode != _mode.name) return null;

      final age = DateTime.now().difference(DateTime.parse(savedAt));
      if (age.inHours >= _configMaxAgeHours) {
        debugPrint('SingboxProvider: config cache expired (${age.inHours}h old)');
        return null;
      }
      return config;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCachedConfig(String config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastConfig, config);
      await prefs.setString(_prefLastConfigAt, DateTime.now().toIso8601String());
      await prefs.setString(_prefLastConfigMode, _mode.name);
      debugPrint('SingboxProvider: config saved to cache');
    } catch (_) {}
  }

  Future<void> _clearConfigCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefLastConfig);
    await prefs.remove(_prefLastConfigAt);
    await prefs.remove(_prefLastConfigMode);
  }

  // â”€â”€â”€ ØªØ¬Ø¯ÙŠØ¯ ØµØ§Ù…Øª (Ù†ÙØ³ profiles_update_notifier ÙÙŠ Ù‡Ø§ÙŠØ¯ÙØ§ÙŠ) â”€
  void _scheduleBackgroundRefresh(String cc) {
    // Ø¨Ø¹Ø¯ 3 Ø«ÙˆØ§Ù†ÙŠ Ù…Ù† Ø§Ù„Ø§ØªØµØ§Ù„ â†’ Ø¬Ø¯Ù‘Ø¯ Ø§Ù„Ù€ Mahsa links ÙÙŠ Ø§Ù„Ø®Ù„ÙÙŠØ©
    Future.delayed(const Duration(seconds: 3), () async {
      if (!isConnected) return;
      debugPrint('SingboxProvider: background refresh starting...');
      try {
        final newConfig = await _buildConfig(cc);
        if (newConfig != null && newConfig.isNotEmpty) {
          await _saveCachedConfig(newConfig);
          debugPrint('SingboxProvider: background config refreshed');
        }
      } catch (e) {
        debugPrint('SingboxProvider: background refresh failed â€” $e');
      }
    });
  }

  // â”€â”€â”€ Build Config â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
        _status = 'Finding the fastest Mahsa server...';
        notifyListeners();
        return await V2RayConfigs.mahsa(
          countryCode: cc,
          excludedApps: _excludedApps,
          blockAds: _blockAds,
        );

      case VpnMode.pythonServers:
        if (_onyxServers.isEmpty) {
          _status = 'Loading Python servers...';
          notifyListeners();
          await loadOnyxServers(forceRefresh: true);
        }
        if (_onyxServers.isEmpty) return null;
        final selected = _selectedOnyxServer;
        final allRanked = _rankedOnyxServers();
        // A country card means â€œpick the best server in this countryâ€, not
        // â€œpin one possibly dead nodeâ€. Let urltest compare same-country nodes.
        // Ø¯Ø² ÙƒÙ„Ù‡Ù… â€” urltest ÙŠØ¬Ø±Ø¨ ÙƒÙ„Ù‡Ù… ÙˆÙŠØ®ØªØ§Ø± Ø§Ù„Ø´ØºØ§Ù„ ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹
        final servers = selected == null
            ? allRanked
            : allRanked
                .where((server) => server.country == selected.country)
                .toList();
        _status = selected == null
            ? 'Selecting the fastest Python server...'
            : 'Connecting to ${selected.country.isNotEmpty ? selected.country : selected.name}...';
        notifyListeners();
        return await V2RayConfigs.buildFromServerList(
          servers: servers,
          countryCode: cc,
          excludedApps: _excludedApps,
          blockAds: _blockAds,
        );
      case VpnMode.custom:
        if (_customUrl == null || _customUrl!.isEmpty) return null;
        // Ù„Ùˆ ÙÙŠ Ø³ÙŠØ±ÙØ± Ù…Ø®ØªØ§Ø± â†’ Ø§ØªØµÙ„ Ø¨ÙŠÙ‡ Ù…Ø¨Ø§Ø´Ø±Ø©
        if (_selectedServer != null) {
          _status = 'Connecting to ${_selectedServer!.name}...';
          notifyListeners();
          return await V2RayConfigs.buildForServer(
            url:          _customUrl!,
            server:       _selectedServer!,
            countryCode:  cc,
            excludedApps: _excludedApps,
            blockAds:     _blockAds,
          );
        }
        // Ù„Ùˆ Ù…Ø§ ÙÙŠ Ø³ÙŠØ±ÙØ± Ù…Ø®ØªØ§Ø± â†’ Ø§ØªØµÙ„ Ø¨Ø£ÙØ¶Ù„ Ø³ÙŠØ±ÙØ± (urltest ØªÙ„Ù‚Ø§Ø¦ÙŠ)
        _status = 'Fetching servers...';
        notifyListeners();
        return await V2RayConfigs.custom(
          url:          _customUrl!,
          countryCode:  cc,
          excludedApps: _excludedApps,
          blockAds:     _blockAds,
        );
    }
  }

  // â”€â”€â”€ Settings â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // â”€â”€â”€ Mode helpers Ù„Ù„Ø¥Ø´Ø¹Ø§Ø±Ø§Øª â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // â”€â”€â”€ OnyxServers â€” Ø§Ù„Ø³ÙŠØ±ÙØ±Ø§Øª Ø§Ù„Ù…Ø¯Ù…Ø¬Ø© Ù…Ù† GitHub â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // ØªÙØ¬Ù„Ø¨ ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹ Ø¹Ù†Ø¯ Ø¨Ø¯Ø¡ Ø§Ù„ØªØ·Ø¨ÙŠÙ‚ ÙˆØªÙØ¹Ø±Ø¶ ÙÙŠ Ù‚Ø§Ø¦Ù…Ø© Mahsa
  List<VpnServer> _onyxServers      = [];
  VpnServer? _selectedOnyxServer;
  bool            _loadingOnyx      = false;
  List<VpnServer> get onyxServers   => _onyxServers;
  VpnServer? get selectedOnyxServer => _selectedOnyxServer;
  bool            get loadingOnyx   => _loadingOnyx;

  List<VpnServer> _rankedOnyxServers() {
    // Ù†Ø­Ø§ÙØ¸ Ø¹Ù„Ù‰ ØªØ±ØªÙŠØ¨ servers.json â€” sing-box ÙŠØ®ØªØ§Ø± Ø§Ù„Ø£ÙØ¶Ù„ ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹ Ø¨Ù€ urltest
    return List<VpnServer>.unmodifiable(_onyxServers);
  }
  Future<void> loadOnyxServers({bool forceRefresh = false}) async {
    _loadingOnyx = true;
    notifyListeners();
    try {
      _onyxServers = await PatternihaService.getServers(forceRefresh: forceRefresh);
      if (_selectedOnyxServer != null && !(_onyxServers.any((server) => server.link == _selectedOnyxServer!.link))) {
        _selectedOnyxServer = null;
      }
      debugPrint('SingboxProvider: loaded ${_onyxServers.length} Onyx servers');
    } catch (e) {
      debugPrint('SingboxProvider: OnyxServers error â€” $e');
    }
    _loadingOnyx = false;
    notifyListeners();
  }

  void selectOnyxServer(VpnServer? server) {
    _selectedOnyxServer = server;
    _clearConfigCache();
    notifyListeners();
  }

  void selectMode(VpnMode m) {
    if (_state != VpnState.disconnected) return;
    _mode             = m;
    _userChangedMode  = true; // Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù… Ø§Ø®ØªØ§Ø± ÙŠØ¯ÙˆÙŠØ§Ù‹ â†’ Ù„Ø§ ØªØºÙŠØ± ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹
    _clearConfigCache();
    notifyListeners();
  }

  Future<void> setCustomUrl(String url) async {
    _customUrl      = url.trim();
    _selectedServer = null;
    _servers        = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCustomUrl, _customUrl!);
    await _clearConfigCache();
    notifyListeners();
    // Ø¬ÙŠØ¨ Ø§Ù„Ø³ÙŠØ±ÙØ±Ø§Øª ÙÙˆØ±Ø§Ù‹ Ø¨Ø¹Ø¯ Ø­ÙØ¸ Ø§Ù„Ù€ URL
    await fetchServers();
    // Ø§ØªØµÙ„ ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹ Ø¨Ø£ÙØ¶Ù„ Ø³ÙŠØ±ÙØ± (Auto) Ø¨Ø¹Ø¯ Ù…Ø§ ØªØ¬ÙŠ Ø§Ù„Ø³ÙŠØ±ÙØ±Ø§Øª
    await connectWithMode(VpnMode.custom);
  }

  /// Ø¬Ù„Ø¨ Ù‚Ø§Ø¦Ù…Ø© Ø§Ù„Ø³ÙŠØ±ÙØ±Ø§Øª Ù…Ù† Ø§Ù„Ù€ subscription â€” Ù†ÙØ³ Ù‡Ø§ÙŠØ¯ÙØ§ÙŠ
  Future<void> fetchServers() async {
    if (_customUrl == null || _customUrl!.isEmpty) return;
    _loadingServers = true;
    notifyListeners();
    try {
      final list = await V2RayConfigs.parseSubscription(_customUrl!);
      _servers        = list;
      // Ù„Ùˆ Ø§Ù„Ø³ÙŠØ±ÙØ± Ø§Ù„Ù…Ø®ØªØ§Ø± Ù…Ø§ Ø¹Ø§Ø¯ Ù…ÙˆØ¬ÙˆØ¯ â†’ reset
      if (_selectedServer != null) {
        final stillExists = list.any((s) => s.name == _selectedServer!.name);
        if (!stillExists) _selectedServer = null;
      }
    } catch (_) {
      _servers = [];
    }
    _loadingServers = false;
    notifyListeners();
  }

  void selectServer(VpnServer server) {
    _selectedServer = server;
    _clearConfigCache();
    notifyListeners();
  }

  void clearSelectedServer() {
    _selectedServer = null;
    _clearConfigCache();
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
    await _clearConfigCache(); // ØªØºÙŠÙŠØ± Ø§Ù„Ù€ ads â†’ Ø§Ø­Ø°Ù Ø§Ù„ÙƒØ§Ø´
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
    await _clearConfigCache();
  }

  Future<void> refreshMahsa() async {
    await MahsaService.clearCache();
    await MahsaService.backgroundRefresh();
    await _clearConfigCache();
  }

  // â”€â”€â”€ Timers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

  String _friendlyConnectionError(String message) {
    if (message.toLowerCase().contains('unknown outbound type: psiphon')) {
      return 'The bundled core rejected Psiphon (unknown outbound type).';
    }
    return message;
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
