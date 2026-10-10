// ─── MahsaService — بنفس منهجية Hiddify (SQLite/Drift بدل JSON) ────
// هايدفاي يحفظ محتوى الـ subscription كملف على الـ disk
// نفس الطريقة هنا لكن بـ SQLite عبر Drift: أسرع قراءة وأكثر موثوقية
// عند الاتصال: نقرأ من DB مباشرة — صفر طلبات شبكة لو الكاش حديث
// التجديد: صامت في الـ background كل 24 ساعة (نفس Hiddify #profile-update-interval: 24)
// ────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_database.dart';   // ← Drift DB بدل path_provider + dart:io

// ignore: avoid_void_async
void _unawaited(Future<void> future) {
  future.ignore();
}

class MahsaService {
  // ─── إعدادات ────────────────────────────────────────────────
  static const _cacheHours    = 24;   // نفس Hiddify (#profile-update-interval: 24)
  static const _prefetchHours = 22;   // pre-fetch قبل ساعتين من انتهاء الكاش
  static const _maxLinks      = 50;

  static const _sources = [
    'https://raw.githubusercontent.com/mahsanet/MahsaFreeConfig/refs/heads/main/mci/sub_1.txt',
    'https://raw.githubusercontent.com/mahsanet/MahsaFreeConfig/refs/heads/main/mtn/sub_1.txt',
    'https://raw.githubusercontent.com/mahsanet/MahsaFreeConfig/refs/heads/main/mci/sub_2.txt',
    'https://raw.githubusercontent.com/mahsanet/MahsaFreeConfig/refs/heads/main/mtn/sub_2.txt',
    'https://raw.githubusercontent.com/mahsanet/MahsaFreeConfig/refs/heads/main/mci/sub_3.txt',
    'https://raw.githubusercontent.com/mahsanet/MahsaFreeConfig/refs/heads/main/mtn/sub_3.txt',
    'https://raw.githubusercontent.com/mahsanet/MahsaFreeConfig/refs/heads/main/mci/sub_4.txt',
    'https://raw.githubusercontent.com/mahsanet/MahsaFreeConfig/refs/heads/main/mtn/sub_4.txt',
  ];

  // ─── كاش في الذاكرة (أسرع من DB) ───────────────────────────
  static List<String>? _memCache;
  static DateTime?     _memCacheTime;

  // ─── الواجهة الرئيسية ────────────────────────────────────────

  /// يرجع links — من ذاكرة، DB، أو شبكة (بهذا الترتيب)
  static Future<List<String>> getLinks({bool forceRefresh = false}) async {
    // 1. كاش الذاكرة — أسرع شي
    if (!forceRefresh && _memCache != null && _memCacheTime != null) {
      final age = DateTime.now().difference(_memCacheTime!);
      if (age.inHours < _cacheHours && _memCache!.isNotEmpty) {
        debugPrint('MahsaService: memory cache hit (${_memCache!.length} links)');
        return _memCache!.take(_maxLinks).toList();
      }
    }

    // 2. قراءة من Drift DB (بدل JSON file)
    if (!forceRefresh) {
      final cached = await _readFromDb();
      if (cached != null && cached.isNotEmpty) {
        _memCache     = cached;
        _memCacheTime = DateTime.now();
        debugPrint('MahsaService: DB cache hit (${cached.length} links)');
        return cached.take(_maxLinks).toList();
      }
    }

    // 3. جلب من الشبكة
    debugPrint('MahsaService: fetching from network...');
    final links = await _fetchFromNetwork();

    if (links.isNotEmpty) {
      _memCache     = links;
      _memCacheTime = DateTime.now();
      await _saveToDb(links);
      debugPrint('MahsaService: fetched ${links.length} links');
      return links.take(_maxLinks).toList();
    }

    // 4. fallback: رجّع الكاش القديم حتى لو انتهت صلاحيته
    if (_memCache != null && _memCache!.isNotEmpty) {
      debugPrint('MahsaService: using stale memory cache as fallback');
      return _memCache!.take(_maxLinks).toList();
    }
    final stale = await _readFromDbIgnoreAge();
    if (stale != null && stale.isNotEmpty) {
      debugPrint('MahsaService: using stale DB cache as fallback');
      return stale.take(_maxLinks).toList();
    }

    return [];
  }

  /// تجديد صامت في الـ background — نفس ForegroundProfilesUpdateNotifier
  /// Pre-fetch قبل ساعة من انتهاء الكاش
  static Future<void> backgroundRefresh() async {
    try {
      final lastSaved = await db.getMahsaLastSavedAt();
      if (lastSaved != null) {
        final ageHours = DateTime.now().difference(lastSaved).inHours;
        if (ageHours < _prefetchHours) {
          debugPrint('MahsaService: backgroundRefresh — cache fresh ($ageHours h), skipping');
          return;
        }
        debugPrint('MahsaService: backgroundRefresh — pre-fetching (cache is $ageHours h old)');
      } else {
        debugPrint('MahsaService: backgroundRefresh — no DB cache, fetching');
      }
    } catch (_) {
      debugPrint('MahsaService: backgroundRefresh — DB read error, fetching');
    }

    _unawaited(_fetchAndSave());
  }

