import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chess/chess.dart' as ch;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../api.dart';
import '../coach.dart';
import '../config.dart';
import '../engine.dart';
import '../l10n.dart';
import '../puzzles.dart';
import '../lessons.dart';
import '../settings.dart';
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
  int _baseSeconds = 600;
  int _whiteLeft = 600;
  int _blackLeft = 600;
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
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_appActive) s.tickActivity();
      _tick();
    });
    _loadRating();
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
        await s.applyServerUser(user.cast<String, dynamic>());
        if (mounted && s.role == null) {
          await showRoleDialog(context, s, pal);
        }
      }
    } catch (_) {
      // Server javob bermasa, reyting o'rniga chiziqcha ko'rsatiladi.
    }
  }

  // ---- O'yin holati -------------------------------------------------------

  bool get _over =>
      _game.in_checkmate || _game.in_draw || _timeoutLoser != null;

  String get _status {
    if (_timeoutLoser != null) {
      final winner = _timeoutLoser == 'white' ? t('black') : t('white');
      return t('timeout', {'winner': winner});
    }
    if (_game.in_checkmate) {
      final winner = _game.turn == ch.Color.WHITE ? t('black') : t('white');
      return t('checkmate', {'winner': winner});
    }
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
  }

  void _requestEval() {
    if (!s.engineOn || !mounted) return;
    if (_over) {
      _engine.clear();
    } else {
      _engine.analyze(_game.fen);
    }
  }

  void _onMoved(MoveRecord r) {
    setState(() => _log.add(r));
    _requestEval();
  }

  void _newGame([int? seconds]) {
    setState(() {
      if (seconds != null) _baseSeconds = seconds;
      _game.reset();
      _log.clear();
      _whiteLeft = _baseSeconds;
      _blackLeft = _baseSeconds;
      _timeoutLoser = null;
      _boardKey++;
    });
    _requestEval();
  }

  void _undo() {
    if (_log.isEmpty) return;
    setState(() {
      _game.undo_move();
      _log.removeLast();
      _timeoutLoser = null;
      _boardKey++;
    });
    _requestEval();
  }

  List<PieceKind> _capturedBy(bool white) => [
        for (final r in _log)
          if (r.white == white && r.captured != null) r.captured!,
      ];

  int _material(List<PieceKind> list) =>
      list.fold(0, (sum, k) => sum + pieceValue(k));

  // ---- Kartalar va boshqaruv ---------------------------------------------

  Widget _playerCard(bool white) {
    final mine = _capturedBy(white);
    final theirs = _capturedBy(!white);
    final adv = _material(mine) - _material(theirs);
    final left = white ? _whiteLeft : _blackLeft;
    final color = white ? ch.Color.WHITE : ch.Color.BLACK;

    final name = white
        ? (s.fullName.isEmpty ? t('you') : s.fullName)
        : t('opponent');
    return PlayerCard(
      pal: pal,
      boardStyle: s.boardStyle,
      clockStyle: s.clockStyle,
      avatar: white ? s.avatar : null,
      initials: white ? s.initials : '',
      name: name,
      rating: '${_rating ?? '—'}',
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

  Widget _timeChips() {
    final w = pal;
    const options = [3, 5, 10, 30];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: w.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: w.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 18, color: w.accent),
              const SizedBox(width: 8),
              Text(
                t('time_control'),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: w.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in options)
                ChoiceChip(
                  label: Text('$m ${t('minutes_short')}'),
                  selected: _baseSeconds == m * 60,
                  selectedColor: w.accent.withAlpha(0x55),
                  onSelected: (_) => _newGame(m * 60),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buttons() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _newGame(),
            icon: const Icon(Icons.refresh),
            label: Text(t('new_game')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _log.isEmpty ? null : _undo,
            icon: const Icon(Icons.undo),
            label: Text(t('undo')),
          ),
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
      enabled: !_over,
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
      const panelW = 330.0;
      const cardH = 96.0;
      const pad = 20.0;
      final maxH = cc.maxHeight - pad * 2 - cardH * 2 - gap * 2;
      final maxW = cc.maxWidth - pad * 3 - panelW;
      final board = math.max(260.0, math.min(maxH, maxW));

      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(pad),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: board,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _playerCard(false),
                    const SizedBox(height: gap),
                    _board(),
                    const SizedBox(height: gap),
                    _playerCard(true),
                  ],
                ),
              ),
              const SizedBox(width: pad),
              SizedBox(
                width: panelW,
                height: board + cardH * 2 + gap * 2,
                child: Column(
                  children: [
                    _statusCard(),
                    if (s.engineOn) ...[
                      const SizedBox(height: gap),
                      _engineCard(),
                    ],
                    const SizedBox(height: gap),
                    _timeChips(),
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
              _playerCard(false),
              const SizedBox(height: gap),
              _board(),
              const SizedBox(height: gap),
              _playerCard(true),
              const SizedBox(height: gap),
              _statusCard(),
              if (s.engineOn) ...[
                const SizedBox(height: gap),
                _engineCard(),
              ],
              const SizedBox(height: gap),
              _timeChips(),
              const SizedBox(height: gap),
              _buttons(),
              const SizedBox(height: gap),
              SizedBox(height: 260, child: _moveList()),
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
                    : (_tab == 5
                        ? _settingsView()
                        : (_tab == 4
                        ? LessonsView(settings: s, pal: pal)
                        : (_tab == 1
                            ? RatingView(settings: s, pal: pal)
                            : StatsView(settings: s, pal: pal)))))),
      );



  // ---- Sozlamalar oynasi --------------------------------------------------

  Widget _settingsView() {
    final w = pal;
    final modes = [
      (false, Icons.light_mode_outlined, t('light')),
      (true, Icons.dark_mode_outlined, t('dark')),
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
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
        ),
      ),
    );
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
  }

  Future<void> _saveProfile() async {
    await s.setName(_firstCtl.text.trim(), _lastCtl.text.trim());
    final token = s.token;
    if (token != null) {
      try {
        await Api.post('/me/name', token, {
          'firstName': s.firstName,
          'lastName': s.lastName,
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

  void _showAppearance() {
    showDialog<void>(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: s,
        builder: (_, __) {
          final p = pal;
          return Dialog(
            backgroundColor: p.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: p.cardBorder),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.palette_outlined, color: p.accent),
                        const SizedBox(width: 10),
                        Text(
                          t('appearance'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: p.text,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.close, color: p.subtext),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ..._appearanceSections(p),
                  ],
                ),
              ),
            ),
          );
        },
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

  Widget _themeButton({double scale = 1}) => _actionButton(
        icon: s.dark ? Icons.light_mode : Icons.dark_mode,
        tooltip: t('theme'),
        onTap: () => s.setDark(!s.dark),
        scale: scale,
      );

  Widget _paletteButton({double scale = 1}) => _actionButton(
        icon: Icons.palette_outlined,
        tooltip: t('appearance'),
        onTap: _showAppearance,
        scale: scale,
      );

  Widget _logoutButton({double scale = 1}) => _actionButton(
        icon: Icons.logout,
        tooltip: t('logout'),
        onTap: () => s.signOut(),
        scale: scale,
      );

  List<(IconData, String)> get _tabs => [
        (Icons.sports_esports, t('nav_play')),
        (Icons.leaderboard, t('nav_rating')),
        (Icons.insights, t('nav_stats')),
        (Icons.assignment, t('nav_tasks')),
        (Icons.menu_book, t('nav_lessons')),
        (Icons.settings, t('nav_settings')),
      ];

  Widget _navTile(IconData icon, String label, int i) {
    final sel = !_showProfile && _tab == i;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() {
            _tab = i;
            _showProfile = false;
          }),
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
            for (var i = 0; i < tabs.length; i++)
              _navTile(tabs[i].$1, tabs[i].$2, i),
            const Spacer(),
            _profileTile(),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
              child: Row(
                children: [
                  _langButton(),
                  const Spacer(),
                  _paletteButton(),
                  _themeButton(),
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
          _paletteButton(scale: 0.8),
          _themeButton(scale: 0.8),
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
      onDestinationSelected: (i) => setState(() {
        _tab = i;
        _showProfile = false;
      }),
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
