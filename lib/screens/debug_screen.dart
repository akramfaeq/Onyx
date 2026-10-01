import 'dart:convert';
import 'package:flutter/material.dart';
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

  void _log(String msg, {bool ok = true}) {
    setState(() {
      _logs.add(_LogEntry(msg, ok));
    });
  }

  Future<void> _runTests() async {
    setState(() {
      _logs.clear();
      _running = true;
    });

    _log('═══ بدأ الفحص ═══', ok: true);

    // ── ١. Cache ──────────────────────────────────────────────
    _log('① فحص الكاش...', ok: true);
    try {
      final cached = CacheService.getCachedServers();
      final valid = CacheService.isCacheValid;
      if (cached != null) {
        _log('  الكاش: ${cached.length} سيرفر — صالح: $valid', ok: true);
        final sup = cached.where((m) => m['source'] == 'supabase').length;
        final vpn = cached.where((m) => m['source'] == 'vpngate').length;
        _log('  Supabase في الكاش: $sup | VPNGate: $vpn', ok: true);
      } else {
        _log('  الكاش فاضي', ok: false);
      }
    } catch (e) {
      _log('  خطأ الكاش: $e', ok: false);
    }

    // ── ٢. Supabase SDK ───────────────────────────────────────
    _log('② فحص Supabase SDK...', ok: true);
    try {
      final res = await Supabase.instance.client
          .from('servers')
          .select('ip, ping, is_active, ovpn_config')
          .limit(5)
          .timeout(const Duration(seconds: 10));

      final list = res as List;
      _log('  SDK ✅ — رجع ${list.length} سيرفر (أول 5)', ok: true);

      if (list.isNotEmpty) {
        for (final r in list) {
          final hasConfig = (r['ovpn_config'] ?? '').toString().isNotEmpty;
          _log(
            '  ${r['ip']} | ping:${r['ping']} | active:${r['is_active']} | config:$hasConfig',
            ok: hasConfig,
          );
        }
      }
    } catch (e) {
      _log('  SDK ❌ خطأ: $e', ok: false);
    }

    // ── ٣. Supabase HTTP مباشر ────────────────────────────────
    _log('③ فحص HTTP مباشر...', ok: true);
    try {
      const url = 'https://rtobllrfgmnlsxixmfwj.supabase.co';
      const key =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ0b2JsbHJmZ21ubHN4aXhtZndqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk1MDQ1MzYsImV4cCI6MjEwNTA4MDUzNn0.5AuNxLLbHByGGBVxbvkujHJ5VhUkFbNxRCkGW3ix3Y4';

      final uri = Uri.parse('$url/rest/v1/servers?limit=5&select=ip,ping,is_active,ovpn_config');
      final res = await http.get(uri, headers: {
        'apikey': key,
        'Authorization': 'Bearer $key',
      }).timeout(const Duration(seconds: 10));

      _log('  HTTP status: ${res.statusCode}', ok: res.statusCode == 200);

      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        _log('  HTTP ✅ — رجع ${list.length} سيرفر', ok: list.isNotEmpty);
      } else {
        _log('  HTTP body: ${res.body.substring(0, res.body.length.clamp(0, 200))}', ok: false);
      }
    } catch (e) {
      _log('  HTTP ❌ خطأ: $e', ok: false);
    }

    // ── ٤. فلتر is_active ─────────────────────────────────────
    _log('④ فحص مع فلتر is_active=true...', ok: true);
    try {
      const url = 'https://rtobllrfgmnlsxixmfwj.supabase.co';
      const key =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ0b2JsbHJmZ21ubHN4aXhtZndqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk1MDQ1MzYsImV4cCI6MjEwNTA4MDUzNn0.5AuNxLLbHByGGBVxbvkujHJ5VhUkFbNxRCkGW3ix3Y4';

      final uri = Uri.parse(
        '$url/rest/v1/servers?is_active=eq.true&ping=lte.300&limit=5&select=ip,ping',
      );
      final res = await http.get(uri, headers: {
        'apikey': key,
        'Authorization': 'Bearer $key',
      }).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        _log('  مع فلتر: ${list.length} سيرفر', ok: list.isNotEmpty);
        if (list.isEmpty) {
          _log('  ⚠️ الفلتر يرجع صفر! is_active أو ping مشكلة', ok: false);
        }
      } else {
        _log('  فشل: ${res.statusCode}', ok: false);
      }
    } catch (e) {
      _log('  ❌ $e', ok: false);
    }

    _log('═══ انتهى الفحص ═══', ok: true);
    setState(() => _running = false);
  }

  Future<void> _clearCache() async {
    await CacheService.clear();
    _log('🗑️ تم مسح الكاش', ok: true);
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
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('فحص الاتصال',
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
  _LogEntry(this.msg, this.ok);
}
