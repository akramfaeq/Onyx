// ─── PatternihaService — نفس MahsaService + ServerProbe ──────────────

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_database.dart';
import 'v2ray_configs.dart';
import 'server_probe.dart';   // ← جديد

void _unawaited(Future<void> future) { future.ignore(); }

class PatternihaService {
  static const _cacheHours    = 24;
  static const _prefetchHours = 22;
  static const _maxServers    = 50;

  static const _sourceUrl =
      'https://raw.githubusercontent.com/patterniha/Free-Configs/refs/heads/main/configs.txt';

  static List<VpnServer>? _memCache;
  static DateTime?         _memCacheTime;

  // ─── ① getServers — نفس السابق ────────────────────────────────
  static Future<List<VpnServer>> getServers({bool forceRefresh = false}) async {
    if (!forceRefresh && _memCache != null && _memCacheTime != null) {
      final age = DateTime.now().difference(_memCacheTime!);
      if (age.inHours < _cacheHours && _memCache!.isNotEmpty) {
        debugPrint('PatternihaService: memory cache hit (${_memCache!.length})');
        return _memCache!.take(_maxServers).toList();
      }
    }

    if (!forceRefresh) {
      final cached = await _readFromDb();
      if (cached != null && cached.isNotEmpty) {
        _memCache     = cached;
        _memCacheTime = DateTime.now();
        debugPrint('PatternihaService: DB cache hit (${cached.length})');
        return cached.take(_maxServers).toList();
      }
    }

    return _fetchFromNetwork();
  }

  // ─── ② getProbed — جديد: يرجع السيرفرات الأحياء مرتبة ─────────
  static Future<List<VpnServer>> getProbed({bool forceRefresh = false}) async {
    final servers = await getServers(forceRefresh: forceRefresh);
    if (servers.isEmpty) return [];

    final links  = servers.map((s) => s.link).toList();
    final probed = await ServerProbe.probe(links);

    // نعيد بناء قائمة VpnServer بنفس ترتيب الـ probe
    final linkToServer = { for (final s in servers) s.link: s };
    return probed
        .map((l) => linkToServer[l])
        .whereType<VpnServer>()
        .toList();
  }

  // ─── Background refresh ──────────────────────────────────────
  static Future<void> backgroundRefresh() async {
    try {
      final lastSaved = await db.getPatternihaLastSavedAt();
      if (lastSaved != null) {
        final age = DateTime.now().difference(lastSaved).inHours;
        if (age < _prefetchHours) {
          debugPrint('PatternihaService: backgroundRefresh — fresh ($age h)');
          return;
        }
      }
    } catch (_) {}

    _unawaited(
      getServers(forceRefresh: true)
          .then<void>((_) {})
          .catchError((Object e) {
        debugPrint('PatternihaService: background refresh failed: $e');
      }),
    );
  }

  static Future<void> clearCache() async {
    _memCache     = null;
    _memCacheTime = null;
    await db.clearPatternihaServers();
  }

  // ─── DB ──────────────────────────────────────────────────────
  static Future<List<VpnServer>?> _readFromDb({bool ignoreAge = false}) async {
    try {
      final lastSaved = await db.getPatternihaLastSavedAt();
      if (lastSaved == null) return null;
      if (!ignoreAge && DateTime.now().difference(lastSaved).inHours >= _cacheHours) return null;
      final rows = await db.getAllPatternihaServers();
      if (rows.isEmpty) return null;
      return rows.map((r) => VpnServer(
        name: r.name, link: r.rawLink, flag: r.flag, country: r.country,
      )).toList();
    } catch (_) { return null; }
  }

  static Future<void> _saveToDb(List<VpnServer> servers) async {
    try {
      await db.replacePatternihaServers(
        links:     servers.map((s) => s.link).toList(),
        names:     servers.map((s) => s.name).toList(),
        flags:     servers.map((s) => s.flag).toList(),
        countries: servers.map((s) => s.country).toList(),
      );
    } catch (e) {
      debugPrint('PatternihaService: DB save error: $e');
    }
  }

  // ─── Network ─────────────────────────────────────────────────
  static Future<List<VpnServer>> _fetchFromNetwork() async {
    debugPrint('PatternihaService: fetching from network...');
    try {
      final response = await http.get(
        Uri.parse(_sourceUrl),
        headers: const {'User-Agent': 'OnyxVPN/1.0', 'Accept': 'text/plain'},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');

      final servers = _parseConfigsTxt(response.body);
      if (servers.isEmpty) throw Exception('No servers found');

      await _saveToDb(servers);
      _memCache     = servers;
      _memCacheTime = DateTime.now();

      debugPrint('PatternihaService: fetched ${servers.length} servers');
      return servers.take(_maxServers).toList();
    } catch (e) {
      debugPrint('PatternihaService: network failed: $e');
      final stale = await _readFromDb(ignoreAge: true);
      if (stale != null && stale.isNotEmpty) return stale.take(_maxServers).toList();
      rethrow;
    }
  }

  // ─── Parser (لم يتغير) ───────────────────────────────────────
  static List<VpnServer> _parseConfigsTxt(String body) {
    final servers = <VpnServer>[];
    for (final rawLine in body.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (!_isSupportedLink(line)) continue;
      final server = _parseLink(line);
      if (server != null) servers.add(server);
      if (servers.length >= _maxServers * 2) break;
    }
    return servers;
  }

  static bool _isSupportedLink(String line) =>
      line.startsWith('vless://')  ||
      line.startsWith('trojan://') ||
      line.startsWith('ss://')     ||
      line.startsWith('vmess://');

  static VpnServer? _parseLink(String line) {
    try {
      final fragmentIdx  = line.lastIndexOf('#');
      final urlPart      = fragmentIdx >= 0 ? line.substring(0, fragmentIdx) : line;
      final fragmentPart = fragmentIdx >= 0 ? line.substring(fragmentIdx + 1) : '';
      if (urlPart.length < 20) return null;
      final decoded     = Uri.decodeComponent(fragmentPart.replaceAll('+', ' '));
      final nameAndFlag = _extractNameAndFlag(decoded, urlPart);
      return VpnServer(
        name: nameAndFlag.name, link: urlPart,
        flag: nameAndFlag.flag, country: nameAndFlag.country,
      );
    } catch (_) { return null; }
  }

  static ({String name, String flag, String country}) _extractNameAndFlag(
      String fragment, String urlPart) {
    if (fragment.isEmpty) {
      final host = Uri.tryParse(urlPart)?.host ?? 'Unknown';
      return (name: host, flag: '🌐', country: '');
    }
    final parts     = fragment.split('|');
    final firstPart = parts.first.trim();
    final flagEmoji = RegExp(r'[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true)
        .firstMatch(firstPart)?.group(0) ?? '🌐';
    final country = RegExp(r'\b([A-Z]{2})\b').firstMatch(firstPart)?.group(1) ?? '';
    String name = parts.length >= 2
        ? '${parts[0].trim()} ${parts[1].trim()}'.replaceAll('|', '').trim()
        : firstPart;
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.isEmpty) name = country.isNotEmpty ? country : '🌐';
    return (name: name, flag: flagEmoji, country: country);
  }
}
