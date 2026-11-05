import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sound.dart';
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
        uiStyle = _prefs.getInt('uiStyle') ?? 3,
        role = _prefs.getString('role'),
        inviteCode = _prefs.getString('inviteCode'),
        publicId = _prefs.getString('publicId') ?? '',
        username = _prefs.getString('username') ?? '',
        bio = _prefs.getString('bio') ?? '',
        engineOn = _prefs.getBool('engineOn') ?? true,
        bestHint = _prefs.getBool('bestHint') ?? true,
        coordSize = _prefs.getInt('coordSize') ?? 1,
        coordFont = _prefs.getInt('coordFont') ?? 0,
        birthDate = _prefs.getString('birthDate'),
        avatar = _decode(_prefs.getString('avatar')),
        solved = _loadSolved(_prefs.getString('solved')),
        reviews = _loadSolved(_prefs.getString('reviews')),
        planDone = _loadPlan(_prefs.getString('planDone')),
        activity = _loadSolved(_prefs.getString('activity')),
        actCat = _loadCat(_prefs.getString('actCat')),
        soundOn = _prefs.getBool('soundOn') ?? true,
        soundVolume = _prefs.getDouble('soundVolume') ?? 0.8,
        playVs = _prefs.getBool('playVs') ?? true,
        playSeconds = _prefs.getInt('playSeconds') ?? 600,
        playInc = _prefs.getInt('playInc') ?? 0,
        playElo = _clampElo(_prefs.getInt('playElo') ?? 1500),
        playSide = _prefs.getInt('playSide') ?? 0,
        planCfg = _loadPlanCfg(_prefs.getString('planCfg')),
        savedGames = _loadGames(_prefs.getString('savedGames')),
        myFiles = _loadGames(_prefs.getString('myFiles'));

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
  bool engineOn;
  bool bestHint; // eng yaxshi yurish matni ko'rinsinmi
  String? role; // 'student' | 'coach' | null
  String? inviteCode; // trenerning taklif kodi
  String publicId; // ochiq ID raqam (duel uchun)
  String username; // @username
  String bio; // o'zi haqida qisqa ma'lumot
  int coordSize; // 0 kichik, 1 o'rta, 2 katta
  int coordFont; // 0 oddiy, 1 antiqa, 2 texnik
  String? birthDate; // yyyy-MM-dd
  Uint8List? avatar;
  Map<String, int> solved;
  Map<String, int> reviews; // masala id -> bajarilgan takrorlashlar soni
  Map<String, int> activity; // sana -> ilovada o'tkazilgan soniyalar
  Map<String, List<int>> planDone; // sana -> bajarilgan bloklar
  Map<String, Map<String, int>> actCat; // sana -> bo'lim -> soniyalar
  bool soundOn;
  double soundVolume; // 0..1
  bool playVs; // true: kompyuterga qarshi, false: ikki o'yinchi
  int playSeconds; // har bir tomon uchun boshlang'ich vaqt
  int playInc; // har bir yurishdan keyin qo'shiladigan soniyalar
  int playElo; // kompyuter kuchi (taxminiy FIDE Elo)
  int playSide; // 0 oq, 1 qora, 2 tasodifiy
  List<Map<String, dynamic>?> planCfg; // trener belgilagan 4 ta blok
  List<Map<String, dynamic>> savedGames; // o'yinchi saqlagan partiyalar
  List<Map<String, dynamic>> myFiles; // o'yinchining shaxsiy fayllari (PGN, PDF, DJVU)

  static Map<String, int> _loadSolved(String? v) {
    if (v == null || v.isEmpty) return {};
    try {
      final m = jsonDecode(v) as Map<String, dynamic>;
      return {for (final e in m.entries) e.key: (e.value as num).toInt()};
    } catch (_) {
      return {};
    }
  }

  int _actTicks = 0;

  // ---- Faollik: qaysi bo'limda qancha vaqt o'tgani ----------------------------
  // Bo'limlar: play, train, task, analysis, lessons, rating, stats, passive.
  static const List<String> activeCats = [
    'play',
    'train',
    'task',
    'analysis',
    'lessons',
  ];

  /// Asosiy oyna tegishli bo'lim (HomeScreen belgilaydi).
  String baseCtx = 'play';
  final List<String> _ctxStack = [];
  DateTime _lastTouch = DateTime.now();

  /// Sahifa ochilganda/yopilganda (tahlil, trener vazifasi) chaqiriladi.
  void pushCtx(String c) => _ctxStack.add(c);
  void popCtx() {
    if (_ctxStack.isNotEmpty) _ctxStack.removeLast();
  }

  /// Foydalanuvchi sichqoncha/ekran/klaviatura bilan harakat qildi.
  void touch() => _lastTouch = DateTime.now();

  static Map<String, Map<String, int>> _loadCat(String? v) {
    if (v == null || v.isEmpty) return {};
    try {
      final m = jsonDecode(v) as Map<String, dynamic>;
      return {
        for (final e in m.entries)
          e.key: {
            for (final c in (e.value as Map<String, dynamic>).entries)
              c.key: (c.value as num).toInt(),
          },
      };
    } catch (_) {
      return {};
    }
  }

  static int _clampElo(int v) => v < 400 ? 400 : (v > 2850 ? 2850 : v);

  static List<Map<String, dynamic>> _loadGames(String? v) {
    if (v == null || v.isEmpty) return [];
    try {
      return [
        for (final e in jsonDecode(v) as List) (e as Map).cast<String, dynamic>(),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> addSavedGame(Map<String, dynamic> g) async {
    savedGames = [g, ...savedGames].take(300).toList();
    await _prefs.setString('savedGames', jsonEncode(savedGames));
    notifyListeners();
  }

  /// Bir nechta partiyani birdan qo'shadi (PGN fayldan).
  Future<void> addSavedGames(List<Map<String, dynamic>> gs) async {
    savedGames = [...gs, ...savedGames].take(500).toList();
    await _prefs.setString('savedGames', jsonEncode(savedGames));
    notifyListeners();
  }

  Future<void> updateSavedGame(Map<String, dynamic> g) async {
    savedGames = [
      for (final x in savedGames) x['id'] == g['id'] ? g : x,
    ];
    await _prefs.setString('savedGames', jsonEncode(savedGames));
    notifyListeners();
  }

  Future<void> addMyFile(Map<String, dynamic> f) async {
    myFiles = [f, ...myFiles].take(200).toList();
    await _prefs.setString('myFiles', jsonEncode(myFiles));
    notifyListeners();
  }

  Future<void> renameMyFile(int id, String name) async {
    myFiles = [
      for (final x in myFiles) x['id'] == id ? {...x, 'name': name} : x,
    ];
    await _prefs.setString('myFiles', jsonEncode(myFiles));
    notifyListeners();
  }

  Future<void> deleteMyFile(int id) async {
    myFiles = myFiles.where((x) => x['id'] != id).toList();
    await _prefs.setString('myFiles', jsonEncode(myFiles));
    notifyListeners();
  }

  Future<void> deleteSavedGame(int id) async {
    savedGames = savedGames.where((g) => g['id'] != id).toList();
    await _prefs.setString('savedGames', jsonEncode(savedGames));
    notifyListeners();
  }

  static List<Map<String, dynamic>?> _loadPlanCfg(String? v) {
    final empty = List<Map<String, dynamic>?>.filled(4, null);
    if (v == null || v.isEmpty) return empty;
    try {
      final l = jsonDecode(v) as List;
      for (var i = 0; i < 4 && i < l.length; i++) {
        final e = l[i];
        empty[i] = e is Map ? e.cast<String, dynamic>() : null;
      }
    } catch (_) {}
    return empty;
  }

  /// Ilova ochiq turgan har bir soniya uchun chaqiriladi.
  /// [gameRunning] — o'yin davom etmoqda (harakatsiz o'ylash ham faol sanaladi).
  void tickActivity({bool gameRunning = false}) {
    final k = dayKey(DateTime.now());
    activity[k] = (activity[k] ?? 0) + 1;
    final idle = DateTime.now().difference(_lastTouch).inSeconds > 120 &&
        !gameRunning;
    var cat = idle
        ? 'passive'
        : (_ctxStack.isNotEmpty ? _ctxStack.last : baseCtx);
    if (!activeCats.contains(cat)) cat = 'passive';
    final day = actCat.putIfAbsent(k, () => <String, int>{});
    day[cat] = (day[cat] ?? 0) + 1;
    _actTicks++;
    if (_actTicks % 20 == 0) saveActivity();
  }

  /// Kun uchun bo'limlar bo'yicha soniyalar. Eski (bo'limsiz) vaqt
  /// "passiv"ga qo'shiladi.
  Map<String, int> catSeconds(String day) {
    final src = actCat[day] ?? const <String, int>{};
    final out = <String, int>{for (final c in activeCats) c: src[c] ?? 0};
    final known = src.values.fold<int>(0, (a, b) => a + b);
    final total = activity[day] ?? 0;
    // Reyting va statistika oynalarida turish ham passiv faollik hisoblanadi.
    out['passive'] = (src['passive'] ?? 0) +
        (src['rating'] ?? 0) +
        (src['stats'] ?? 0) +
        (total > known ? total - known : 0);
    return out;
  }

  Future<void> saveActivity() async {
    if (activity.length > 120) {
      final keys = activity.keys.toList()..sort();
      for (final old in keys.take(activity.length - 120)) {
        activity.remove(old);
      }
    }
    if (actCat.length > 120) {
      final keys = actCat.keys.toList()..sort();
      for (final old in keys.take(actCat.length - 120)) {
        actCat.remove(old);
      }
    }
    await _prefs.setString('activity', jsonEncode(activity));
    await _prefs.setString('actCat', jsonEncode(actCat));
  }

  Future<void> setSoundVolume(double v) async {
    soundVolume = v.clamp(0.0, 1.0);
    Sfx.instance.volume = soundVolume;
    await _prefs.setDouble('soundVolume', soundVolume);
    notifyListeners();
  }

  /// Serverdagi yechilgan masalalarni mahalliy ro'yxatga qo'shadi.
  Future<void> mergeSolved(Map<String, dynamic> server) async {
    var changed = false;
    final m = {...solved};
    server.forEach((k, v) {
      if (!m.containsKey(k) && v is num) {
        m[k] = v.toInt();
        changed = true;
      }
    });
    if (!changed) return;
    solved = m;
    await _prefs.setString('solved', jsonEncode(solved));
    notifyListeners();
  }

  Future<void> setSoundOn(bool v) async {
    soundOn = v;
    Sfx.instance.enabled = v;
    await _prefs.setBool('soundOn', v);
    notifyListeners();
  }

  /// O'yin sozlamalari: har biri saqlanadi (notifyListeners chaqirilmaydi).
  Future<void> setPlayPrefs({
    bool? vs,
    int? seconds,
    int? inc,
    int? elo,
    int? side,
  }) async {
    if (vs != null) {
      playVs = vs;
      await _prefs.setBool('playVs', vs);
    }
    if (seconds != null) {
      playSeconds = seconds;
      await _prefs.setInt('playSeconds', seconds);
    }
    if (inc != null) {
      playInc = inc;
      await _prefs.setInt('playInc', inc);
    }
    if (elo != null) {
      playElo = elo;
      await _prefs.setInt('playElo', elo);
    }
    if (side != null) {
      playSide = side;
      await _prefs.setInt('playSide', side);
    }
  }

  Future<void> setPlanCfg(List<Map<String, dynamic>?> cfg) async {
    planCfg = cfg;
    await _prefs.setString('planCfg', jsonEncode(cfg));
    notifyListeners();
  }

  static const List<int> srsDays = [1, 3, 7, 30];

  /// Masala takrorlash vaqti kelganmi (1, 3, 7, 30 kun).
  bool isDue(int id) {
    final t = solved['$id'];
    if (t == null) return false;
    final st = reviews['$id'] ?? 0;
    if (st >= srsDays.length) return false;
    final due = t + srsDays[st] * 86400000;
    return DateTime.now().millisecondsSinceEpoch >= due;
  }

  Future<void> markSolved(int id) async {
    if (solved.containsKey('$id')) {
      if (isDue(id)) {
        reviews = {...reviews, '$id': (reviews['$id'] ?? 0) + 1};
        await _prefs.setString('reviews', jsonEncode(reviews));
        notifyListeners();
      }
      return;
    }
    solved = {...solved, '$id': DateTime.now().millisecondsSinceEpoch};
    await _prefs.setString('solved', jsonEncode(solved));
    notifyListeners();
  }

  static Map<String, List<int>> _loadPlan(String? v) {
    if (v == null || v.isEmpty) return {};
    try {
      final m = jsonDecode(v) as Map<String, dynamic>;
      return {
        for (final e in m.entries)
          e.key: [for (final x in (e.value as List)) (x as num).toInt()],
      };
    } catch (_) {
      return {};
    }
  }

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<int> get planToday => planDone[dayKey(DateTime.now())] ?? const [];

  Future<void> setPlanBlock(int i, bool done) async {
    final k = dayKey(DateTime.now());
    final cur = {...(planDone[k] ?? const <int>[])};
    if (done) {
      cur.add(i);
    } else {
      cur.remove(i);
    }
    final m = {...planDone, k: cur.toList()..sort()};
    // eski kunlarni ixchamlash: faqat oxirgi 120 kun
    if (m.length > 120) {
      final keys = m.keys.toList()..sort();
      for (final old in keys.take(m.length - 120)) {
        m.remove(old);
      }
    }
    planDone = m;
    await _prefs.setString('planDone', jsonEncode(planDone));
    notifyListeners();
  }

  /// Ketma-ket kunlar soni (kamida bitta blok bajarilgan kunlar).
  int get streak {
    var d = DateTime.now();
    var n = 0;
    if ((planDone[dayKey(d)] ?? const []).isEmpty) {
      d = d.subtract(const Duration(days: 1));
    }
    while ((planDone[dayKey(d)] ?? const []).isNotEmpty) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
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
    Sfx.instance.enabled = s.soundOn;
    Sfx.instance.volume = s.soundVolume;
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

  /// Serverdan kelgan foydalanuvchi ma'lumotlarini saqlaydi (rol, taklif kodi).
  Future<void> applyServerUser(Map<String, dynamic> user) async {
    role = user['role'] as String?;
    inviteCode = user['inviteCode'] as String?;
    final pid = (user['publicId'] as String?) ?? '';
    if (pid.isNotEmpty) {
      publicId = pid;
      await _prefs.setString('publicId', pid);
    }
    username = (user['username'] as String?) ?? username;
    bio = (user['bio'] as String?) ?? bio;
    await _prefs.setString('username', username);
    await _prefs.setString('bio', bio);
    final fn = (user['firstName'] as String?) ?? '';
    final ln = (user['lastName'] as String?) ?? '';
    if (fn.isNotEmpty || ln.isNotEmpty) {
      firstName = fn;
      lastName = ln;
      await _prefs.setString('firstName', fn);
      await _prefs.setString('lastName', ln);
    }
    final bd = (user['birthDate'] as String?) ?? '';
    if (bd.isNotEmpty) {
      birthDate = bd;
      await _prefs.setString('birthDate', bd);
    }
    if (role == null) {
      await _prefs.remove('role');
    } else {
      await _prefs.setString('role', role!);
    }
    if (inviteCode == null) {
      await _prefs.remove('inviteCode');
    } else {
      await _prefs.setString('inviteCode', inviteCode!);
    }
    notifyListeners();
  }

  Future<void> setEngineOn(bool v) async {
    engineOn = v;
    await _prefs.setBool('engineOn', v);
    notifyListeners();
  }

  Future<void> setBestHint(bool v) async {
    bestHint = v;
    await _prefs.setBool('bestHint', v);
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

  Future<void> setUsernameBio(String u, String b) async {
    username = u;
    bio = b;
    await _prefs.setString('username', u);
    await _prefs.setString('bio', b);
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

  /// Chiqishda shu akkauntga tegishli barcha mahalliy ma'lumotlar tozalanadi
  /// (til, mavzu, doska va ovoz sozlamalari qoladi). Keyingi kirishda
  /// ma'lumotlar serverdan qayta yuklanadi.
  Future<void> signOut() async {
    token = null;
    phone = null;
    firstName = '';
    lastName = '';
    birthDate = null;
    avatar = null;
    role = null;
    inviteCode = null;
    publicId = '';
    username = '';
    bio = '';
    solved = {};
    reviews = {};
    planDone = {};
    activity = {};
    actCat = {};
    planCfg = List<Map<String, dynamic>?>.filled(4, null);
    savedGames = [];
    myFiles = [];
    for (final k in const [
      'token',
      'phone',
      'firstName',
      'lastName',
      'birthDate',
      'avatar',
      'role',
      'inviteCode',
      'publicId',
      'username',
      'bio',
      'solved',
      'reviews',
      'planDone',
      'activity',
      'actCat',
      'planCfg',
      'savedGames',
      'myFiles',
    ]) {
      await _prefs.remove(k);
    }
    notifyListeners();
  }
}
