import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'v2ray_configs.dart';

/// Loads the Onyx server list published by the project's GitHub repository.
class OnyxServersService {
  static const String _serversUrl =
      'https://raw.githubusercontent.com/akramfaeq/Upload/main/servers.json';
  static const Duration _cacheDuration = Duration(hours: 1);

  static List<VpnServer>? _cachedServers;
  static DateTime? _cachedAt;
  static Future<List<VpnServer>>? _pendingFetch;

  static Future<List<VpnServer>> getServers({bool forceRefresh = false}) async {
    final cached = _cachedServers;
    final cachedAt = _cachedAt;
    if (!forceRefresh &&
        cached != null &&
        cached.isNotEmpty &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheDuration) {
      return List<VpnServer>.unmodifiable(cached);
    }

    final pending = _pendingFetch;
    if (pending != null) return pending;

    final fetch = _fetchServers();
    _pendingFetch = fetch;
    try {
      return await fetch;
    } finally {
      if (identical(_pendingFetch, fetch)) _pendingFetch = null;
    }
  }

  static Future<void> backgroundRefresh() async {
    final cachedAt = _cachedAt;
    if (_cachedServers?.isNotEmpty == true &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheDuration) {
      return;
    }
    unawaited(getServers(forceRefresh: true).then<void>((_) {}).catchError((Object error) {
      debugPrint('OnyxServersService: background refresh failed: $error');
    }));
  }

  static Future<List<VpnServer>> _fetchServers() async {
    try {
      final response = await http
          .get(
            Uri.parse(_serversUrl),
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'OnyxVPN',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw http.ClientException(
          'Failed to load servers.json (HTTP ${response.statusCode})',
          Uri.parse(_serversUrl),
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['servers'] is! List) {
        throw const FormatException('Invalid servers.json structure');
      }

      final servers = <VpnServer>[];
      for (final item in decoded['servers'] as List<dynamic>) {
        if (item is! Map<String, dynamic>) continue;
        final name = item['name'];
        final link = item['link'];
        if (name is! String || name.trim().isEmpty || link is! String || link.trim().isEmpty) {
          continue;
        }

        final pingValue = item['ping'];
        servers.add(VpnServer(
          name: name.trim(),
          link: link.trim(),
          ping: pingValue is num ? pingValue.toInt() : 0,
          quality: item['quality'] is String ? item['quality'] as String : '',
          flag: item['flag'] is String ? item['flag'] as String : '🌐',
          country: item['country'] is String ? item['country'] as String : '',
        ));
      }

      if (servers.isEmpty) {
        throw const FormatException('servers.json contains no usable servers');
      }

      _cachedServers = List<VpnServer>.unmodifiable(servers);
      _cachedAt = DateTime.now();
      return _cachedServers!;
    } catch (error) {
      debugPrint('OnyxServersService: failed to fetch servers: $error');
      final cached = _cachedServers;
      if (cached != null) return List<VpnServer>.unmodifiable(cached);
      rethrow;
    }
  }
}
