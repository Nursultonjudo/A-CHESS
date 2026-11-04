import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chess/chess.dart' as ch;
import 'package:flutter/material.dart';
import '../page_frame.dart';
import '../robot_button.dart';
import '../ai_chat.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../api.dart';
import '../coach.dart';
import '../config.dart';
import '../engine.dart';
import '../l10n.dart';
import '../pgn.dart';
import '../puzzles.dart';
import '../lessons.dart';
import '../settings.dart';
import '../sound.dart';
import '../stats.dart';
import '../widgets/chess_board.dart';

/// Asosiy oyna: chap tomonda menyu, o'rtada doska, o'ngda yurishlar va boshqaruv.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _appActive = true;
  final ch.Chess _game = ch.Chess();
  final List<MoveRecord> _log = [];

  int _tab = 0;
  bool _showProfile = false;
  late final TextEditingController _firstCtl =
      TextEditingController(text: s.firstName);
  late final TextEditingController _lastCtl =
      TextEditingController(text: s.lastName);
  int _boardKey = 0;
  late int _baseSeconds = s.playSeconds;
  late int _incSeconds = s.playInc;
  late int _elo = s.playElo;
  late int _side = s.playSide; // 0 oq, 1 qora, 2 tasodifiy
  late bool _vsComputer = s.playVs;
  late int _whiteLeft = s.playSeconds;
  late int _blackLeft = s.playSeconds;
  bool _userWhite = true;
  bool _thinking = false;
  bool _endHandled = false;
  bool _engineFail = false;
  bool _setupOpen = true;
  bool _savedCurrent = false;
  int _thinkId = 0;
  String? _timeoutLoser; // 'white' yoki 'black'
  Timer? _timer;
  int? _rating;
  final EngineService _engine = EngineService.instance;

  AppSettings get s => widget.settings;
  Pal get pal => Pal.of(s.boardStyle, s.dark, s.uiStyle);
  String t(String key, [Map<String, String> args = const {}]) =>
      tr(s.lang, key, args);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Sfx.instance.init();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_appActive) {
        const ctx = ['play', 'rating', 'stats', 'train', 'lessons', 'passive'];
        s.baseCtx = _showProfile ? 'passive' : ctx[_tab.clamp(0, 5)];
        s.tickActivity(
          gameRunning: _tab == 0 && !_showProfile && !_over && _log.isNotEmpty,
        );
      }
      _tick();
    });
    _loadRating();
    if (_vsComputer && _side != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _log.isEmpty) _newGame(sound: false);
      });
    }
    if (s.engineOn) {
      _engine.start().then((_) => _requestEval());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    s.saveActivity();
    _timer?.cancel();
    _engine.stop();
    _firstCtl.dispose();
    _lastCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (!_appActive) s.saveActivity();
  }

  // ---- Server: reyting ----------------------------------------------------

  Future<void> _loadRating() async {
    final token = s.token;
    if (token == null) return;
    try {
      final res = await http.get(
        Uri.parse('$apiUrl/me'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final user = (jsonDecode(res.body) as Map)['user'] as Map;
        final r = user['rating'];
        if (mounted && r is int) setState(() => _rating = r);
        final srvFirst = (user['firstName'] as String?) ?? '';
        final srvLast = (user['lastName'] as String?) ?? '';
        final srvBirth = (user['birthDate'] as String?) ?? '';
        if ((srvFirst.isEmpty && srvLast.isEmpty && s.fullName.isNotEmpty) ||
            (srvBirth.isEmpty && (s.birthDate ?? '').isNotEmpty)) {
          // Serverda ism hali yo'q: ro'yxatdan o'tishda kiritilganni yuboramiz.
          try {
            await Api.post('/me/name', token, {
              'firstName': s.firstName,
              'lastName': s.lastName,
              'birthDate': s.birthDate ?? '',
            });
          } catch (_) {}
        }
        await s.applyServerUser(user.cast<String, dynamic>());
        loadCustomPuzzles(s);
        try {
          final pr = await Api.get('/me/progress', token);
          await s.mergeSolved((pr['solved'] as Map).cast<String, dynamic>());
        } catch (_) {}
        if (mounted && s.role == null) {
          await showRoleDialog(context, s, pal);
        }
        unawaited(_loadPlan());
      }
    } catch (_) {
      // Server javob bermasa, reyting o'rniga chiziqcha ko'rsatiladi.
    }
  }

  /// Trener belgilagan kunlik kalendar bloklarini yuklaydi.
  Future<void> _loadPlan() async {
    final token = s.token;
    if (token == null || s.role != 'student') return;
    try {
      final res = await Api.get('/me/plan', token);
      final list = List<Map<String, dynamic>?>.filled(4, null);
      for (final b in (res['blocks'] as List).cast<Map<String, dynamic>>()) {
        final i = (b['idx'] as num).toInt();
        if (i >= 0 && i < 4) list[i] = b;
      }
      await s.setPlanCfg(list);
    } catch (_) {
      // Server bo'lmasa, oxirgi saqlangan kalendar ishlatiladi.
    }
  }

  void _selectTab(int i) {
    setState(() {
      _tab = i;
      _showProfile = false;
    });
    if (i == 3) _loadPlan();
  }

  // ---- O'yin holati -------------------------------------------------------

  bool _drawAgreed = false; // ikki tomon kelishib durang qildi
  bool _drawBusy = false;

  bool get _over =>
      _game.in_checkmate || _game.in_draw || _timeoutLoser != null || _drawAgreed;

  String get _status {
    if (_thinking) return t('pl_thinking');
    if (_timeoutLoser != null) {
      final winner = _timeoutLoser == 'white' ? t('black') : t('white');
      return t('timeout', {'winner': winner});
    }
    if (_game.in_checkmate) {
      final winner = _game.turn == ch.Color.WHITE ? t('black') : t('white');
      return t('checkmate', {'winner': winner});
    }
    if (_drawAgreed) return t('draw_agreed');
    if (_game.in_draw) return t('draw');
    final turn =
        _game.turn == ch.Color.WHITE ? t('turn_white') : t('turn_black');
    return _game.in_check ? '${t('check')} $turn' : turn;
  }

  void _tick() {
    if (!mounted || _over || _log.isEmpty) return;
    setState(() {
      if (_game.turn == ch.Color.WHITE) {
        if (_whiteLeft > 0) _whiteLeft--;
        if (_whiteLeft == 0) _timeoutLoser = 'white';
      } else {
        if (_blackLeft > 0) _blackLeft--;
        if (_blackLeft == 0) _timeoutLoser = 'black';
      }
    });
    if (_over) _handleEnd();
  }

  void _requestEval() {
    if (!s.engineOn || !mounted) return;
    if (_over) {
      _engine.clear();
    } else {
      _engine.analyze(_game.fen);
    }
  }

  void _addIncrement(bool white) {
    if (_incSeconds <= 0) return;
    if (white) {
      _whiteLeft += _incSeconds;
    } else {
      _blackLeft += _incSeconds;
    }
  }

  /// O'yinchi yurdi (ovoz doskaning o'zida chalinadi).
  void _onMoved(MoveRecord r) {
    setState(() {
      _log.add(r);
      _addIncrement(r.white);
      if (_log.length == 1) _setupOpen = false;
    });
    _afterMove();
  }

  void _afterMove() {
    _requestEval();
    if (_over) {
      _handleEnd();
      return;
    }
    _maybeEngineMove();
  }

  /// O'yin tugaganda bir marta ovoz chaladi.
  void _handleEnd() {
    if (_endHandled) return;
    _endHandled = true;
    _thinkId++;
    if (_thinking) setState(() => _thinking = false);
    bool? whiteWon;
    if (_timeoutLoser != null) {
      whiteWon = _timeoutLoser == 'black';
    } else if (_game.in_checkmate) {
      whiteWon = _game.turn == ch.Color.BLACK;
    }
    String snd;
    if (whiteWon == null) {
      snd = 'draw';
    } else if (_vsComputer) {
      snd = whiteWon == _userWhite ? 'win' : 'lose';
    } else {
      snd = 'win';
    }
    Sfx.instance.play(snd, delay: const Duration(milliseconds: 450));
  }

  void _newGame({bool sound = true}) {
    _thinkId++;
    final white = _side == 0 ? true : (_side == 1 ? false : math.Random().nextBool());
    setState(() {
      _userWhite = white;
      _game.reset();
      _log.clear();
      _whiteLeft = _baseSeconds;
      _blackLeft = _baseSeconds;
      _timeoutLoser = null;
      _drawAgreed = false;
      _thinking = false;
      _endHandled = false;
      _engineFail = false;
      _setupOpen = true;
      _savedCurrent = false;
      _boardKey++;
    });
    _requestEval();
    if (sound) Sfx.instance.play('start');
    _maybeEngineMove();
  }

  /// Durang taklif qilish.
  Future<void> _offerDraw() async {
    if (_over || _log.length < 2 || _drawBusy || _thinking) return;
    final msg = ScaffoldMessenger.of(context);
    if (_vsComputer) {
      setState(() => _drawBusy = true);
      var accept = false;
      try {
        final e = await _engine.evalOnce(_game.fen, 700);
        if (e != null) {
          final compWhite = !_userWhite;
          final mate = e.mate;
          final cp = e.cp ?? 0;
          final compCp = compWhite ? cp : -cp;
          final compMate = mate == null ? null : (compWhite ? mate : -mate);
          final thr = _elo >= 2500 ? 30 : 90; // kuchli kompyuter faqat teng yoki yomon holatda rozi
          accept = (compMate == null || compMate < 0) && compCp <= thr;
        } else {
          accept = _log.length >= 60;
        }
      } catch (_) {
      } finally {
        _engine.endBatch();
      }
      if (!mounted) return;
      setState(() => _drawBusy = false);
      if (_over) return;
      if (accept) {
        _acceptDraw();
      } else {
        msg.showSnackBar(SnackBar(content: Text(t('pl_draw_declined'))));
      }
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t('pl_draw_offer')),
          content: Text(t('pl_draw_ask')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t('pl_draw_no')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t('pl_draw_yes')),
            ),
          ],
        ),
      );
      if (ok == true && mounted && !_over) _acceptDraw();
    }
  }

  void _acceptDraw() {
    _thinkId++;
    setState(() {
      _drawAgreed = true;
      _thinking = false;
    });
    _handleEnd();
    _requestEval();
  }

  void _undo() {
    if (_log.isEmpty) return;
    _thinkId++;
    setState(() {
      _thinking = false;
      do {
        _game.undo_move();
        _log.removeLast();
      } while (_vsComputer &&
          _log.isNotEmpty &&
          ((_game.turn == ch.Color.WHITE) != _userWhite));
      _timeoutLoser = null;
      _drawAgreed = false;
      _endHandled = false;
      _boardKey++;
    });
    _requestEval();
    _maybeEngineMove();
  }

  // ---- Partiyani saqlash -------------------------------------------------

  String get _resultText {
    if (_timeoutLoser != null) return _timeoutLoser == 'white' ? '0-1' : '1-0';
    if (_game.in_checkmate) {
      return _game.turn == ch.Color.WHITE ? '0-1' : '1-0';
    }
    if (_drawAgreed || _game.in_draw) return '1/2-1/2';
    return '*';
  }

  Future<void> _saveGame() async {
    if (_log.isEmpty || _savedCurrent) return;
    final me = s.fullName.isEmpty ? t('you') : s.fullName;
    final opp = _vsComputer ? 'Stockfish' : t('opponent');
    final white = _bottomWhite ? me : opp;
    final black = _bottomWhite ? opp : me;
    final now = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    final date = '${now.year}.${two(now.month)}.${two(now.day)}';
    final res = _resultText;
    final headers = <String, String>{
      'Event': 'A-CHESS',
      'Site': 'A-CHESS',
      'Date': date,
      'White': white,
      'Black': black,
      'Result': res,
      'TimeControl': '${_baseSeconds}+$_incSeconds',
      if (_vsComputer && _userWhite) 'BlackElo': '${_effElo(_elo)}',
      if (_vsComputer && !_userWhite) 'WhiteElo': '${_effElo(_elo)}',
    };
    final pgn = buildPgn(headers, [for (final r in _log) r.san], res);
    await s.addSavedGame({
      'id': now.millisecondsSinceEpoch,
      'date': date,
      'white': white,
      'black': black,
      'result': res,
      'moves': _log.length,
      'pgn': pgn,
    });
    if (!mounted) return;
    setState(() => _savedCurrent = true);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t('pl_game_saved'))));
  }

  // ---- Kompyuter raqib ---------------------------------------------------

  bool get _engineTurn =>
      _vsComputer &&
      !_over &&
      ((_game.turn == ch.Color.WHITE) != _userWhite);

  Future<void> _maybeEngineMove() async {
    if (!mounted || !_engineTurn || _thinking) return;
    final id = ++_thinkId;
    setState(() => _thinking = true);
    final started = DateTime.now();
    String? uci;
    final legal = (_game.moves({'verbose': true}) as List).cast<Map>();
    if (legal.isEmpty) {
      setState(() => _thinking = false);
      return;
    }
    final rnd = math.Random();
    // Past reytingda ba'zan tasodifiy (inson kabi) xato yuradi.
    final slipP = _elo < 1000 ? (1000 - _elo) / 600 * 0.18 : 0.0;
    if (rnd.nextDouble() < slipP) {
      final m = legal[rnd.nextInt(legal.length)];
      uci = '${m['from']}${m['to']}${m['promotion'] ?? ''}';
    } else {
      final left = _game.turn == ch.Color.WHITE ? _whiteLeft : _blackLeft;
      // Soatga qarab o'ylash vaqti: yuqori kuchda ko'proq, lekin soatga yetadigan.
      final maxLevel = _elo >= 2850;
      final cap = math.max(150, math.min(maxLevel ? 8000 : 4000, left * 125));
      var ms = (left * 1000 ~/ 40 + _incSeconds * 700).clamp(150, cap).toInt();
      if (maxLevel) ms = math.min(cap, (ms * 1.8).round());
      try {
        uci = await _engine.playMove(_game.fen, elo: _effElo(_elo), ms: ms);
      } catch (_) {}
    }
    final spent = DateTime.now().difference(started).inMilliseconds;
    if (spent < 500) {
      await Future<void>.delayed(Duration(milliseconds: 500 - spent));
    }
    if (!mounted || id != _thinkId) return;
    _playEngineUci(uci);
  }

  void _playEngineUci(String? uci) {
    final legal = (_game.moves({'verbose': true}) as List).cast<Map>();
    Map? pick;
    if (uci != null && uci.length >= 4) {
      for (final m in legal) {
        if ('${m['from']}${m['to']}' == uci.substring(0, 4) &&
            (uci.length < 5 || (m['promotion']?.toString() ?? '') == uci[4])) {
          pick = m;
          break;
        }
      }
    }
    if (pick == null && legal.isNotEmpty) {
      // Dvigatel javob bermadi: o'yin to'xtamasligi uchun tasodifiy yurish.
      pick = legal[math.Random().nextInt(legal.length)];
      _engineFail = true;
    }
    if (pick == null) {
      setState(() => _thinking = false);
      return;
    }
    final from = pick['from'].toString();
    final to = pick['to'].toString();
    final promo = pick['promotion']?.toString();
    final san = pick['san'].toString();
    final mover = _game.get(from);
    final target = _game.get(to);
    PieceKind? captured = target == null ? null : kindOf(target.type);
    if (captured == null &&
        mover != null &&
        mover.type == ch.PieceType.PAWN &&
        from[0] != to[0]) {
      captured = PieceKind.pawn; // en passant
    }
    _game.move({
      'from': from,
      'to': to,
      if (promo != null) 'promotion': promo,
    });
    final rec = MoveRecord(
      san: san,
      from: from,
      to: to,
      white: mover?.color == ch.Color.WHITE,
      captured: captured,
    );
    setState(() {
      _log.add(rec);
      _addIncrement(rec.white);
      _thinking = false;
      if (_log.length == 1) _setupOpen = false;
    });
    Sfx.instance.playSan(san);
    _afterMove();
  }

  // ---- O'yin sozlamalari -------------------------------------------------

  /// Ko'rsatilgan reyting -> Stockfish UCI_Elo. Stockfish qisqa vaqtda va
  /// cheklangan rejimda tirik shaxmatchidan ancha past o'ynagani uchun
  /// haqiqiy kuch ko'rsatilgan raqamdan yuqoriroq qilib olinadi.
  int _effElo(int d) {
    if (d >= 2850) return 3190;
    // (ko'rsatilgan reyting, dvigatelga beriladigan UCI_Elo) tayanch nuqtalari
    const pts = <List<int>>[
      [400, 650],
      [800, 1200],
      [1000, 1500],
      [1200, 1800],
      [1500, 2150],
      [1800, 2450],
      [2000, 2650],
      [2200, 2850],
      [2500, 3050],
      [2700, 3150],
      [2850, 3190],
    ];
    for (var i = 1; i < pts.length; i++) {
      if (d <= pts[i][0]) {
        final a = pts[i - 1], b = pts[i];
        final f = (d - a[0]) / (b[0] - a[0]);
        return (a[1] + (b[1] - a[1]) * f).round();
      }
    }
    return 3190;
  }

  void _setSetup({bool? vs, int? sec, int? inc, int? elo, int? side}) {
    s.setPlayPrefs(vs: vs, seconds: sec, inc: inc, elo: elo, side: side);
    setState(() {
      if (vs != null) _vsComputer = vs;
      if (sec != null) _baseSeconds = sec;
      if (inc != null) _incSeconds = inc;
      if (elo != null) _elo = elo;
      if (side != null) _side = side;
    });
    // Hali yurish qilinmagan bo'lsa, darhol yangi sozlama bilan boshlanadi.
    if (_log.isEmpty && (vs != null || sec != null || inc != null || side != null)) {
      _newGame(sound: false);
    }
  }

  Future<void> _customTime() async {
    final mCtl = TextEditingController(
      text: _baseSeconds % 60 == 0 ? '${_baseSeconds ~/ 60}' : '${_baseSeconds / 60}',
    );
    final iCtl = TextEditingController(text: '$_incSeconds');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('pl_custom')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: mCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: t('pl_custom_min')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: iCtl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: t('pl_custom_inc')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('co_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('save')),
          ),
        ],
      ),
    );
    if (ok == true) {
      final mins = double.tryParse(mCtl.text.trim().replaceAll(',', '.')) ?? 10;
      final inc = int.tryParse(iCtl.text.trim()) ?? 0;
      _setSetup(
        sec: (mins.clamp(0.5, 300) * 60).round(),
        inc: inc.clamp(0, 300),
      );
    }
    mCtl.dispose();
    iCtl.dispose();
  }

  List<PieceKind> _capturedBy(bool white) => [
        for (final r in _log)
          if (r.white == white && r.captured != null) r.captured!,
      ];

  int _material(List<PieceKind> list) =>
      list.fold(0, (sum, k) => sum + pieceValue(k));

  // ---- Kartalar va boshqaruv ---------------------------------------------

  /// Pastdagi (o'zimizning) tomon oqmi?
  bool get _bottomWhite => !_vsComputer || _userWhite;

  Widget _playerCard(bool white) {
    final mine = _capturedBy(white);
    final theirs = _capturedBy(!white);
    final adv = _material(mine) - _material(theirs);
    final left = white ? _whiteLeft : _blackLeft;
    final color = white ? ch.Color.WHITE : ch.Color.BLACK;
    final isMe = _vsComputer ? (white == _userWhite) : white;

    final name = isMe
        ? (s.fullName.isEmpty ? t('you') : s.fullName)
        : (_vsComputer ? 'Stockfish' : t('opponent'));
    return PlayerCard(
      pal: pal,
      boardStyle: s.boardStyle,
      clockStyle: s.clockStyle,
      avatar: isMe ? s.avatar : null,
      initials: isMe ? s.initials : '',
      name: name,
      rating: (!isMe && _vsComputer) ? (_elo >= 2850 ? 'MAX' : '$_elo') : '${_rating ?? '—'}',
      subtitle: white ? t('white') : t('black'),
      white: white,
      captured: mine,
      advantage: adv,
      seconds: left,
      active: !_over && _game.turn == color,
    );
  }

  Widget _statusCard() {
    final w = pal;
    final over = _over;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: over ? w.accentSoft : w.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: over ? w.accent : w.cardBorder),
      ),
      child: Row(
        children: [
          Icon(
            over ? Icons.emoji_events : Icons.sports_esports,
            color: w.accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _status,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: w.text,
              ),
            ),
          ),
          if (over && _log.isNotEmpty)
            IconButton(
              tooltip: _savedCurrent ? t('pl_game_saved') : t('pl_save_game'),
              onPressed: _savedCurrent ? null : _saveGame,
              icon: Icon(
                _savedCurrent ? Icons.bookmark_added : Icons.bookmark_add_outlined,
                color: w.accent,
              ),
            ),
        ],
      ),
    );
  }

  Widget _engineCard() {
    final w = pal;
    return ListenableBuilder(
      listenable: Listenable.merge([_engine.eval, _engine.ready, _engine.diag]),
      builder: (_, __) {
        final e = _engine.eval.value;
        final String sub;
        if (!_engine.ready.value) {
          final d = _engine.diag.value;
          sub = d.isEmpty ? t('engine_loading') : '${t('engine_loading')} ($d)';
        } else if (e == null) {
          final d = _engine.diag.value;
          sub = d.isEmpty ? '—' : d;
        } else {
          final b = e.bestText;
          sub = b == null
              ? '${t('engine_depth')} ${e.depth}'
              : '${t('engine_best')}: $b  ·  ${t('engine_depth')} ${e.depth}';
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: w.card,
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(color: w.accent, width: 4),
              top: BorderSide(color: w.cardBorder),
              right: BorderSide(color: w.cardBorder),
              bottom: BorderSide(color: w.cardBorder),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.memory, color: w.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stockfish',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: w.text,
                      ),
                    ),
                    Text(
                      sub,
                      style: TextStyle(fontSize: 12.5, color: w.subtext),
                    ),
                  ],
                ),
              ),
              Text(
                e?.label ?? '',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: w.accent,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _eloName(int e) {
    if (e < 800) return t('pl_lv1');
    if (e < 1200) return t('pl_lv2');
    if (e < 1500) return t('pl_lv3');
    if (e < 1800) return t('pl_lv4');
    if (e < 2000) return t('pl_lv5');
    if (e < 2200) return t('pl_lv6');
    if (e < 2500) return t('pl_lv7');
    if (e < 2700) return t('pl_lv8');
    if (e < 2850) return t('pl_lv9');
    return t('pl_lv10');
  }

  String _fmtBase() {
    final m = _baseSeconds / 60;
    return _baseSeconds % 60 == 0 ? '${m.toInt()}' : m.toStringAsFixed(1);
  }

  Widget _setupCard(double maxBody) {
    final w = pal;
    const presets = [1, 2, 3, 5, 10, 15, 30];
    const incs = [0, 1, 2, 3, 5, 10, 15];
    final customTime =
        _baseSeconds % 60 != 0 || !presets.contains(_baseSeconds ~/ 60);
    final customInc = !incs.contains(_incSeconds);
    final summary =
        '${_vsComputer ? 'Stockfish ${_elo >= 2850 ? 'MAX' : _elo}' : t('pl_two_players')}  ·  ${_fmtBase()}+$_incSeconds';

    Widget label(String key) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Text(
            t(key),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: w.subtext,
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: w.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: w.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _setupOpen = !_setupOpen),
            child: Row(
              children: [
                Icon(Icons.tune, size: 18, color: w.accent),
                const SizedBox(width: 8),
                Text(
                  t('pl_setup'),
                  style: TextStyle(fontWeight: FontWeight.w700, color: w.text),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    summary,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: w.subtext),
                  ),
                ),
                Icon(
                  _setupOpen ? Icons.expand_less : Icons.expand_more,
                  color: w.subtext,
                ),
              ],
            ),
          ),
          if (_setupOpen)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxBody),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label('pl_opponent'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          avatar: const Icon(Icons.memory, size: 16),
                          label: Text(t('pl_computer')),
                          selected: _vsComputer,
                          selectedColor: w.accent.withAlpha(0x55),
                          onSelected: (_) => _setSetup(vs: true),
                        ),
                        ChoiceChip(
                          avatar: const Icon(Icons.people_outline, size: 16),
                          label: Text(t('pl_two_players')),
                          selected: !_vsComputer,
                          selectedColor: w.accent.withAlpha(0x55),
                          onSelected: (_) => _setSetup(vs: false),
                        ),
                      ],
                    ),
                    if (_vsComputer) ...[
                      label('pl_strength'),
                      Row(
                        children: [
                          Text(
                            _elo >= 2850 ? 'MAX' : '$_elo',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: w.accent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _eloName(_elo),
                              style: TextStyle(fontSize: 12.5, color: w.subtext),
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        min: 400,
                        max: 2850,
                        divisions: 49,
                        value: _elo.clamp(400, 2850).toDouble(),
                        onChanged: (v) {
                          final e = (v / 50).round() * 50;
                          _setSetup(elo: math.max(400, math.min(2850, e)));
                        },
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final e in const [800, 1200, 1600, 2000, 2500, 2700, 2850])
                            ChoiceChip(
                              label: Text(e >= 2850 ? 'MAX' : '$e'),
                              selected: _elo == e,
                              selectedColor: w.accent.withAlpha(0x55),
                              onSelected: (_) => _setSetup(elo: e),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t('pl_elo_note'),
                        style: TextStyle(fontSize: 11.5, color: w.subtext),
                      ),
                      label('pl_side'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final e in [
                            (0, t('white')),
                            (1, t('black')),
                            (2, t('pl_random')),
                          ])
                            ChoiceChip(
                              label: Text(e.$2),
                              selected: _side == e.$1,
                              selectedColor: w.accent.withAlpha(0x55),
                              onSelected: (_) => _setSetup(side: e.$1),
                            ),
                        ],
                      ),
                    ],
                    label('time_control'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final m in presets)
                          ChoiceChip(
                            label: Text('$m ${t('minutes_short')}'),
                            selected: _baseSeconds == m * 60,
                            selectedColor: w.accent.withAlpha(0x55),
                            onSelected: (_) => _setSetup(sec: m * 60),
                          ),
                        ChoiceChip(
                          avatar: const Icon(Icons.edit, size: 14),
                          label: Text(customTime
                              ? '${_fmtBase()} ${t('minutes_short')}'
                              : t('pl_custom')),
                          selected: customTime,
                          selectedColor: w.accent.withAlpha(0x55),
                          onSelected: (_) => _customTime(),
                        ),
                      ],
                    ),
                    label('pl_increment'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final i in incs)
                          ChoiceChip(
                            label: Text('+$i ${t('pl_sec')}'),
                            selected: _incSeconds == i,
                            selectedColor: w.accent.withAlpha(0x55),
                            onSelected: (_) => _setSetup(inc: i),
                          ),
                        ChoiceChip(
                          avatar: const Icon(Icons.edit, size: 14),
                          label: Text(customInc
                              ? '+$_incSeconds ${t('pl_sec')}'
                              : t('pl_custom')),
                          selected: customInc,
                          selectedColor: w.accent.withAlpha(0x55),
                          onSelected: (_) => _customTime(),
                        ),
                      ],
                    ),
                    if (_log.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        t('pl_applies_next'),
                        style: TextStyle(fontSize: 11.5, color: w.subtext),
                      ),
                    ],
                    if (_engineFail) ...[
                      const SizedBox(height: 8),
                      Text(
                        t('pl_engine_fail'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buttons() {
    Widget lab(String key) => FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(t(key), maxLines: 1, softWrap: false),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
      children: [
        Expanded(
          flex: 5,
          child: FilledButton.icon(
            onPressed: () => _newGame(),
            icon: const Icon(Icons.refresh, size: 20),
            label: lab('new_game'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: OutlinedButton.icon(
            onPressed: _log.isEmpty ? null : _undo,
            icon: const Icon(Icons.undo, size: 20),
            label: lab('undo'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: OutlinedButton.icon(
            onPressed: (_log.isEmpty || _savedCurrent) ? null : _saveGame,
            icon: Icon(
              _savedCurrent ? Icons.bookmark_added : Icons.bookmark_add_outlined,
              size: 20,
            ),
            label: lab(_savedCurrent ? 'pl_game_saved' : 'pl_save_game'),
          ),
        ),
      ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: (_over || _log.length < 2 || _drawBusy || _thinking)
              ? null
              : _offerDraw,
          icon: const Icon(Icons.handshake_outlined, size: 20),
          label: lab('pl_draw'),
        ),
      ],
    );
  }

  Widget _board() {
    final last = _log.isEmpty ? null : _log.last;
    final board = ChessBoard(
      key: ValueKey(_boardKey),
      game: _game,
      pal: pal,
      style: s.boardStyle,
      lastFrom: last?.from,
      lastTo: last?.to,
      enabled: !_over && !_engineTurn,
      flipped: !_bottomWhite,
      onMoved: _onMoved,
    );
    return LayoutBuilder(
      builder: (context, c) {
        if (!c.hasBoundedWidth || c.maxWidth < 200) return board;
        final side = c.maxWidth - 20;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 12,
              height: side,
              child: ListenableBuilder(
                listenable: _engine.eval,
                builder: (_, __) {
                  final e = s.engineOn ? _engine.eval.value : null;
                  return EvalBar(
                    balance: materialBalance(_game.fen),
                    pal: pal,
                    whiteFrac: e?.whiteFrac,
                    label: e?.label,
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(width: side, height: side, child: board),
          ],
        );
      },
    );
  }

  Widget _moveList() => MoveListPanel(
        pal: pal,
        moves: _log,
        title: t('moves'),
        emptyText: t('no_moves'),
      );

  // ---- O'yin oynasi -------------------------------------------------------

  Widget _playView(BoxConstraints cc) {
    const gap = 10.0;
    if (cc.maxWidth >= 760) {
      const cardH = 96.0;
      const padV = 20.0;
      const padL = 40.0; // menyu bilan doska orasi (taxminan 1 sm)
      const between = 28.0; // doska bilan o'ng panel orasi
      const padR = 24.0;
      const minPanel = 360.0;
      final maxH = cc.maxHeight - padV * 2 - cardH * 2 - gap * 2;
      final maxW = cc.maxWidth - padL - between - padR - minPanel;
      final board = math.max(260.0, math.min(maxH, maxW));
      final panelW = math.max(
        minPanel,
        math.min(720.0, cc.maxWidth - padL - between - padR - board),
      );

      return Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(padL, padV, padR, padV),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: board,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _playerCard(!_bottomWhite),
                      const SizedBox(height: gap),
                      _board(),
                      const SizedBox(height: gap),
                      _playerCard(_bottomWhite),
                    ],
                  ),
                ),
                const SizedBox(width: between),
                SizedBox(
                  width: panelW,
                  height: board + cardH * 2 + gap * 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _statusCard(),
                      if (s.engineOn) ...[
                        const SizedBox(height: gap),
                        _engineCard(),
                      ],
                      const SizedBox(height: gap),
                      _setupCard(math.max(
                        120.0,
                        board + cardH * 2 + gap * 2 -
                            (s.engineOn ? 80 : 0) -
                            330,
                      )),
                      const SizedBox(height: gap),
                      _buttons(),
                      const SizedBox(height: gap),
                      Expanded(child: _moveList()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final boardW = math.min(cc.maxWidth - 24, 560.0);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: SizedBox(
          width: boardW,
          child: Column(
            children: [
              _playerCard(!_bottomWhite),
              const SizedBox(height: gap),
              _board(),
              const SizedBox(height: gap),
              _playerCard(_bottomWhite),
              const SizedBox(height: gap),
              _statusCard(),
              if (s.engineOn) ...[
                const SizedBox(height: gap),
                _engineCard(),
              ],
              const SizedBox(height: gap),
              _setupCard(420),
              const SizedBox(height: gap),
              _buttons(),
              const SizedBox(height: gap),
              SizedBox(height: 320, child: _moveList()),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Reyting / statistika / vazifalar sahifalari ------------------------

  Widget _infoView() {
    final w = pal;
    const items = [
      (Icons.leaderboard, 'nav_rating', 'rating_desc'),
      (Icons.insights, 'nav_stats', 'stats_desc'),
      (Icons.assignment, 'nav_tasks', 'tasks_desc'),
    ];
    final it = items[_tab - 1];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: w.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: w.cardBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(w.accent, Colors.white, 0.5)!,
                      w.accent,
                    ],
                  ),
                ),
                child: Icon(it.$1, size: 42, color: w.navTop),
              ),
              const SizedBox(height: 20),
              Text(
                t(it.$2),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: w.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t(it.$3),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: w.subtext),
              ),
              const SizedBox(height: 18),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: w.accentSoft,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: w.accent),
                ),
                child: Text(
                  t('soon'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: w.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() => LayoutBuilder(
        builder: (context, cc) => _showProfile
            ? _profileView()
            : (_tab == 0
                ? _playView(cc)
                : (_tab == 3
                    ? TasksView(
                        settings: s,
                        pal: pal,
                        onPlay: () => setState(() {
                          _tab = 0;
                          _showProfile = false;
                        }),
                      )
                    : (_tab == 6 && s.role != 'coach'
                        ? AiChatView(settings: s, pal: pal)
                        : (_tab == 5
                        ? _settingsView()
                        : (_tab == 4
                        ? LessonsView(settings: s, pal: pal)
                        : (_tab == 1
                            ? RatingView(settings: s, pal: pal)
                            : StatsView(settings: s, pal: pal))))))),
      );



  // ---- Sozlamalar oynasi --------------------------------------------------

  Widget _settingsView() {
    final w = pal;
    final modes = [
      (false, Icons.light_mode_outlined, t('light')),
      (true, Icons.dark_mode_outlined, t('dark')),
    ];
    return PageFrame(child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: w.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: w.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.settings, color: w.accent),
                      const SizedBox(width: 10),
                      Text(
                        t('settings'),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: w.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionTitle('language'),
                  Row(
                    children: [
                      for (final e in languageNames.entries) ...[
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: _optionCard(
                              selected: s.lang == e.key,
                              onTap: () => s.setLang(e.key),
                              label: e.value,
                              child: SizedBox(
                                height: 30,
                                child: Center(
                                  child: Text(
                                    e.key.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: w.accent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionTitle('theme'),
                  Row(
                    children: [
                      for (final m in modes)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: _optionCard(
                              selected: s.dark == m.$1,
                              onTap: () => s.setDark(m.$1),
                              label: m.$3,
                              child: SizedBox(
                                height: 30,
                                child: Icon(m.$2, size: 28, color: w.accent),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: w.accent,
                    title: Text(
                      t('sound_on'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: w.text,
                      ),
                    ),
                    subtitle: Text(
                      t('sound_on_d'),
                      style: TextStyle(fontSize: 12.5, color: w.subtext),
                    ),
                    value: s.soundOn,
                    onChanged: (v) {
                      s.setSoundOn(v);
                      if (v) Sfx.instance.play('move');
                    },
                  ),
                  if (s.soundOn)
                    Row(
                      children: [
                        Icon(
                          s.soundVolume < 0.05
                              ? Icons.volume_mute
                              : (s.soundVolume < 0.5
                                  ? Icons.volume_down
                                  : Icons.volume_up),
                          color: w.accent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          t('sound_vol'),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: w.text,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            min: 0,
                            max: 1,
                            divisions: 20,
                            value: s.soundVolume.clamp(0.0, 1.0),
                            label: '${(s.soundVolume * 100).round()}%',
                            onChanged: (v) => s.setSoundVolume(v),
                            onChangeEnd: (_) => Sfx.instance.play('capture'),
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text(
                            '${(s.soundVolume * 100).round()}%',
                            textAlign: TextAlign.right,
                            style: TextStyle(color: w.subtext),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeColor: w.accent,
                    title: Text(
                      t('engine_on'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: w.text,
                      ),
                    ),
                    subtitle: Text(
                      t('engine_on_d'),
                      style: TextStyle(fontSize: 12.5, color: w.subtext),
                    ),
                    value: s.engineOn,
                    onChanged: (v) async {
                      await s.setEngineOn(v);
                      if (v) {
                        await _engine.start();
                        _requestEval();
                      } else {
                        await _engine.stop();
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  ..._appearanceSections(w),
                ],
              ),
            ),
          ],
        ));
  }

  // ---- Shaxsiy kabinet ----------------------------------------------------

  Future<void> _pickAvatar() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final bytes = res?.files.single.bytes;
      if (bytes == null) return;
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 256);
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('decode');
      await s.setAvatar(data.buffer.asUint8List());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('err_photo'))));
    }
  }

  String _birthText() {
    final v = s.birthDate;
    if (v == null) return '—';
    final d = DateTime.tryParse(v);
    if (d == null) return '—';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd.$mm.${d.year}';
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final current = DateTime.tryParse(s.birthDate ?? '') ?? DateTime(2000, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isAfter(now) ? now : current,
      firstDate: DateTime(1920, 1, 1),
      lastDate: now,
    );
    if (picked == null) return;
    final mm = picked.month.toString().padLeft(2, '0');
    final dd = picked.day.toString().padLeft(2, '0');
    await s.setBirthDate('${picked.year}-$mm-$dd');
    await _pushProfile(); // darhol serverga saqlaymiz
  }

  Future<void> _pushProfile() async {
    final token = s.token;
    if (token == null) return;
    try {
      await Api.post('/me/name', token, {
        'firstName': s.firstName,
        'lastName': s.lastName,
        'birthDate': s.birthDate ?? '',
      });
    } catch (_) {}
  }

  Future<void> _saveProfile() async {
    await s.setName(_firstCtl.text.trim(), _lastCtl.text.trim());
    final token = s.token;
    if (token != null) {
      try {
        await Api.post('/me/name', token, {
          'firstName': s.firstName,
          'lastName': s.lastName,
          'birthDate': s.birthDate ?? '',
        });
      } catch (_) {}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t('saved'))));
  }

  Widget _profileView() {
    final w = pal;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: w.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: w.cardBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('profile'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: w.text,
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Stack(
                  children: [
                    AvatarView(
                      size: 120,
                      initials: s.initials,
                      pal: w,
                      bytes: s.avatar,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Material(
                        color: w.accent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _pickAvatar,
                          child: const Padding(
                            padding: EdgeInsets.all(9),
                            child: Icon(
                              Icons.photo_camera,
                              size: 20,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _pickAvatar,
                    icon: const Icon(Icons.upload, size: 18),
                    label: Text(t('change_photo')),
                  ),
                  if (s.avatar != null)
                    TextButton(
                      onPressed: () => s.setAvatar(null),
                      child: Text(t('remove_photo')),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _firstCtl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: t('first_name'),
                  prefixIcon: const Icon(Icons.person),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _lastCtl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: t('last_name'),
                  prefixIcon: const Icon(Icons.badge_outlined),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: _pickBirthDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: t('birth_date'),
                    prefixIcon: const Icon(Icons.cake_outlined),
                    suffixIcon: s.birthDate == null
                        ? const Icon(Icons.calendar_month)
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => s.setBirthDate(null),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                  child: Text(
                    _birthText(),
                    style: TextStyle(color: w.text, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: t('phone'),
                  prefixIcon: const Icon(Icons.phone),
                  border: const OutlineInputBorder(),
                ),
                child: Text(
                  s.phone ?? '',
                  style: TextStyle(color: w.text, fontSize: 16),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.star_rounded, color: w.accent),
                  const SizedBox(width: 8),
                  Text(
                    '${t('my_rating')}: ${_rating ?? '—'}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: w.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                t('profile_hint'),
                style: TextStyle(fontSize: 12.5, color: w.subtext),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _saveProfile,
                  icon: const Icon(Icons.check),
                  label: Text(t('save')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Dizayn tanlash oynasi ---------------------------------------------

  Widget _optionCard({
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
    required String label,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? pal.accent : pal.cardBorder,
            width: selected ? 2.2 : 1,
          ),
          color: selected ? pal.accentSoft : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: pal.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _uiPreview(int i) {
    final q = Pal.of(s.boardStyle, s.dark, i);
    return AspectRatio(
      aspectRatio: 1.5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Container(
              width: 22,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [q.navTop, q.navBottom],
                ),
              ),
            ),
            Expanded(
              child: Container(
                color: q.bg1,
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 8,
                      width: 34,
                      decoration: BoxDecoration(
                        color: q.accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: q.card,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: q.cardBorder),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String key) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          t(key),
          style: TextStyle(fontWeight: FontWeight.w700, color: pal.text),
        ),
      );

  /// Chetdagi yozuvlar o'lchami va shrifti tanlovi (kichik namuna bilan).
  List<Widget> _coordSections() {
    final p = pal;
    const sizes = ['size_small', 'size_medium', 'size_large'];
    const fonts = ['font_sans', 'font_serif', 'font_mono'];
    final saved = s.coordFont;
    Widget sample(int size, int font) {
      // Namuna uchun vaqtincha global qiymatni qo'yib, matnni olamiz
      applyCoordStyle(size, font);
      final st = coordTextStyle(p.text, 40);
      applyCoordStyle(s.coordSize, saved);
      return Text('a b c  1 2 3', style: st);
    }

    return [
      const SizedBox(height: 20),
      _sectionTitle('coord_size'),
      Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: _optionCard(
                selected: s.coordSize == i,
                onTap: () => s.setCoordSize(i),
                label: t(sizes[i]),
                child: SizedBox(height: 34, child: Center(child: sample(i, s.coordFont))),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 20),
      _sectionTitle('coord_font'),
      Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: _optionCard(
                selected: s.coordFont == i,
                onTap: () => s.setCoordFont(i),
                label: t(fonts[i]),
                child: SizedBox(height: 34, child: Center(child: sample(s.coordSize, i))),
              ),
            ),
          ],
        ],
      ),
    ];
  }

  /// Dizayn, doska, dona, soat va yozuv sozlamalari (dialog va Sozlamalar oynasi uchun umumiy).
  List<Widget> _appearanceSections(Pal p) {
    final boards = ['style_wood', 'style_marble', 'style_modern'];
    final clocks = ['clock_lcd', 'clock_flip', 'clock_classic'];
    final uis = ['ui_school', 'ui_emerald', 'ui_ocean'];
    return [
                    Text(
                      t('ui_style'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(
                            child: _optionCard(
                              selected: s.uiStyle == i,
                              onTap: () => s.setUiStyle(i),
                              label: t(uis[i]),
                              child: _uiPreview(i),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      t('board_style'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(
                            child: _optionCard(
                              selected: s.boardStyle == i,
                              onTap: () => s.setBoardStyle(i),
                              label: t(boards[i]),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: LayoutBuilder(
                                  builder: (_, c) => BoardPreview(
                                    style: i,
                                    size: c.maxWidth,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      t('piece_style'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (var i = 0; i < 2; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(
                            child: _optionCard(
                              selected: s.pieceSet == i,
                              onTap: () => s.setPieceSet(i),
                              label: t(i == 0 ? 'pieces_classic' : 'pieces_old'),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  PieceView(
                                    kind: PieceKind.knight,
                                    white: true,
                                    size: 52,
                                    style: s.boardStyle,
                                    pieceSet: i,
                                  ),
                                  PieceView(
                                    kind: PieceKind.queen,
                                    white: false,
                                    size: 52,
                                    style: s.boardStyle,
                                    pieceSet: i,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      t('clock_style'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(
                            child: _optionCard(
                              selected: s.clockStyle == i,
                              onTap: () => s.setClockStyle(i),
                              label: t(clocks[i]),
                              child: ClockView(
                                style: i,
                                seconds: 754,
                                active: true,
                                low: false,
                                width: 120,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
      ..._coordSections(),
    ];
  }

  // ---- Menyu va sarlavha --------------------------------------------------

  Widget _logo({bool compact = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: compact ? 40 : 52),
        const SizedBox(width: 12),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: ShaderMask(
          shaderCallback: (rect) => LinearGradient(
            colors: [
              Color.lerp(pal.accent, Colors.white, 0.55)!,
              pal.accent,
              Color.lerp(pal.accent, Colors.black, 0.3)!,
            ],
          ).createShader(rect),
          child: Text(
            t('app_title'),
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 22 : 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
            ),
          ),
        ),
          ),
        ),
      ],
    );
  }

  BoxDecoration _actionDeco() => BoxDecoration(
        color: Colors.white.withAlpha(0x14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(0x24), width: 1),
      );

  Widget _langButton({double scale = 1}) {
    return PopupMenuButton<String>(
      tooltip: t('language'),
      onSelected: (v) => s.setLang(v),
      itemBuilder: (_) => [
        for (final e in languageNames.entries)
          PopupMenuItem(value: e.key, child: Text(e.value)),
      ],
      child: Container(
        height: 48 * scale,
        padding: EdgeInsets.symmetric(horizontal: 14 * scale),
        decoration: _actionDeco(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.language, size: 24 * scale, color: pal.accent),
            SizedBox(width: 7 * scale),
            Text(
              s.lang.toUpperCase(),
              style: TextStyle(
                color: pal.navText,
                fontSize: 16 * scale,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    double scale = 1,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 3 * scale),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            width: 48 * scale,
            height: 48 * scale,
            decoration: _actionDeco(),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              child: Icon(icon, size: 26 * scale, color: pal.navText),
            ),
          ),
        ),
      ),
    );
  }

  Widget _logoutButton({double scale = 1}) => _actionButton(
        icon: Icons.logout,
        tooltip: t('logout'),
        onTap: () async {
          // Chiqishdan oldin jarayonni serverga yuboramiz.
          try {
            await syncProgress(s).timeout(const Duration(seconds: 6));
          } catch (_) {}
          await _pushProfile();
          await s.signOut();
        },
        scale: scale,
      );

  List<(IconData, String)> get _tabs => [
        (Icons.sports_esports, t('nav_play')),
        (Icons.leaderboard, t('nav_rating')),
        (Icons.insights, t('nav_stats')),
        (Icons.assignment, t('nav_tasks')),
        (Icons.menu_book, t('nav_lessons')),
        (Icons.settings, t('nav_settings')),
        if (s.role != 'coach') (Icons.smart_toy, 'A-CHESS AI'),
      ];

  Widget _navTile(IconData icon, String label, int i) {
    final sel = !_showProfile && _tab == i;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _selectTab(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: sel ? pal.accent.withAlpha(0x2B) : Colors.transparent,
              border: Border(
                left: BorderSide(
                  color: sel ? pal.accent : Colors.transparent,
                  width: 4,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 24, color: sel ? pal.accent : pal.navIcon),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      color: sel ? pal.accent : pal.navText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openProfile() {
    _firstCtl.text = s.firstName;
    _lastCtl.text = s.lastName;
    setState(() => _showProfile = true);
  }

  Widget _profileTile() {
    final sel = _showProfile;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _openProfile,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: sel ? pal.accentSoft : Colors.white.withAlpha(0x0D),
              border: Border.all(
                color: sel ? pal.accent : Colors.transparent,
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                AvatarView(
                  size: 42,
                  initials: s.initials,
                  pal: pal,
                  bytes: s.avatar,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.fullName.isEmpty ? t('profile') : s.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: pal.navText,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      Text(
                        t('profile'),
                        style: TextStyle(color: pal.navIcon, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: pal.navIcon),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _aiTile() {
    final sel = !_showProfile && _tab == 6;
    const cyan = Color(0xFF58E6FF);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _selectTab(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  cyan.withAlpha(sel ? 0x40 : 0x1C),
                  pal.accent.withAlpha(sel ? 0x40 : 0x14),
                ],
              ),
              border: Border.all(
                color: sel ? cyan : cyan.withAlpha(0x66),
                width: sel ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                const RobotFace(size: 60, color: cyan),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A-CHESS AI',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: pal.navText,
                        ),
                      ),
                      Text(
                        t('ai_sub'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: pal.navText.withAlpha(0xB0),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sideNav() {
    final tabs = _tabs;
    return Container(
      width: 264,
      decoration: BoxDecoration(
        color: pal.navTop,
        border: Border(
          right: BorderSide(color: Colors.white.withAlpha(0x14)),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 24, 18, 22),
              child: _logo(),
            ),
            for (var i = 0; i < tabs.length && i < 6; i++)
              _navTile(tabs[i].$1, tabs[i].$2, i),
            const Spacer(),
            if (s.role != 'coach') _aiTile(),
            _profileTile(),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
              child: Row(
                children: [
                  _langButton(),
                  const Spacer(),
                  _logoutButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: pal.navTop,
        border: Border(
          bottom: BorderSide(color: Colors.white.withAlpha(0x14)),
        ),
      ),
      child: Row(
        children: [
          _logo(compact: true),
          const Spacer(),
          InkWell(
            customBorder: const CircleBorder(),
            onTap: _openProfile,
            child: AvatarView(
              size: 34,
              initials: s.initials,
              pal: pal,
              bytes: s.avatar,
            ),
          ),
          const SizedBox(width: 4),
          _langButton(scale: 0.8),
          _logoutButton(scale: 0.8),
        ],
      ),
    );
  }

  Widget _bottomNav() {
    final tabs = _tabs;
    return NavigationBar(
      selectedIndex: _tab,
      indicatorColor: pal.accent.withAlpha(0x3A),
      backgroundColor: pal.card,
      surfaceTintColor: Colors.transparent,
      onDestinationSelected: _selectTab,
      destinations: [
        for (final tab in tabs)
          NavigationDestination(icon: Icon(tab.$1), label: tab.$2),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: s, builder: (_, __) => _scaffold());
  }

  Widget _scaffold() {
    final w = pal;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => s.touch(),
      onPointerMove: (_) => s.touch(),
      onPointerHover: (_) => s.touch(),
      onPointerSignal: (_) => s.touch(),
      child: _scaffoldBody(w),
    );
  }

  Widget _scaffoldBody(Pal w) {
    return Scaffold(
      backgroundColor: w.bg1,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [w.bg1, w.bg2],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth >= 900) {
              return Row(
                children: [
                  _sideNav(),
                  Expanded(child: _content()),
                ],
              );
            }
            return SafeArea(
              child: Column(
                children: [
                  _topBar(),
                  Expanded(child: _content()),
                  _bottomNav(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
