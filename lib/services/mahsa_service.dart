// ─── MahsaService — نفس هايدفاي + ServerProbe ────────────────────────
// التغيير الوحيد عن النسخة السابقة:
//   getLinks()   → يرجع raw links (للـ cache والـ DB)
//   getProbed()  → جديد: يختبر السيرفرات ويرجع الأفضل (للاتصال)
// ─────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_database.dart';
import 'server_probe.dart';   // ← جديد

void _unawaited(Future<void> future) { future.ignore(); }

class MahsaService {
  static const _cacheHours    = 24;
  static const _prefetchHours = 22;
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

  static List<String>? _memCache;
  static DateTime?     _memCacheTime;

  // ─── ① getLinks — نفس السابق (cache + network) ──────────────
  static Future<List<String>> getLinks({bool forceRefresh = false}) async {
    if (!forceRefresh && _memCache != null && _memCacheTime != null) {
      final age = DateTime.now().difference(_memCacheTime!);
      if (age.inHours < _cacheHours && _memCache!.isNotEmpty) {
        debugPrint('MahsaService: memory cache hit (${_memCache!.length})');
        return _memCache!.take(_maxLinks).toList();
      }
    }

    if (!forceRefresh) {
      final cached = await _readFromDb();
      if (cached != null && cached.isNotEmpty) {
        _memCache     = cached;
        _memCacheTime = DateTime.now();
        debugPrint('MahsaService: DB cache hit (${cached.length})');
        return cached.take(_maxLinks).toList();
      }
    }

    debugPrint('MahsaService: fetching from network...');
    final links = await _fetchFromNetwork();

    if (links.isNotEmpty) {
      _memCache     = links;
      _memCacheTime = DateTime.now();
      await _saveToDb(links);
      return links.take(_maxLinks).toList();
    }

    if (_memCache != null && _memCache!.isNotEmpty) return _memCache!.take(_maxLinks).toList();
    final stale = await _readFromDbIgnoreAge();
    if (stale != null && stale.isNotEmpty)        return stale.take(_maxLinks).toList();
    return [];
  }

  // ─── ② getProbed — جديد: نفس منطقية هايدفاي ─────────────────
  // يجلب السيرفرات ثم يختبرهم ويرجع الأفضل فقط
  static Future<List<String>> getProbed({bool forceRefresh = false}) async {
    final links = await getLinks(forceRefresh: forceRefresh);
    if (links.isEmpty) return [];

    debugPrint('MahsaService: probing ${links.length} servers...');
    return ServerProbe.probe(links);
  }

  // ─── Background refresh ──────────────────────────────────────
  static Future<void> backgroundRefresh() async {
    try {
      final lastSaved = await db.getMahsaLastSavedAt();
      if (lastSaved != null) {
        final age = DateTime.now().difference(lastSaved).inHours;
        if (age < _prefetchHours) {
          debugPrint('MahsaService: backgroundRefresh — fresh ($age h)');
          return;
        }
      }
    } catch (_) {}
    _unawaited(_fetchAndSave());
  }

  static Future<void> clearCache() async {
    _memCache     = null;
    _memCacheTime = null;
    await db.clearMahsaLinks();
  }

  // ─── DB ──────────────────────────────────────────────────────
  static Future<List<String>?> _readFromDb() async {
    try {
      final lastSaved = await db.getMahsaLastSavedAt();
      if (lastSaved == null) return null;
      if (DateTime.now().difference(lastSaved).inHours >= _cacheHours) return null;
      final rows = await db.getAllMahsaLinks();
      return rows.map((r) => r.rawLink).toList();
    } catch (_) { return null; }
  }

  static Future<List<String>?> _readFromDbIgnoreAge() async {
    try {
      final rows = await db.getAllMahsaLinks();
      if (rows.isEmpty) return null;
      return rows.map((r) => r.rawLink).toList();
    } catch (_) { return null; }
  }

  static Future<void> _saveToDb(List<String> links) async {
    try {
      await db.replaceMahsaLinks(links);
    } catch (e) {
      debugPrint('MahsaService: DB save error — $e');
    }
  }

  // ─── Network ─────────────────────────────────────────────────
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
      final res = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'HiddifyNext/2.0 (compatible; sing-box)',
        'Accept':     '*/*',
      }).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return [];
      return _parseBody(res.body.trim());
    } catch (e) {
      debugPrint('MahsaService: $url → $e');
      return [];
    }
  }

  static List<String> _parseBody(String body) {
    if (body.isEmpty) return [];

    if (body.startsWith('{')) {
      try {
        final json  = jsonDecode(body) as Map<String, dynamic>;
        final obs   = json['outbounds'] as List<dynamic>? ?? [];
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
    final links   = <String>[];
    for (final raw in text.split(RegExp(r'[\r\n]+'))) {
      final line   = raw.trim();
      final scheme = Uri.tryParse(line)?.scheme.toLowerCase();
      if (const {'vless','vmess','trojan','ss','hysteria2','hy2','tuic','anytls'}.contains(scheme)) {
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
          return 'trojan://${ob['password'] ?? ''}@$host:$port#${Uri.encodeComponent(tag)}';
        case 'vless':
          return 'vless://${ob['uuid'] ?? ''}@$host:$port#${Uri.encodeComponent(tag)}';
      }
    } catch (_) {}
    return null;
  }
}