  static Future<void> clearCache() async {
    _memCache     = null;
    _memCacheTime = null;
    await db.clearMahsaLinks();
    debugPrint('MahsaService: cache cleared');
  }

  // ─── DB Operations (بدل File Operations) ────────────────────

  /// يقرأ من DB ويتحقق من العمر — يرجع null لو قديم
  static Future<List<String>?> _readFromDb() async {
    try {
      final lastSaved = await db.getMahsaLastSavedAt();
      if (lastSaved == null) return null;

      if (DateTime.now().difference(lastSaved).inHours >= _cacheHours) {
        debugPrint('MahsaService: DB cache expired');
        return null;
      }

      final rows = await db.getAllMahsaLinks();
      return rows.map((r) => r.rawLink).toList();
    } catch (_) {
      return null;
    }
  }

  /// يقرأ من DB بغض النظر عن العمر — للـ fallback فقط
  static Future<List<String>?> _readFromDbIgnoreAge() async {
    try {
      final rows = await db.getAllMahsaLinks();
      if (rows.isEmpty) return null;
      return rows.map((r) => r.rawLink).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveToDb(List<String> links) async {
    try {
      await db.replaceMahsaLinks(links);
      debugPrint('MahsaService: saved ${links.length} links to DB');
    } catch (e) {
      debugPrint('MahsaService: DB save error — $e');
    }
  }

  // ─── جلب من الشبكة (لم يتغير) ───────────────────────────────

  static Future<List<String>> _fetchFromNetwork() async {
    final futures = _sources.map(_fetchSingleSource);
    final results = await Future.wait(futures, eagerError: false)
        .catchError((_) => List<List<String>>.empty());

    final seen  = <String>{};
    final links = <String>[];
    for (var i = 0; i < 60 && links.length < _maxLinks * 3; i++) {
      for (final batch in results) {
        if (i >= batch.length) continue;
        final link = batch[i];
        if (seen.add(link)) links.add(link);
        if (links.length >= _maxLinks * 3) break;
      }
    }
    return links;
  }

  static Future<void> _fetchAndSave() async {
    final links = await _fetchFromNetwork();
    if (links.isNotEmpty) {
      _memCache     = links;
      _memCacheTime = DateTime.now();
      await _saveToDb(links);
    }
  }

  static Future<List<String>> _fetchSingleSource(String url) async {
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'HiddifyNext/2.0 (compatible; sing-box)',
          'Accept':     '*/*',
        },
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) return [];
      return _parseBody(res.body.trim());
    } catch (e) {
      debugPrint('MahsaService: $url → $e');
      return [];
    }
  }

  // ─── Parser (لم يتغير) ───────────────────────────────────────

  static List<String> _parseBody(String body) {
    if (body.isEmpty) return [];

    if (body.startsWith('{')) {
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final obs  = json['outbounds'] as List<dynamic>? ?? [];
        final links = <String>[];
        for (final ob in obs) {
          final m    = ob as Map<String, dynamic>;
          final type = m['type'] as String? ?? '';
          if (['vless', 'vmess', 'trojan', 'shadowsocks'].contains(type)) {
            final link = _singboxOutboundToLink(m);
            if (link != null) links.add(link);
          }
        }
        if (links.isNotEmpty) return links;
      } catch (_) {}
    }

    final decoded = _tryBase64(body);
    final text    = decoded ?? body;

    final links = <String>[];
    for (final raw in text.split(RegExp(r'[\r\n]+'))) {
      final line   = raw.trim();
      final scheme = Uri.tryParse(line)?.scheme.toLowerCase();
      if (const {'vless', 'vmess', 'trojan', 'ss', 'hysteria2', 'hy2', 'tuic', 'anytls'}
          .contains(scheme)) {
        links.add(line);
        if (links.length >= 60) break;
      }
    }
    return links;
  }

  static String? _tryBase64(String input) {
    if (input.contains('://')) return null;
    try {
      final padded  = input + '=' * ((4 - input.length % 4) % 4);
      final decoded = utf8.decode(base64.decode(padded));
      if (decoded.contains('://')) return decoded;
    } catch (_) {}
    return null;
  }

  static String? _singboxOutboundToLink(Map<String, dynamic> ob) {
    try {
      final type = ob['type'] as String;
      final tag  = ob['tag']  as String? ?? 'node';
      final host = ob['server'] as String? ?? '';
      final port = ob['server_port'] as int? ?? 443;
      if (host.isEmpty) return null;

      switch (type) {
        case 'shadowsocks':
          final method = ob['method']   as String? ?? 'none';
          final pass   = ob['password'] as String? ?? '';
          final up     = base64Url.encode(utf8.encode('$method:$pass')).replaceAll('=', '');
          return 'ss://$up@$host:$port#${Uri.encodeComponent(tag)}';
        case 'trojan':
          final pass = ob['password'] as String? ?? '';
          return 'trojan://$pass@$host:$port#${Uri.encodeComponent(tag)}';
        case 'vless':
          final uuid = ob['uuid'] as String? ?? '';
          return 'vless://$uuid@$host:$port#${Uri.encodeComponent(tag)}';
      }
    } catch (_) {}
    return null;
  }
}
