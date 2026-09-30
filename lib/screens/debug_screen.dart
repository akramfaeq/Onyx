import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/cache_service.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final List<_LogEntry> _logs = [];
  bool _running = false;
  static const _v2ray = MethodChannel('com.onyxvpn.v2ray');

  void _log(String msg, {bool ok = true}) {
    setState(() => _logs.add(_LogEntry(msg, ok)));
  }

  Future<void> _runTests() async {
    setState(() { _logs.clear(); _running = true; });
    _log('═══ بدأ الفحص ═══');

    // ── ١. Cache ──────────────────────────────────────────────
    _log('① فحص الكاش...');
    try {
      final cached = CacheService.getCachedServers();
      final valid  = CacheService.isCacheValid;
      if (cached != null) {
        _log('  الكاش: ${cached.length} سيرفر — صالح: $valid');
        final hard = cached.where((m) => m['is_hard_to_block'] == true).length;
        final proto = <String, int>{};
        for (final m in cached) {
          final p = m['protocol'] ?? 'unknown';
          proto[p] = (proto[p] ?? 0) + 1;
        }
        _log('  صعب الحجب: $hard');
        proto.forEach((p, c) => _log('  $p: $c'));
      } else {
        _log('  الكاش فاضي', ok: false);
      }
    } catch (e) {
      _log('  خطأ الكاش: $e', ok: false);
    }

    // ── ٢. Supabase ───────────────────────────────────────────
    _log('② فحص Supabase...');
    try {
      final res = await Supabase.instance.client
          .from('servers')
          .select('ip, ping, protocol, country_name, country_code, is_hard_to_block')
          .eq('is_active', true)
          .order('ping', ascending: true)
          .limit(5)
          .timeout(const Duration(seconds: 10));

      final list = res as List;
      _log('  Supabase ✅ — ${list.length} سيرفر');
      for (final r in list) {
        _log('  ${r['country_code'] ?? 'XX'} ${r['ip']} | ${r['protocol']} | ping:${r['ping']} | hard:${r['is_hard_to_block']}');
      }
    } catch (e) {
      _log('  Supabase ❌: $e', ok: false);
    }

    // ── ٣. GitHub المصادر ─────────────────────────────────────
    _log('③ فحص مصادر GitHub...');
    final sources = {
      '0xRadikal/vless': 'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/vless.txt',
      '0xRadikal/hysteria2': 'https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/Splitted-By-Protocol/hysteria2.txt',
      'barry-far/Sub1': 'https://raw.githubusercontent.com/barry-far/V2ray-Config/main/Sub1.txt',
      'morpheusadam/mix': 'https://raw.githubusercontent.com/morpheusadam/v2ray-config/main/sub/mix',
    };
    for (final entry in sources.entries) {
      try {
        final r = await http.get(Uri.parse(entry.value))
            .timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          final lines = r.body.split('\n')
              .where((l) => ['vless://','vmess://','trojan://','ss://','hysteria2://'].any(l.startsWith))
              .length;
          _log('  ${entry.key}: $lines كونفيغ ✅', ok: lines > 0);
        } else {
          _log('  ${entry.key}: ${r.statusCode} ❌', ok: false);
        }
      } catch (e) {
        _log('  ${entry.key}: timeout ❌', ok: false);
      }
    }

    // ── ٤. xray binary ────────────────────────────────────────
    _log('④ فحص xray binary...');
    try {
      final xrayFile = File('/data/data/com.onyxvpn.onyx_vpn/files/xray');
      final exists = xrayFile.existsSync();
      _log('  xray موجود: $exists', ok: exists);
      if (exists) {
        final size = xrayFile.lengthSync();
        _log('  xray حجمه: ${(size / 1024 / 1024).toStringAsFixed(1)} MB', ok: size > 1000000);
      }

      final tun2socksFile = File('/data/data/com.onyxvpn.onyx_vpn/files/tun2socks');
      final t2sExists = tun2socksFile.existsSync();
      _log('  tun2socks موجود: $t2sExists', ok: t2sExists);
    } catch (e) {
      _log('  فحص الملفات: $e', ok: false);
    }

    // ── ٥. xray SOCKS port ────────────────────────────────────
    _log('⑤ فحص xray SOCKS port 10808...');
    try {
      final socket = await Socket.connect('127.0.0.1', 10808,
          timeout: const Duration(seconds: 3));
      socket.destroy();
      _log('  port 10808: مفتوح ✅ — xray شغّال!');
    } catch (e) {
      _log('  port 10808: مغلق ❌ — xray مو شغّال', ok: false);
    }

    // ── ٦. تجربة اتصال V2Ray ──────────────────────────────────
    _log('⑥ تجربة تشغيل xray...');
    try {
      // جيب أول سيرفر من Supabase
      final res = await Supabase.instance.client
          .from('servers')
          .select('ovpn_config, country_name, protocol')
          .eq('is_active', true)
          .eq('is_hard_to_block', true)
          .order('ping', ascending: true)
          .limit(1)
          .timeout(const Duration(seconds: 5));

      final list = res as List;
      if (list.isNotEmpty) {
        final server = list.first;
        _log('  جرب: ${server['country_name']} — ${server['protocol']}');
        final result = await _v2ray.invokeMethod<bool>('connect', {
          'config': server['ovpn_config'],
          'name': server['country_name'] ?? 'Test',
        });
        _log('  نتيجة connect: $result', ok: result == true);

        if (result == true) {
          await Future.delayed(const Duration(seconds: 2));
          try {
            final s = await Socket.connect('127.0.0.1', 10808,
                timeout: const Duration(seconds: 3));
            s.destroy();
            _log('  ✅ xray شغّال فعلاً على port 10808!');
          } catch (_) {
            _log('  ❌ xray ما فتح port 10808 بعد الاتصال', ok: false);
          }
          // وقف الاتصال
          await _v2ray.invokeMethod('disconnect');
        }
      } else {
        _log('  ما في سيرفرات hard_to_block بـ Supabase', ok: false);
      }
    } catch (e) {
      _log('  خطأ: $e', ok: false);
    }

    // ── ٧. إنترنت عام ─────────────────────────────────────────
    _log('⑦ فحص الإنترنت...');
    try {
      final r = await http.get(Uri.parse('https://1.1.1.1'))
          .timeout(const Duration(seconds: 5));
      _log('  إنترنت: ${r.statusCode} ✅');
    } catch (e) {
      _log('  إنترنت: ❌ $e', ok: false);
    }

    _log('═══ انتهى الفحص ═══');
    setState(() => _running = false);
  }

  Future<void> _clearCache() async {
    await CacheService.clear();
    _log('🗑️ تم مسح الكاش');
  }

  Future<void> _stopVpn() async {
    try {
      await _v2ray.invokeMethod('disconnect');
      _log('⏹️ تم إيقاف VPN');
    } catch (e) {
      _log('خطأ إيقاف VPN: $e', ok: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A14),
        title: const Text('Debug Panel',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: _running ? null : _clearCache,
            child: const Text('مسح الكاش',
                style: TextStyle(color: Color(0xFFF59E0B), fontSize: 13)),
          ),
          TextButton(
            onPressed: _running ? null : _stopVpn,
            child: const Text('Stop VPN',
                style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text('اضغط "فحص" لتشخيص المشكلة',
                        style: TextStyle(color: Color(0xFF6B7280))),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _logs.length,
                    itemBuilder: (_, i) {
                      final l = _logs[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          l.msg,
                          style: TextStyle(
                            color: l.ok
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444),
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _running ? null : _runTests,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B5CF0),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _running
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('فحص شامل',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogEntry {
  final String msg;
  final bool ok;
  _LogEntry(this.msg, [this.ok = true]);
}
