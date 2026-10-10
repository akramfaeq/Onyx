// ─── PatternihaService — بنفس منهجية Hiddify (SQLite/Drift بدل JSON) ─
// الفرق عن MahsaService:
//   • المصدر ملف .txt يحتوي v2ray links مباشرة
//   • نستخرج الاسم والعلم والبلد ونحفظهم في DB
//   • التجديد كل 24 ساعة (بدل 6 ساعات في Mahsa)
// ────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_database.dart';   // ← Drift DB
import 'v2ray_configs.dart';

// NOTE: _unawaited معرّفة هنا فقط — لا تعيد تعريفها في ملفات أخرى
// ignore: avoid_void_async
void _unawaited(Future<void> future) {
  future.ignore();
}

class PatternihaService {
  // ─── إعدادات ────────────────────────────────────────────────
  static const _cacheHours    = 24;  // Patterniha أبطأ تغييراً → 24 ساعة
  static const _prefetchHours = 22;  // جدّد مسبقاً قبل ساعتين
  static const _maxServers    = 50;

  static const _sourceUrl =
      'https://raw.githubusercontent.com/patterniha/Free-Configs/refs/heads/main/configs.txt';

  // ─── كاش في الذاكرة ─────────────────────────────────────────
  static List<VpnServer>? _memCache;
  static DateTime?         _memCacheTime;

  // ─── الواجهة الرئيسية ────────────────────────────────────────

  /// يرجع servers — من ذاكرة، DB، أو شبكة (بهذا الترتيب)
  static Future<List<VpnServer>> getServers({bool forceRefresh = false}) async {
    // 1. كاش الذاكرة
    if (!forceRefresh && _memCache != null && _memCacheTime != null) {
      final age = DateTime.now().difference(_memCacheTime!);
      if (age.inHours < _cacheHours && _memCache!.isNotEmpty) {
        debugPrint('PatternihaService: memory cache hit (${_memCache!.length} servers)');
        return _memCache!.take(_maxServers).toList();
      }
    }

    // 2. قراءة من Drift DB
    if (!forceRefresh) {
      final cached = await _readFromDb();
      if (cached != null && cached.isNotEmpty) {
        _memCache     = cached;
        _memCacheTime = DateTime.now();
        debugPrint('PatternihaService: DB cache hit (${cached.length} servers)');
        return cached.take(_maxServers).toList();
      }
    }

    // 3. جلب من الشبكة
    return _fetchFromNetwork();
  }

  /// تجديد صامت في الـ background
  static Future<void> backgroundRefresh() async {
    try {
      final lastSaved = await db.getPatternihaLastSavedAt();
      if (lastSaved != null) {
        final ageHours = DateTime.now().difference(lastSaved).inHours;
        if (ageHours < _prefetchHours) {
          debugPrint('PatternihaService: backgroundRefresh — cache fresh ($ageHours h), skipping');
          return;
        }
        debugPrint('PatternihaService: backgroundRefresh — pre-fetching ($ageHours h old)');
      } else {
        debugPrint('PatternihaService: backgroundRefresh — no DB cache, fetching');
      }
    } catch (_) {
      debugPrint('PatternihaService: backgroundRefresh — DB error, fetching');
    }

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
    debugPrint('PatternihaService: cache cleared');
  }

  // ─── DB Operations ──────────────────────────────────────────

  /// يقرأ من DB ويتحقق من العمر
  static Future<List<VpnServer>?> _readFromDb({bool ignoreAge = false}) async {
    try {
      final lastSaved = await db.getPatternihaLastSavedAt();
      if (lastSaved == null) return null;

      if (!ignoreAge &&
          DateTime.now().difference(lastSaved).inHours >= _cacheHours) {
        debugPrint('PatternihaService: DB cache expired');
        return null;
      }

      final rows = await db.getAllPatternihaServers();
      if (rows.isEmpty) return null;

      return rows.map((r) => VpnServer(
        name:    r.name,
        link:    r.rawLink,
        flag:    r.flag,
        country: r.country,
      )).toList();
    } catch (e) {
      debugPrint('PatternihaService: DB read error: $e');
      return null;
    }
  }

  static Future<void> _saveToDb(List<VpnServer> servers) async {
    try {
      await db.replacePatternihaServers(
        links:     servers.map((s) => s.link).toList(),
        names:     servers.map((s) => s.name).toList(),
        flags:     servers.map((s) => s.flag).toList(),
        countries: servers.map((s) => s.country).toList(),
      );
      debugPrint('PatternihaService: saved ${servers.length} servers to DB');
    } catch (e) {
      debugPrint('PatternihaService: DB save error: $e');
    }
  }

  // ─── جلب من الشبكة ──────────────────────────────────────────

  static Future<List<VpnServer>> _fetchFromNetwork() async {
    debugPrint('PatternihaService: fetching from network...');
    try {
      final response = await http
          .get(
            Uri.parse(_sourceUrl),
            headers: const {
              'User-Agent': 'OnyxVPN/1.0',
              'Accept':     'text/plain',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final servers = _parseConfigsTxt(response.body);
      if (servers.isEmpty) throw Exception('No usable servers found');

      await _saveToDb(servers);
      _memCache     = servers;
      _memCacheTime = DateTime.now();

      debugPrint('PatternihaService: fetched ${servers.length} servers');
      return servers.take(_maxServers).toList();
    } catch (e) {
      debugPrint('PatternihaService: network fetch failed: $e');

      // fallback — استخدم الكاش القديم
      final cached = _memCache;
      if (cached != null && cached.isNotEmpty) {
        debugPrint('PatternihaService: using stale memory cache');
        return cached.take(_maxServers).toList();
      }
      final dbCached = await _readFromDb(ignoreAge: true);
      if (dbCached != null && dbCached.isNotEmpty) {
        debugPrint('PatternihaService: using stale DB cache');
        return dbCached.take(_maxServers).toList();
      }
      rethrow;
    }
  }

  // ─── Parser ───────────────────────────────────────────────────

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
        name:    nameAndFlag.name,
        link:    urlPart,
        flag:    nameAndFlag.flag,
        country: nameAndFlag.country,
      );
    } catch (_) {
      return null;
    }
  }

  static ({String name, String flag, String country}) _extractNameAndFlag(
      String fragment, String urlPart) {
    if (fragment.isEmpty) {
      final host = _extractHost(urlPart);
      return (name: host, flag: '🌐', country: '');
    }

    final parts     = fragment.split('|');
    final firstPart = parts.first.trim();
    final flagEmoji = _extractFlagEmoji(firstPart);
    final country   = _extractCountryCode(firstPart);

    String name;
    if (parts.length >= 2) {
      name = '${parts[0].trim()} ${parts[1].trim()}'
          .replaceAll(RegExp(r'\|'), '')
          .trim();
    } else {
      name = firstPart;
    }

    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.isEmpty) name = country.isNotEmpty ? country : '🌐';

    return (name: name, flag: flagEmoji, country: country);
  }

  static String _extractFlagEmoji(String text) {
    final match = RegExp(r'[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true).firstMatch(text);
    return match?.group(0) ?? '🌐';
  }

  static String _extractCountryCode(String text) {
    final match = RegExp(r'\b([A-Z]{2})\b').firstMatch(text);
    return match?.group(1) ?? '';
  }

  static String _extractHost(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.isNotEmpty ? uri.host : 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }
}
