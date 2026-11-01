import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Til, rejim va kirish ma'lumotlarini saqlaydi.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs)
      : lang = _prefs.getString('lang') ?? 'uz',
        dark = _prefs.getBool('dark') ?? false,
        token = _prefs.getString('token'),
        phone = _prefs.getString('phone'),
        firstName = _prefs.getString('firstName') ?? '',
        lastName = _prefs.getString('lastName') ?? '',
        boardStyle = _prefs.getInt('boardStyle') ?? 0,
        clockStyle = _prefs.getInt('clockStyle') ?? 0,
        avatar = _decode(_prefs.getString('avatar'));

  final SharedPreferences _prefs;

  String lang;
  bool dark;
  String? token;
  String? phone;
  String firstName;
  String lastName;
  int boardStyle;
  int clockStyle;
  Uint8List? avatar;

  static Uint8List? _decode(String? v) {
    if (v == null || v.isEmpty) return null;
    try {
      return base64Decode(v);
    } catch (_) {
      return null;
    }
  }

  String get initials {
    final a = firstName.isNotEmpty ? firstName[0] : '';
    final b = lastName.isNotEmpty ? lastName[0] : '';
    return (a + b).toUpperCase();
  }

  Future<void> setAvatar(Uint8List? bytes) async {
    avatar = bytes;
    if (bytes == null) {
      await _prefs.remove('avatar');
    } else {
      await _prefs.setString('avatar', base64Encode(bytes));
    }
    notifyListeners();
  }

  static Future<AppSettings> load() async =>
      AppSettings._(await SharedPreferences.getInstance());

  bool get loggedIn => token != null;

  Future<void> setLang(String value) async {
    lang = value;
    await _prefs.setString('lang', value);
    notifyListeners();
  }

  Future<void> setDark(bool value) async {
    dark = value;
    await _prefs.setBool('dark', value);
    notifyListeners();
  }

  String get fullName => '$firstName $lastName'.trim();

  Future<void> setName(String first, String last) async {
    firstName = first;
    lastName = last;
    await _prefs.setString('firstName', first);
    await _prefs.setString('lastName', last);
    notifyListeners();
  }

  Future<void> setBoardStyle(int v) async {
    boardStyle = v;
    await _prefs.setInt('boardStyle', v);
    notifyListeners();
  }

  Future<void> setClockStyle(int v) async {
    clockStyle = v;
    await _prefs.setInt('clockStyle', v);
    notifyListeners();
  }

  Future<void> signIn(String newToken, String newPhone) async {
    token = newToken;
    phone = newPhone;
    await _prefs.setString('token', newToken);
    await _prefs.setString('phone', newPhone);
    notifyListeners();
  }

  Future<void> signOut() async {
    token = null;
    phone = null;
    await _prefs.remove('token');
    await _prefs.remove('phone');
    notifyListeners();
  }
}
