import 'dart:async';

import 'package:chess/chess.dart' as ch;
import 'package:flutter/material.dart';

import 'api.dart';
import 'game_viewer.dart';
import 'l10n.dart';
import 'page_frame.dart';
import 'people.dart';
import 'pgn.dart';
import 'settings.dart';
import 'sound.dart';
import 'widgets/chess_board.dart';

/// Onlayn duel: raqibga ID orqali taklif yuborish yoki tasodifiy raqib topish.
Future<void> showDuelLobby(BuildContext context, AppSettings s, Pal pal,
        {String? presetId}) =>
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DuelLobbyPage(settings: s, pal: pal, presetId: presetId),
    ));

/// Kelgan takliflarni va boshlangan partiyalarni kuzatuvchi (HomeScreen ichida ishlatiladi).
class DuelWatcher {
  DuelWatcher(this.context, this.s, this.palOf);
  final BuildContext context;
  final AppSettings s;
  final Pal Function() palOf;
  Timer? _timer;
  bool _busy = false;
  bool _dialog = false;
  static bool inGame = false;
  static bool inLobby = false;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  void stop() => _timer?.cancel();

  Future<void> _poll() async {
    if (_busy || s.token == null || inGame || inLobby || _dialog) return;
    _busy = true;
    try {
      final r = await Api.get('/duel/poll', s.token!);
      if (!context.mounted) return;
      final gid = r['gameId']?.toString();
      if (gid != null && !inGame) {
        await openDuelGame(context, s, palOf(), gid);
        return;
      }
      final inc = (r['incoming'] as List?) ?? const [];
      if (inc.isNotEmpty) {
        _dialog = true;
        final iv = inc.first as Map<String, dynamic>;
        await _askInvite(iv);
        _dialog = false;
      }
    } catch (_) {
      // tarmoq xatosi: keyingi so'rovda qayta uriniladi
    } finally {
      _busy = false;
    }
  }

  Future<void> _askInvite(Map<String, dynamic> iv) async {
    String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);
    final from = (iv['from'] as Map?) ?? const {};
    final time = '${iv['minutes']}+${iv['inc']}';
    final msg = t('du_incoming', {
      'name': '${from['name'] ?? ''}',
      'id': '${from['publicId'] ?? ''}',
      'time': time,
    });
    final tag = iv['rated'] == true ? t('du_rated_tag') : t('du_friendly_tag');
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(t('du_title')),
        content: Text('$msg\n\n$tag'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t('du_decline'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t('du_accept'))),
        ],
      ),
    );
    try {
      if (ok == true) {
        final r = await Api.post(
            '/duel/invite/${iv['id']}/accept', s.token!, const {});
        if (!context.mounted) return;
        await openDuelGame(context, s, palOf(), r['gameId'].toString());
      } else {
        await Api.post('/duel/invite/${iv['id']}/decline', s.token!, const {});
      }
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t(e.l10nKey))));
    }
  }
}

Future<void> openDuelGame(
    BuildContext context, AppSettings s, Pal pal, String gameId) {
  DuelWatcher.inGame = true;
  return Navigator.of(context)
      .push(MaterialPageRoute(
        builder: (_) => OnlineGamePage(settings: s, pal: pal, gameId: gameId),
      ))
      .whenComplete(() => DuelWatcher.inGame = false);
}

// ---------------------------------------------------------------------------

class DuelLobbyPage extends StatefulWidget {
  const DuelLobbyPage(
      {super.key, required this.settings, required this.pal, this.presetId});
  final AppSettings settings;
  final Pal pal;
  final String? presetId;
  @override
  State<DuelLobbyPage> createState() => _DuelLobbyPageState();
}

