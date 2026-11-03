import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

/// Server qaytargan xato. [code] l10n dagi `err_<code>` kaliti bilan mos.
class ApiException implements Exception {
  ApiException(this.code);
  final String code;
  String get l10nKey => 'err_$code';
}

class Api {
  static const _timeout = Duration(seconds: 15);

  static Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
    Duration? timeout,
  }) async {
    final to = timeout ?? _timeout;
    final uri = Uri.parse('$apiUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    try {
      final http.Response res;
      switch (method) {
        case 'GET':
          res = await http.get(uri, headers: headers).timeout(to);
        case 'PATCH':
          res = await http
              .patch(uri, headers: headers, body: jsonEncode(body))
              .timeout(to);
        default:
          res = await http
              .post(uri, headers: headers, body: jsonEncode(body))
              .timeout(to);
      }
      final data = res.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode >= 400) {
        throw ApiException((data['error'] as String?) ?? 'network');
      }
      return data;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('network');
    }
  }

  static Future<Map<String, dynamic>> get(
    String path,
    String token, {
    Duration? timeout,
  }) =>
      _send('GET', path, token: token, timeout: timeout);

  static Future<Map<String, dynamic>> post(
    String path,
    String token,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) =>
      _send('POST', path, body: body, token: token, timeout: timeout);

  /// Telefonga kod yuboradi. Test rejimida serverdan kod ham qaytadi.
  static Future<String?> requestCode(String phone) async {
    final data = await _send('POST', '/auth/request-code', body: {'phone': phone});
    return data['devCode'] as String?;
  }

  /// Kodni tasdiqlaydi va token qaytaradi.
  static Future<String> verify(
    String phone,
    String code, {
    required String lang,
    required bool dark,
  }) async {
    final data = await _send('POST', '/auth/verify', body: {
      'phone': phone,
      'code': code,
      'lang': lang,
      'theme': dark ? 'dark' : 'light',
    });
    return data['token'] as String;
  }

  /// Token hali amal qiladimi?
  static Future<bool> checkToken(String token) async {
    try {
      await _send('GET', '/me', token: token);
      return true;
    } on ApiException catch (e) {
      // Faqat server tokenni rad etsa false; tarmoq xatosida kirishni saqlab qolamiz.
      return e.code != 'unauthorized';
    }
  }
}
