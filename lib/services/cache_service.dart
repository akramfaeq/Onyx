import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';

class CacheService {
  static const _boxName = 'vpn_cache';
  static const _serversKey = 'servers';
  static const _timestampKey = 'servers_timestamp';
  static const _cacheDuration = Duration(hours: 6);

  static Box? _box;

  static Future<void> initialize() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
  }

  static bool get isCacheValid {
    final ts = _box?.get(_timestampKey);
    if (ts == null) return false;
    final saved = DateTime.fromMillisecondsSinceEpoch(ts as int);
    return DateTime.now().difference(saved) < _cacheDuration;
  }

  static List<Map<String, dynamic>>? getCachedServers() {
    final raw = _box?.get(_serversKey);
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw as String) as List;
      // ✅ whereType بدل cast — يتجاهل أي عنصر بصيغة خاطئة بدل ما يكرش
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveServers(List<Map<String, dynamic>> servers) async {
    await _box?.put(_serversKey, jsonEncode(servers));
    await _box?.put(_timestampKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> clear() async {
    await _box?.delete(_serversKey);
    await _box?.delete(_timestampKey);
  }
}
