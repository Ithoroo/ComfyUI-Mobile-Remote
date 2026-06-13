import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ComfyInstance {
  final String ip;
  final int port;
  final String url;

  ComfyInstance({required this.ip, required this.port})
      : url = 'http://$ip:$port';

  @override
  String toString() => '$ip:$port';
}

class NetworkDiscoveryService {
  static const _ports = [8000, 8188];
  static const _connectTimeoutMs = 300;
  static const _httpTimeoutMs = 1500;

  /// Get all subnet prefixes to scan — the device's own local subnet(s)
  /// plus common private network ranges as fallback (unless fastMode)
  static Future<List<String>> _getSubnetsToScan({bool fastMode = false}) async {
    final subnets = <String>{};

    // 1. Detect the device's own local subnet(s)
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.') ||
              ip.startsWith('100.') ||
              ip.startsWith('10.0.2.')) continue;
          final parts = ip.split('.');
          if (parts.length == 4) {
            subnets.add('${parts[0]}.${parts[1]}.${parts[2]}');
          }
        }
      }
    } catch (e) {
      debugPrint('[Discovery] getSubnets error: $e');
    }

    // Fast mode: only scan the detected subnet(s)
    if (fastMode) {
      debugPrint('[Discovery] Fast mode — subnets: ${subnets.length}');
      return subnets.toList();
    }

    // 2. Thorough mode: add common home/office router default subnets
    const commonSubnets = [
      '192.168.0',   // most common (TP-Link, D-Link, etc)
      '192.168.1',   // most common (Netgear, Linksys, etc)
      '192.168.2',   // some routers
      '192.168.10',  // some routers
      '192.168.8',   // Huawei/mobile hotspots
      '192.168.50',  // ASUS
      '192.168.100', // some ISP modems
      '10.0.0',      // some routers, Apple
      '10.0.1',      // Apple AirPort
      '10.1.1',      // some networks
    ];
    subnets.addAll(commonSubnets);

    debugPrint('[Discovery] Thorough mode — subnets: ${subnets.length}');
    return subnets.toList();
  }

  /// Scan the local network for ComfyUI instances
  static Future<List<ComfyInstance>> scan({
    void Function(int progress, int total)? onProgress,
    bool fastMode = false,
  }) async {
    final subnets = await _getSubnetsToScan(fastMode: fastMode);
    if (subnets.isEmpty) {
      debugPrint('[Discovery] No subnets to scan');
      return [];
    }

    final found = <ComfyInstance>[];
    final foundIps = <String>{}; // dedupe across overlapping subnets
    final total = subnets.length * 254 * _ports.length;
    int scanned = 0;

    const batchSize = 30;
    final futures = <Future<void>>[];

    for (final subnet in subnets) {
      for (int i = 1; i <= 254; i++) {
        for (final port in _ports) {
          final ip = '$subnet.$i';
          futures.add(_checkHost(ip, port).then((ok) {
            if (ok && !foundIps.contains('$ip:$port')) {
              foundIps.add('$ip:$port');
              debugPrint('[Discovery] Found ComfyUI at $ip:$port');
              found.add(ComfyInstance(ip: ip, port: port));
            }
            scanned++;
            onProgress?.call(scanned, total);
          }));

          if (futures.length >= batchSize) {
            await Future.wait(futures);
            futures.clear();
          }
        }
      }
    }
    if (futures.isNotEmpty) await Future.wait(futures);

    debugPrint('[Discovery] Scan complete. Found: ${found.length}');
    return found;
  }

  /// First does a fast TCP check, then verifies it's actually ComfyUI
  /// by querying the /system_stats endpoint and parsing the JSON
  static Future<bool> _checkHost(String ip, int port) async {
    // Fast TCP pre-check to skip dead hosts quickly
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(milliseconds: _connectTimeoutMs),
      );
      socket.destroy();
    } catch (_) {
      return false; // port closed, skip
    }

    // Port is open — verify it's ComfyUI via its API
    try {
      final res = await http
          .get(Uri.parse('http://$ip:$port/system_stats'))
          .timeout(const Duration(milliseconds: _httpTimeoutMs));
      if (res.statusCode != 200) return false;

      // Parse JSON and check for ComfyUI-specific structure
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      // ComfyUI /system_stats always returns "system" and "devices" keys
      final hasSystem = data.containsKey('system');
      final hasDevices = data.containsKey('devices');
      if (hasSystem && hasDevices) {
        debugPrint('[Discovery] Verified ComfyUI at $ip:$port');
        return true;
      }
    } catch (e) {
      // Not ComfyUI, invalid JSON, or no HTTP response
    }
    return false;
  }
}