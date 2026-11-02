import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widgets/chess_board.dart' show applyPieceSet, applyCoordStyle;

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
        pieceSet = _prefs.getInt('pieceSetV2') ?? 0,
        uiStyle = _prefs.getInt('uiStyle') ?? 0,
        coordSize = _prefs.getInt('coordSize') ?? 1,
        coordFont = _prefs.getInt('coordFont') ?? 0,
        birthDate = _prefs.getString('birthDate'),
        avatar = _decode(_prefs.getString('avatar')),
        solved = _loadSolved(_prefs.getString('solved'));

  final SharedPreferences _prefs;

  String lang;
  bool dark;
  String? token;
  String? phone;
  String firstName;
  String lastName;
  int boardStyle;
  int clockStyle;
  int pieceSet;
  int uiStyle;
  int coordSize; // 0 kichik, 1 o'rta, 2 katta
  int coordFont; // 0 oddiy, 1 antiqa, 2 texnik
  String? birthDate; // yyyy-MM-dd
  Uint8List? avatar;
  Map<String, int> solved;

  static Map<String, int> _loadSolved(String? v) {
    if (v == null || v.isEmpty) return {};
    try {
      final m = jsonDecode(v) as Map<String, dynamic>;
      return {for (final e in m.entries) e.key: (e.value as num).toInt()};
    } catch (_) {
      return {};
    }
  }

  Future<void> markSolved(int id) async {
    if (solved.containsKey('$id')) return;
    solved = {...solved, '$id': DateTime.now().millisecondsSinceEpoch};
    await _prefs.setString('solved', jsonEncode(solved));
    notifyListeners();
  }

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

  static Future<AppSettings> load() async {
    final s = AppSettings._(await SharedPreferences.getInstance());
    applyPieceSet(s.pieceSet);
    applyCoordStyle(s.coordSize, s.coordFont);
    return s;
  }

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

  Future<void> setCoordSize(int v) async {
    coordSize = v;
    applyCoordStyle(coordSize, coordFont);
    await _prefs.setInt('coordSize', v);
    notifyListeners();
  }

  Future<void> setCoordFont(int v) async {
    coordFont = v;
    applyCoordStyle(coordSize, coordFont);
    await _prefs.setInt('coordFont', v);
    notifyListeners();
  }

  Future<void> setBoardStyle(int v) async {
    boardStyle = v;
    await _prefs.setInt('boardStyle', v);
    notifyListeners();
  }

  Future<void> setPieceSet(int v) async {
    pieceSet = v;
    applyPieceSet(v);
    await _prefs.setInt('pieceSetV2', v);
    notifyListeners();
  }

  Future<void> setUiStyle(int v) async {
    uiStyle = v;
    await _prefs.setInt('uiStyle', v);
    notifyListeners();
  }

  Future<void> setBirthDate(String? v) async {
    birthDate = v;
    if (v == null) {
      await _prefs.remove('birthDate');
    } else {
      await _prefs.setString('birthDate', v);
    }
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
