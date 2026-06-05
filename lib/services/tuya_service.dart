import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Communicates with the Tuya IoT cloud API to control your smart plug.
class TuyaService {
  final String clientId;
  final String clientSecret;
  final String deviceId;
  final String baseUrl;

  String? _accessToken;
  DateTime? _tokenExpiry;

  TuyaService({
    required this.clientId,
    required this.clientSecret,
    required this.deviceId,
    required this.baseUrl,
  });

  String _hmacSha256(String message) {
    final key   = utf8.encode(clientSecret);
    final bytes = utf8.encode(message);
    return Hmac(sha256, key).convert(bytes).toString().toUpperCase();
  }

  Map<String, String> _authHeaders(String token, String method, String path, String body) {
    final t     = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = DateTime.now().microsecondsSinceEpoch.toString();
    final contentHash  = sha256.convert(utf8.encode(body)).toString();
    final stringToSign = '$method\n$contentHash\n\n$path';
    final signStr      = clientId + token + t + nonce + stringToSign;
    return {
      'client_id':    clientId,
      'access_token': token,
      't':            t,
      'sign_method':  'HMAC-SHA256',
      'sign':         _hmacSha256(signStr),
      'nonce':        nonce,
      'Content-Type': 'application/json',
    };
  }

  Future<String> _getToken() async {
    if (_accessToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _accessToken!;
    }

    const tokenPath = '/v1.0/token?grant_type=1';
    final t     = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = DateTime.now().microsecondsSinceEpoch.toString();
    const emptyHash    = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    final stringToSign = 'GET\n$emptyHash\n\n$tokenPath';
    final signStr      = clientId + t + nonce + stringToSign;

    final response = await http.get(
      Uri.parse('$baseUrl$tokenPath'),
      headers: {
        'client_id':   clientId,
        't':           t,
        'sign_method': 'HMAC-SHA256',
        'sign':        _hmacSha256(signStr),
        'nonce':       nonce,
      },
    );

    print('[Tuya] token response: ${response.body}');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['success'] == true) {
      final result     = data['result'] as Map<String, dynamic>;
      _accessToken     = result['access_token'] as String;
      final expireTime = (result['expire_time'] as num).toInt();
      _tokenExpiry     = DateTime.now().add(Duration(seconds: expireTime - 60));
      print('[Tuya] token acquired successfully');
      return _accessToken!;
    }
    throw Exception('Tuya token error: ${data['msg']}');
  }

  /// Returns true if the smart plug is currently ON.
  Future<bool> getPlugState() async {
    final token   = await _getToken();
    final devPath = '/v1.0/iot-03/devices/$deviceId/status';
    final headers = _authHeaders(token, 'GET', devPath, '');

    final response = await http.get(Uri.parse('$baseUrl$devPath'), headers: headers);
    print('[Tuya] getPlugState response: ${response.body}');

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['success'] == true) {
      final statusList = data['result'] as List<dynamic>;
      print('[Tuya] codes: ${statusList.map((s) => "${s['code']}=${s['value']}").toList()}');

      final sw = statusList.firstWhere(
        (s) => s['code'] == 'pc status' ||
               s['code'] == 'switch_1'  ||
               s['code'] == 'switch',
        orElse: () => {'code': 'none', 'value': false},
      );
      print('[Tuya] matched: ${sw['code']} = ${sw['value']}');
      final value = sw['value'];
      if (value is bool) return value;
      return value.toString().toUpperCase() == 'ON';
    }
    print('[Tuya] getPlugState failed: ${data['msg']}');
    throw Exception('Tuya status error: ${data['msg']}');
  }

  /// Turns the smart plug on (true) or off (false).
  Future<bool> setPlugState(bool on) async {
    final token   = await _getToken();
    final cmdPath = '/v1.0/iot-03/devices/$deviceId/commands';
    final body    = jsonEncode({
      'commands': [{'code': 'switch_1', 'value': on}],
    });
    final headers = _authHeaders(token, 'POST', cmdPath, body);

    final response = await http.post(
      Uri.parse('$baseUrl$cmdPath'),
      headers: headers,
      body: body,
    );
    print('[Tuya] setPlugState response: ${response.body}');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['success'] == true;
  }
}