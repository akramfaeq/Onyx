// ─────────────────────────────────────────────────────────────────────
// ServerProbe — منطقية هايدفاي الكاملة لاختبار وترتيب السيرفرات
//
// هايدفاي يسوي هذا قبل كل اتصال:
//   ① جلب السيرفرات من المصدر (Mahsa / Patterniha)
//   ② ping كل سيرفر بـ TCP connect — timeout 3 ثواني
//   ③ حذف الميتين (ما ردوا خلال 3 ثواني)
//   ④ ترتيب الباقين من الأسرع للأبطأ
//   ⑤ تمرير أفضل 8 للـ sing-box
//
// الفرق الجوهري عن urltest في sing-box:
//   urltest → يختار بعد ما يتصل بكلهم (بطيء، يستهلك بيانات)
//   ServerProbe → يختار قبل الاتصال (سريع، نفس هايدفاي)
// ─────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class ProbeResult {
  final String link;
  final int    pingMs;   // -1 = ميت / timeout
  bool get isAlive => pingMs >= 0;

  const ProbeResult({required this.link, required this.pingMs});
}

class ServerProbe {

  // ─── إعدادات نفس هايدفاي ──────────────────────────────────────
  static const _probeTimeout  = Duration(seconds: 3);
  static const _maxConcurrent = 10;
  static const _maxToPass     = 8;    // أفضل 8 للـ sing-box

  /// الواجهة الرئيسية
  /// يأخذ raw links، يختبرهم بالتوازي، يرجع الأحياء مرتبين تصاعدياً
  static Future<List<String>> probe(List<String> links) async {
    if (links.isEmpty) return [];

    debugPrint('ServerProbe: probing ${links.length} servers...');
    final sw = Stopwatch()..start();

    final results = await _probeAll(links);

    final alive = results
        .where((r) => r.isAlive)
        .toList()
      ..sort((a, b) => a.pingMs.compareTo(b.pingMs));

    sw.stop();
    debugPrint(
      'ServerProbe: ${alive.length}/${links.length} alive '
      'in ${sw.elapsedMilliseconds}ms'
      '${alive.isEmpty ? "" : " — best ${alive.first.pingMs}ms"}',
    );

    if (alive.isEmpty) {
      // كلهم ميتين → fallback بالترتيب الأصلي
      debugPrint('ServerProbe: all dead, using original order as fallback');
      return links.take(_maxToPass).toList();
    }

    return alive.take(_maxToPass).map((r) => r.link).toList();
  }

  // ─── اختبار الكل بالتوازي مع semaphore ───────────────────────
  static Future<List<ProbeResult>> _probeAll(List<String> links) async {
    final results   = List<ProbeResult?>.filled(links.length, null);
    final sem       = _Semaphore(_maxConcurrent);

    await Future.wait(
      List.generate(links.length, (i) async {
        await sem.acquire();
        try {
          results[i] = await _probeOne(links[i]);
        } finally {
          sem.release();
        }
      }),
    );

    return results.whereType<ProbeResult>().toList();
  }

  // ─── اختبار سيرفر واحد بـ TCP connect ────────────────────────
  static Future<ProbeResult> _probeOne(String link) async {
    final addr = _extractAddr(link);
    if (addr == null) return ProbeResult(link: link, pingMs: -1);

    final sw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        addr.host,
        addr.port,
        timeout: _probeTimeout,
      );
      socket.destroy();
      sw.stop();
      debugPrint('  ✅ ${addr.host}:${addr.port} ${sw.elapsedMilliseconds}ms');
      return ProbeResult(link: link, pingMs: sw.elapsedMilliseconds);
    } catch (_) {
      debugPrint('  ❌ ${addr.host}:${addr.port}');
      return ProbeResult(link: link, pingMs: -1);
    }
  }

  // ─── استخراج host:port من أي نوع link ────────────────────────
  static _Addr? _extractAddr(String link) {
    try {
      final clean = link.trim().replaceFirst('\uFEFF', '');
      final uri   = Uri.tryParse(clean);
      if (uri == null) return null;

      if (uri.scheme == 'vmess') {
        // vmess://base64(json)
        try {
          final b64     = clean.substring(8);
          final padded  = b64 + '=' * ((4 - b64.length % 4) % 4);
          final decoded = utf8.decode(base64.decode(padded));
          final j       = jsonDecode(decoded) as Map<String, dynamic>;
          final host    = j['add']?.toString() ?? '';
          final port    = int.tryParse(j['port']?.toString() ?? '') ?? 0;
          if (host.isNotEmpty && port > 0) return _Addr(host, port);
        } catch (_) {}
        return null;
      }

      // vless / trojan / ss / hysteria2 / tuic / anytls / socks
      final host = uri.host;
      final port = uri.port;
      if (host.isNotEmpty && port > 0) return _Addr(host, port);
      return null;

    } catch (_) {
      return null;
    }
  }
}

// ─── Semaphore بسيط ────────────────────────────────────────────
class _Semaphore {
  final int _max;
  int       _active = 0;
  final     _waiters = <Completer<void>>[];

  _Semaphore(this._max);

  Future<void> acquire() async {
    if (_active < _max) { _active++; return; }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _active--;
    }
  }
}

class _Addr {
  final String host;
  final int    port;
  const _Addr(this.host, this.port);
}