class _DuelLobbyPageState extends State<DuelLobbyPage> {
  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);

  final _idCtl = TextEditingController();
  static const _presets = [(1, 0), (3, 0), (3, 2), (5, 0), (10, 0), (15, 10)];
  int _sel = 4;
  String _mode = 'idle'; // idle | invite | queue
  String? _inviteId;
  String? _msg;
  Timer? _timer;
  bool _leaving = false;

  bool _rated = false;

  @override
  void initState() {
    super.initState();
    DuelWatcher.inLobby = true;
    if (widget.presetId != null) _idCtl.text = widget.presetId!;
  }

  @override
  void dispose() {
    DuelWatcher.inLobby = false;
    _timer?.cancel();
    _idCtl.dispose();
    if (_mode == 'queue') {
      Api.post('/duel/queue/leave', s.token!, const {}).catchError((_) => <String, dynamic>{});
    } else if (_mode == 'invite' && _inviteId != null) {
      Api.post('/duel/invite/$_inviteId/cancel', s.token!, const {})
          .catchError((_) => <String, dynamic>{});
    }
    super.dispose();
  }

  Map<String, dynamic> get _time =>
      {'minutes': _presets[_sel].$1, 'inc': _presets[_sel].$2, 'rated': _rated};

  void _err(Object e) {
    final key = e is ApiException ? e.l10nKey : 'err_network';
    setState(() {
      _mode = 'idle';
      _msg = t(key);
    });
  }

  Future<void> _go(String gameId) async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    _mode = 'idle';
    DuelWatcher.inLobby = false;
    if (!mounted) return;
    DuelWatcher.inGame = true;
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) =>
          OnlineGamePage(settings: s, pal: pal, gameId: gameId),
    ));
    DuelWatcher.inGame = false;
  }

  Future<void> _invite() async {
    final id = _idCtl.text.trim();
    if (id.isEmpty) return;
    setState(() => _msg = null);
    try {
      final r = await Api.post(
          '/duel/invite', s.token!, {'toPublicId': id, ..._time});
      _inviteId = r['id'].toString();
      setState(() => _mode = 'invite');
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
        try {
          final p = await Api.get('/duel/poll', s.token!);
          final o = p['outgoing'] as Map?;
          if (o == null || o['id'] != _inviteId) return;
          if (o['status'] == 'accepted' && o['gameId'] != null) {
            _go(o['gameId'].toString());
          } else if (o['status'] == 'declined') {
            _timer?.cancel();
            if (mounted) {
              setState(() {
                _mode = 'idle';
                _msg = t('du_declined');
              });
            }
          } else if (o['status'] == 'expired') {
            _timer?.cancel();
            if (mounted) {
              setState(() {
                _mode = 'idle';
                _msg = t('du_expired');
              });
            }
          }
        } catch (_) {}
      });
    } catch (e) {
      _err(e);
    }
  }

  Future<void> _random() async {
    setState(() => _msg = null);
    try {
      final r = await Api.post('/duel/queue', s.token!, _time);
      if (r['gameId'] != null) {
        _go(r['gameId'].toString());
        return;
      }
      setState(() => _mode = 'queue');
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
        try {
          final p = await Api.get('/duel/poll', s.token!);
          if (p['gameId'] != null) {
            _go(p['gameId'].toString());
          } else if (p['queued'] != true && mounted && _mode == 'queue') {
            _timer?.cancel();
            setState(() => _mode = 'idle');
          }
        } catch (_) {}
      });
    } catch (e) {
      _err(e);
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    try {
      if (_mode == 'queue') {
        await Api.post('/duel/queue/leave', s.token!, const {});
      } else if (_inviteId != null) {
        await Api.post('/duel/invite/$_inviteId/cancel', s.token!, const {});
      }
    } catch (_) {}
    if (mounted) setState(() => _mode = 'idle');
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _mode != 'idle';
    return Scaffold(
      backgroundColor: pal.bg1,
      appBar: AppBar(title: Text(t('du_title'))),
      body: PageFrame(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: pal.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: pal.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('my_id'),
                      style: TextStyle(color: pal.subtext, fontSize: 12.5)),
                  Text(s.publicId.isEmpty ? '—' : s.publicId,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: pal.text)),
                  const SizedBox(height: 14),
                  Text(t('du_time'),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: pal.subtext,
                          fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    for (var i = 0; i < _presets.length; i++)
                      ChoiceChip(
                        label: Text('${_presets[i].$1}+${_presets[i].$2}'),
                        selected: _sel == i,
                        selectedColor: pal.accent.withAlpha(0x55),
                        onSelected: waiting ? null : (_) => setState(() => _sel = i),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                          value: false,
                          icon: const Icon(Icons.handshake_outlined),
                          label: Text(t('du_friendly_opt'))),
                      ButtonSegment(
                          value: true,
                          icon: const Icon(Icons.emoji_events_outlined),
                          label: Text(t('du_rated_opt'))),
                    ],
                    selected: {_rated},
                    onSelectionChanged:
                        waiting ? null : (v) => setState(() => _rated = v.first),
                  ),
                  const SizedBox(height: 4),
                  Text(_rated ? t('du_rated_hint') : t('du_friendly'),
                      style: TextStyle(fontSize: 11.5, color: pal.subtext)),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: Text(t('pe_pick_from_list'),
                          style: TextStyle(color: pal.subtext, fontSize: 12.5)),
                    ),
                    PeopleSearchButton(
                      settings: s,
                      pal: pal,
                      onPick: (u) => setState(
                          () => _idCtl.text = '${u['publicId']}'),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _idCtl,
                    enabled: !waiting,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: t('du_opp_id'),
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _invite(),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: waiting ? null : _invite,
                    icon: const Icon(Icons.sports_martial_arts),
                    label: Text(t('du_send')),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: waiting ? null : _random,
                    icon: const Icon(Icons.shuffle),
                    label: Text(t('du_random')),
                  ),
                  if (waiting) ...[
                    const SizedBox(height: 14),
                    Row(children: [
                      const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            _mode == 'queue' ? t('du_searching') : t('du_waiting'),
                            style: TextStyle(color: pal.text)),
                      ),
                      TextButton(onPressed: _cancel, child: Text(t('co_cancel'))),
                    ]),
                  ],
                  if (_msg != null) ...[
                    const SizedBox(height: 10),
                    Text(_msg!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class OnlineGamePage extends StatefulWidget {
  const OnlineGamePage({
    super.key,
    required this.settings,
    required this.pal,
    required this.gameId,
  });
  final AppSettings settings;
  final Pal pal;
  final String gameId;
  @override
  State<OnlineGamePage> createState() => _OnlineGamePageState();
}

class _OnlineGamePageState extends State<OnlineGamePage> {
  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);

  ch.Chess _game = ch.Chess();
  final List<MoveRecord> _log = [];
  final List<String> _uci = [];
  final List<(String, String)> _premoves = [];
  Map<String, dynamic>? _v;
  DateTime _vAt = DateTime.now();
  Timer? _poll;
  Timer? _tick;
  int _boardKey = 0;
  bool _busy = false;
  bool _soundEnd = false;
  bool _saved = false;
  String? _error;

  bool get _iWhite => (_v?['color'] ?? 'w') == 'w';
  bool get _over => _v != null && _v!['status'] != 'play';
  bool get _myTurn =>
      _v != null &&
      !_over &&
      (_game.turn == ch.Color.WHITE) == _iWhite;

  @override
  void initState() {
    super.initState();
    _fetch();
    _poll = Timer.periodic(const Duration(milliseconds: 1000), (_) => _fetch());
    _tick = Timer.periodic(
        const Duration(milliseconds: 250), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  MoveRecord? _applyUci(String uci) {
    final from = uci.substring(0, 2), to = uci.substring(2, 4);
    final promo = uci.length > 4 ? uci.substring(4) : 'q';
    final mover = _game.get(from);
    final target = _game.get(to);
    PieceKind? cap = target == null ? null : kindOf(target.type);
    if (cap == null &&
        mover != null &&
        mover.type == ch.PieceType.PAWN &&
        from[0] != to[0]) {
      cap = PieceKind.pawn;
    }
    final legal = (_game.moves({'verbose': true}) as List).cast<Map>();
    final m = legal.where((x) => x['from'] == from && x['to'] == to).toList();
    if (m.isEmpty) return null;
    final san = m.first['san']?.toString() ?? uci;
    _game.move({'from': from, 'to': to, 'promotion': promo});
    return MoveRecord(
      san: san,
      from: from,
      to: to,
      white: mover?.color == ch.Color.WHITE,
      captured: cap,
    );
  }

  void _rebuild(List moves) {
    _game = ch.Chess();
    _log.clear();
    _uci.clear();
    for (final m in moves) {
      final u = (m as Map)['uci'].toString();
      final r = _applyUci(u);
      if (r == null) break;
      _log.add(r);
      _uci.add(u);
    }
    _boardKey++;
  }

  Future<void> _fetch() async {
    if (_busy) return;
    _busy = true;
    try {
      final v = await Api.get('/duel/game/${widget.gameId}', s.token!);
      if (!mounted) return;
      _consume(v);
    } on ApiException catch (e) {
      if (mounted && e.code == 'duel_game_gone') {
        setState(() => _error = t(e.l10nKey));
        _poll?.cancel();
      }
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  void _consume(Map<String, dynamic> v) {
    final moves = (v['moves'] as List?) ?? const [];
    setState(() {
      _v = v;
      _vAt = DateTime.now();
      var prefixOk = _uci.length <= moves.length;
      for (var i = 0; prefixOk && i < _uci.length; i++) {
        if ((moves[i] as Map)['uci'] != _uci[i]) prefixOk = false;
      }
      if (!prefixOk) {
        _rebuild(moves);
      } else if (_uci.length < moves.length) {
        for (var i = _uci.length; i < moves.length; i++) {
          final u = (moves[i] as Map)['uci'].toString();
          final r = _applyUci(u);
          if (r == null) {
            _rebuild(moves);
            break;
          }
          _log.add(r);
          _uci.add(u);
          Sfx.instance.playSan(r.san);
        }
        _boardKey++;
      }
      if (v['status'] != 'play' && !_soundEnd) {
        _soundEnd = true;
        _premoves.clear();
        final res = v['result'];
        final won = (res == '1-0' && _iWhite) || (res == '0-1' && !_iWhite);
        Sfx.instance.play(res == '1/2-1/2' ? 'draw' : (won ? 'win' : 'lose'),
            delay: const Duration(milliseconds: 300));
      }
    });
    _tryPremove();
  }

  void _tryPremove() {
    if (_premoves.isEmpty || !_myTurn) return;
    final pm = _premoves.removeAt(0);
    final legal = (_game.moves({'verbose': true}) as List).cast<Map>();
    final ok = legal.any((x) => x['from'] == pm.$1 && x['to'] == pm.$2);
    if (!ok) {
      setState(_premoves.clear);
      return;
    }
    final isPromo = legal.any((x) =>
        x['from'] == pm.$1 && x['to'] == pm.$2 && x['promotion'] != null);
    final r = _applyUci('${pm.$1}${pm.$2}${isPromo ? 'q' : ''}');
    if (r == null) return;
    setState(() {
      _log.add(r);
      _uci.add('${pm.$1}${pm.$2}${isPromo ? 'q' : ''}');
      _boardKey++;
    });
    Sfx.instance.playSan(r.san);
    _send(_uci.last, r.san);
  }

  Future<void> _send(String uci, String san) async {
    String? fin;
    if (_game.in_checkmate) {
      fin = 'checkmate';
    } else if (_game.in_stalemate) {
      fin = 'stalemate';
    } else if (_game.in_draw) {
      fin = 'draw';
    }
    try {
      final v = await Api.post('/duel/game/${widget.gameId}/move', s.token!,
          {'uci': uci, 'san': san, if (fin != null) 'finish': fin});
      if (mounted) _consume(v);
    } catch (_) {
      if (mounted) _fetch();
    }
  }

  void _onMoved(MoveRecord r) {
    final promo = r.san.contains('=') ? 'q' : '';
    final u = '${r.from}${r.to}$promo';
    setState(() {
      _log.add(r);
      _uci.add(u);
    });
    _send(u, r.san);
  }

  Future<void> _act(String path, [Map<String, dynamic> body = const {}]) async {
    try {
      final v = await Api.post('/duel/game/${widget.gameId}/$path', s.token!, body);
      if (mounted) _consume(v);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t(e.l10nKey))));
      }
    }
  }

  Future<void> _resign() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('pl_resign')),
        content: Text(t('du_resign_q')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t('co_cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: Text(t('pl_resign'))),
        ],
      ),
    );
    if (ok == true) _act('resign');
  }

  int _left(bool white) {
    final v = _v;
    if (v == null) return 0;
    var ms = (white ? v['wms'] : v['bms']) as int;
    if (v['status'] == 'play' && (v['turn'] == 'w') == white) {
      ms -= DateTime.now().difference(_vAt).inMilliseconds;
    }
    return (ms < 0 ? 0 : ms) ~/ 1000;
  }

  String get _resultKey {
    final r = _v?['result'];
    if (r == '1/2-1/2') return 'du_drawn';
    final won = (r == '1-0' && _iWhite) || (r == '0-1' && !_iWhite);
    return won ? 'du_won' : 'du_lost';
  }

  ({String pgn, String date, String white, String black, String res}) _pgn() {
    final v = _v!;
    final w = (v['white'] as Map?)?['name'] ?? '?';
    final b = (v['black'] as Map?)?['name'] ?? '?';
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    final date = '${n.year}.${two(n.month)}.${two(n.day)}';
    final res = v['status'] == 'play' ? '*' : '${v['result']}';
    final pgn = buildPgn({
      'Event': 'A-CHESS online',
      'Site': 'A-CHESS',
      'Date': date,
      'White': '$w',
      'Black': '$b',
      'Result': res,
      'TimeControl': '${(v['minutes'] as int) * 60}+${v['inc']}',
    }, [for (final r in _log) r.san], res);
    return (pgn: pgn, date: date, white: '$w', black: '$b', res: res);
  }

  Future<void> _save() async {
    if (_saved || _log.isEmpty) return;
    final d = _pgn();
    await s.addSavedGame({
      'id': DateTime.now().millisecondsSinceEpoch,
      'date': d.date,
      'white': d.white,
      'black': d.black,
      'result': d.res,
      'moves': _log.length,
      'pgn': d.pgn,
    });
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t('pl_game_saved'))));
  }

  void _review() {
    final games = parsePgn(_pgn().pgn);
    if (games.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameViewerPage(
        settings: s,
        pal: pal,
        game: games.first,
        autoAnalyze: true,
      ),
    ));
  }

  Widget _player(bool white) {
    final info = (_v?[white ? 'white' : 'black'] as Map?) ?? const {};
    final secs = _left(white);
    final active = _v != null && !_over && (_game.turn == ch.Color.WHITE) == white;
    return Row(
      children: [
        Icon(white ? Icons.circle_outlined : Icons.circle, size: 16, color: pal.text),
        const SizedBox(width: 8),
        Expanded(
          child: Text('${info['name'] ?? ''}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
        ),
        ClockView(
          style: s.clockStyle,
          seconds: secs,
          active: active,
          low: secs <= 20,
          width: 130,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    final last = _log.isEmpty ? null : _log.last;
    final pmColor = (v != null && !_over)
        ? (_iWhite ? ch.Color.WHITE : ch.Color.BLACK)
        : null;
    final offer = v?['drawOffer'];
    final myCol = _iWhite ? 'w' : 'b';
    final board = v == null
        ? const Center(child: CircularProgressIndicator())
        : ChessBoard(
            key: ValueKey(_boardKey),
            game: _game,
            pal: pal,
            style: s.boardStyle,
            lastFrom: last?.from,
            lastTo: last?.to,
            enabled: _myTurn,
            flipped: !_iWhite,
            onMoved: _onMoved,
            premoveColor: pmColor,
            premoves: List.of(_premoves),
            onPremove: (f, t2) => setState(() {
              if (f == null || t2 == null) {
                _premoves.clear();
              } else if (_premoves.length < 10) {
                _premoves.add((f, t2));
              }
            }),
          );

    return Scaffold(
      backgroundColor: pal.bg1,
      appBar: AppBar(
        title: Text(
            '${t('du_title')} · ${v?['rated'] == true ? t('du_rated_opt') : t('du_friendly_opt')}'),
        actions: [
          if (_over)
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(t('du_leave'))),
        ],
      ),
      body: PageFrame(
        child: _error != null
            ? Center(child: Text(_error!, style: TextStyle(color: pal.text)))
            : LayoutBuilder(builder: (context, c) {
                final maxSide = c.maxHeight - 260 > 200 ? c.maxHeight - 260 : 200.0;
                final side = (c.maxWidth - 24).clamp(200.0, maxSide).toDouble();
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _player(!_iWhite),
                    const SizedBox(height: 8),
                    Center(
                      child: SizedBox(width: side, height: side, child: board),
                    ),
                    const SizedBox(height: 8),
                    _player(_iWhite),
                    const SizedBox(height: 10),
                    if (_over)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: pal.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: pal.cardBorder),
                        ),
                        child: Column(children: [
                          Text(t(_resultKey),
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: pal.text)),
                          Text(t('du_r_${v!['reason']}'),
                              style: TextStyle(color: pal.subtext)),
                          if (v['rated'] == true && v['delta'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                () {
                                  final d = v['delta'] as Map;
                                  final mine = _iWhite ? d['w'] : d['b'];
                                  final now = _iWhite ? d['wNew'] : d['bNew'];
                                  return '${t('du_rating')}: ${(mine as int) >= 0 ? '+' : ''}$mine  →  $now';
                                }(),
                                style: TextStyle(
                                    color: pal.text, fontWeight: FontWeight.w700),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 6, children: [
                            OutlinedButton.icon(
                              onPressed: _saved ? null : _save,
                              icon: const Icon(Icons.bookmark_add_outlined),
                              label: Text(t(_saved ? 'pl_game_saved' : 'pl_save_game')),
                            ),
                            FilledButton.icon(
                              onPressed: _log.isEmpty ? null : _review,
                              icon: const Icon(Icons.analytics_outlined),
                              label: Text(t('du_review')),
                            ),
                          ]),
                        ]),
                      )
                    else ...[
                      if (offer != null && offer != myCol)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0x33F2B705),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(children: [
                            Expanded(child: Text(t('du_draw_offer'))),
                            TextButton(
                                onPressed: () => _act('draw', {'action': 'decline'}),
                                child: Text(t('du_decline'))),
                            FilledButton(
                                onPressed: () => _act('draw', {'action': 'accept'}),
                                child: Text(t('du_accept'))),
                          ]),
                        ),
                      Row(children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFF2B705),
                              foregroundColor: const Color(0xFF2B2100),
                              disabledBackgroundColor: const Color(0x55F2B705),
                            ),
                            onPressed: (_log.length < 2 || offer == myCol)
                                ? null
                                : () => _act('draw', {'action': 'offer'}),
                            icon: const Icon(Icons.handshake_outlined, size: 20),
                            label: Text(t(offer == myCol ? 'du_draw_sent' : 'pl_draw')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFD93025),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _resign,
                            icon: const Icon(Icons.flag_outlined, size: 20),
                            label: Text(t('pl_resign')),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        _myTurn ? t('du_my_turn') : t('du_opp_turn'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: pal.subtext, fontSize: 12.5),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      [
                        for (var i = 0; i < _log.length; i++)
                          '${i.isEven ? '${i ~/ 2 + 1}. ' : ''}${_log[i].san}',
                      ].join(' '),
                      style: TextStyle(color: pal.text, fontSize: 13.5),
                    ),
                  ],
                );
              }),
      ),
    );
  }
}
