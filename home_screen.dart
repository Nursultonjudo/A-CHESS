import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chess/chess.dart' as ch;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../l10n.dart';
import '../settings.dart';
import '../widgets/chess_board.dart';

/// Asosiy oyna: chap tomonda menyu, o'rtada doska, o'ngda yurishlar va boshqaruv.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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

  AppSettings get s => widget.settings;
  Pal get pal => Pal.of(s.boardStyle, s.dark);
  String t(String key, [Map<String, String> args = const {}]) =>
      tr(s.lang, key, args);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _loadRating();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _firstCtl.dispose();
    _lastCtl.dispose();
    super.dispose();
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

  void _onMoved(MoveRecord r) => setState(() => _log.add(r));

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
  }

  void _undo() {
    if (_log.isEmpty) return;
    setState(() {
      _game.undo_move();
      _log.removeLast();
      _timeoutLoser = null;
      _boardKey++;
    });
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
        borderRadius: BorderRadius.circular(16),
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

  Widget _timeChips() {
    final w = pal;
    const options = [3, 5, 10, 30];
    return Container(
      padding: const EdgeInsets.all(14),
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
    return ChessBoard(
      key: ValueKey(_boardKey),
      game: _game,
      pal: pal,
      style: s.boardStyle,
      lastFrom: last?.from,
      lastTo: last?.to,
      enabled: !_over,
      onMoved: _onMoved,
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
            borderRadius: BorderRadius.circular(24),
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
            : (_tab == 0 ? _playView(cc) : _infoView()),
      );



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

  Future<void> _saveProfile() async {
    await s.setName(_firstCtl.text.trim(), _lastCtl.text.trim());
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
            borderRadius: BorderRadius.circular(24),
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

  void _showAppearance() {
    showDialog<void>(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: s,
        builder: (_, __) {
          final p = pal;
          final boards = ['style_wood', 'style_marble', 'style_modern'];
          final clocks = ['clock_lcd', 'clock_flip', 'clock_classic'];
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
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
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

  Widget _langButton() {
    return PopupMenuButton<String>(
      tooltip: t('language'),
      onSelected: (v) => s.setLang(v),
      itemBuilder: (_) => [
        for (final e in languageNames.entries)
          PopupMenuItem(value: e.key, child: Text(e.value)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: pal.accent.withAlpha(0x66)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.language, size: 18, color: pal.accent),
            const SizedBox(width: 6),
            Text(
              s.lang.toUpperCase(),
              style: TextStyle(
                color: pal.navText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _themeButton() => IconButton(
        tooltip: t('theme'),
        icon: Icon(
          s.dark ? Icons.light_mode : Icons.dark_mode,
          color: pal.navIcon,
        ),
        onPressed: () => s.setDark(!s.dark),
      );

  Widget _paletteButton() => IconButton(
        tooltip: t('appearance'),
        icon: Icon(Icons.palette_outlined, color: pal.navIcon),
        onPressed: _showAppearance,
      );

  Widget _logoutButton() => IconButton(
        tooltip: t('logout'),
        icon: Icon(Icons.logout, color: pal.navIcon),
        onPressed: () => s.signOut(),
      );

  List<(IconData, String)> get _tabs => [
        (Icons.sports_esports, t('nav_play')),
        (Icons.leaderboard, t('nav_rating')),
        (Icons.insights, t('nav_stats')),
        (Icons.assignment, t('nav_tasks')),
      ];

  Widget _navTile(IconData icon, String label, int i) {
    final sel = !_showProfile && _tab == i;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() {
            _tab = i;
            _showProfile = false;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: sel ? pal.accentSoft : Colors.transparent,
              border: Border.all(
                color: sel ? pal.accent : Colors.transparent,
                width: 1.2,
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
      width: 292,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [pal.navTop, pal.navBottom],
        ),
        boxShadow: [BoxShadow(blurRadius: 16, color: Colors.black38)],
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
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 16),
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
        gradient: LinearGradient(
          colors: [pal.navTop, pal.navBottom],
        ),
        boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black38)],
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
          _langButton(),
          _paletteButton(),
          _themeButton(),
          _logoutButton(),
        ],
      ),
    );
  }

  Widget _bottomNav() {
    final tabs = _tabs;
    return NavigationBar(
      selectedIndex: _tab,
      indicatorColor: pal.accent.withAlpha(0x44),
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
