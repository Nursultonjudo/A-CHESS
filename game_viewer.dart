import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chess/chess.dart' as ch;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analysis.dart';
import 'l10n.dart';
import 'pgn.dart';
import 'settings.dart';
import 'widgets/chess_board.dart';

// ---------------------------------------------------------------------------
// Doska + boshqaruv + tahlil + PGN paneli (partiya va debyut liniyalari uchun)
// ---------------------------------------------------------------------------

class GameBoardPanel extends StatefulWidget {
  const GameBoardPanel({
    super.key,
    required this.settings,
    required this.pal,
    required this.sans,
    required this.headers,
    required this.result,
    this.practice = false,
    this.startPly = 0,
  });
  final AppSettings settings;
  final Pal pal;
  final List<String> sans;
  final Map<String, String> headers;
  final String result;
  final bool practice; // debyut liniyasi: mashq rejimi mavjud
  final int startPly;

  @override
  State<GameBoardPanel> createState() => _GameBoardPanelState();
}

class _GameBoardPanelState extends State<GameBoardPanel> {
  late final ReplayResult _rr;
  late ch.Chess _game;
  int _ply = 0;
  int _boardKey = 0;
  int _section = 0; // 0 yurishlar, 1 tahlil, 2 PGN
  Timer? _auto;

  // tahlil
  GameAnalysis? _an;
  bool _running = false;
  bool _cancel = false;
  int _done = 0;
  int _total = 0;
  int _ms = 800;
  String _anError = '';
  bool _annotatedPgn = true;

  // mashq
  bool _practice = false;
  bool _userWhite = true;
  bool _waiting = false;
  String _msg = '';
  bool _msgOk = true;
  Timer? _opp;

  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);
  int get _n => _rr.sans.length;

  @override
  void initState() {
    super.initState();
    _rr = replaySans(widget.sans);
    _ply = widget.startPly.clamp(0, _n);
    _game = ch.Chess.fromFEN(_rr.fens[_ply]);
    _loadSaved();
  }

  @override
  void dispose() {
    _cancel = true;
    _auto?.cancel();
    _opp?.cancel();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    try {
      final p = await SharedPreferences.getInstance();
      final ms = p.getInt('an_ms');
      if (ms != null && mounted) setState(() => _ms = ms);
    } catch (_) {}
    final a = await loadAnalysis(_rr.sans);
    if (a != null && mounted) setState(() => _an = a);
  }

  void _setPly(int n) {
    _ply = n.clamp(0, _n);
    _game = ch.Chess.fromFEN(_rr.fens[_ply]);
    _boardKey++;
  }

  void _goto(int n) {
    _auto?.cancel();
    setState(() => _setPly(n));
  }

  void _toggleAuto() {
    if (_auto?.isActive ?? false) {
      _auto!.cancel();
      setState(() {});
      return;
    }
    if (_ply >= _n) _setPly(0);
    _auto = Timer.periodic(const Duration(milliseconds: 900), (tm) {
      if (!mounted || _ply >= _n) {
        tm.cancel();
        if (mounted) setState(() {});
        return;
      }
      setState(() => _setPly(_ply + 1));
    });
    setState(() {});
  }

  // ---- tahlil ----------------------------------------------------------------

  Future<void> _startAnalysis() async {
    if (_running) return;
    setState(() {
      _running = true;
      _cancel = false;
      _done = 0;
      _total = _rr.fens.length;
      _anError = '';
    });
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('an_ms', _ms);
    } catch (_) {}
    final res = await runAnalysis(
      _rr,
      movetimeMs: _ms,
      onProgress: (d, tt) {
        if (mounted) {
          setState(() {
            _done = d;
            _total = tt;
          });
        }
      },
      cancelled: () => _cancel || !mounted,
    );
    if (!mounted) return;
    if (res != null) {
      await saveAnalysis(_rr.sans, res);
      setState(() {
        _an = res;
        _running = false;
      });
    } else {
      setState(() {
        _running = false;
        if (!_cancel) _anError = t('an_no_engine');
      });
    }
  }

  void _stopAnalysis() {
    _cancel = true;
    setState(() {});
  }

  MoveQuality? _q(int ply) {
    final a = _an;
    if (a == null || ply < 1 || ply > a.plies || ply > _rr.ucis.length) {
      return null;
    }
    return a.quality(ply, _rr.ucis[ply - 1]);
  }

  Color _qColor(MoveQuality q) {
    switch (q) {
      case MoveQuality.best:
        return const Color(0xFF22C55E);
      case MoveQuality.good:
        return const Color(0xFF86EFAC);
      case MoveQuality.inaccuracy:
        return const Color(0xFFFACC15);
      case MoveQuality.mistake:
        return const Color(0xFFF97316);
      case MoveQuality.blunder:
        return const Color(0xFFEF4444);
    }
  }

  String _qSuffix(MoveQuality? q) {
    switch (q) {
      case MoveQuality.inaccuracy:
        return '?!';
      case MoveQuality.mistake:
        return '?';
      case MoveQuality.blunder:
        return '??';
      default:
        return '';
    }
  }

  // ---- mashq -----------------------------------------------------------------

  void _startPractice(bool white) {
    _auto?.cancel();
    _opp?.cancel();
    setState(() {
      _practice = true;
      _userWhite = white;
      _setPly(0);
      _msg = t('ol_your_move');
      _msgOk = true;
      _waiting = false;
      _section = 0;
    });
    _maybeOpponent();
  }

  bool get _userTurn =>
      _game.turn == (_userWhite ? ch.Color.WHITE : ch.Color.BLACK);
  bool get _finished => _ply >= _n;

  void _maybeOpponent() {
    if (!_practice || _finished || _userTurn) return;
    _waiting = true;
    _opp?.cancel();
    _opp = Timer(const Duration(milliseconds: 600), () {
      if (!mounted || !_practice) return;
      setState(() {
        _setPly(_ply + 1);
        _waiting = false;
        _msg = _finished ? t('ol_done') : t('ol_your_move');
        _msgOk = true;
      });
    });
  }

  void _onUserMove(MoveRecord r) {
    if (_finished) {
      _game.undo_move();
      setState(() => _boardKey++);
      return;
    }
    final exp = _rr.ucis[_ply];
    if (exp.length >= 4 && r.from == exp.substring(0, 2) && r.to == exp.substring(2, 4)) {
      setState(() {
        _ply++;
        _msg = _finished ? t('ol_done') : t('ol_correct');
        _msgOk = true;
      });
      _maybeOpponent();
    } else {
      _game.undo_move();
      setState(() {
        _boardKey++;
        _msg = t('ol_wrong');
        _msgOk = false;
      });
    }
  }

  void _hint() {
    if (_finished) return;
    setState(() {
      _msg = t('ol_hint_is', {'m': _rr.sans[_ply]});
      _msgOk = true;
    });
  }

  // ---- PGN -------------------------------------------------------------------

  String _pgnText() {
    final h = Map<String, String>.from(widget.headers);
    final a = _an;
    List<String>? suffix;
    List<String>? comments;
    if (_annotatedPgn && a != null) {
      suffix = [];
      comments = [];
      for (var i = 1; i <= _n; i++) {
        suffix.add(_qSuffix(_q(i)));
        comments.add('[%eval ${(a.evals[i].abs() >= 90000 ? '#${100000 - a.evals[i].abs()}' : (a.evals[i] / 100).toStringAsFixed(2))}]');
      }
    }
    return buildPgn(h, _rr.sans, widget.result,
        suffix: suffix, comments: comments);
  }

  Future<void> _copyPgn() async {
    await Clipboard.setData(ClipboardData(text: _pgnText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t('pgn_copied'))),
    );
  }

  Future<void> _savePgn() async {
    final text = _pgnText();
    final bytes = Uint8List.fromList(utf8.encode(text));
    try {
      final name =
          '${(widget.headers['White'] ?? 'game').replaceAll(RegExp(r'[^\w]+'), '_')}.pgn';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'PGN',
        fileName: name,
        bytes: bytes,
      );
      if (path != null && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        await File(path).writeAsBytes(bytes);
      }
      if (!mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('pgn_saved'))),
        );
      }
    } catch (_) {
      await _copyPgn();
    }
  }

  // ---- UI --------------------------------------------------------------------

  Widget _ctl(IconData icon, VoidCallback? onTap, {bool big = false}) =>
      IconButton.filledTonal(
        onPressed: onTap,
        icon: Icon(icon, size: big ? 30 : 24),
      );

  Widget _board() {
    final last = _ply > 0 && _ply <= _rr.ucis.length ? _rr.ucis[_ply - 1] : null;
    final a = _an;
    final showBar = !_practice && a != null;
    return LayoutBuilder(
      builder: (context, c) {
        final size = c.maxWidth - (showBar ? 22 : 0);
        return SizedBox(
          height: size,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showBar) ...[
                SizedBox(
                  width: 14,
                  child: EvalBar(
                    balance: 0,
                    pal: pal,
                    whiteFrac: a.winPct(_ply.clamp(0, a.plies)) / 100,
                    label: labelOfPacked(a.evals[_ply.clamp(0, a.plies)]),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: ChessBoard(
                  key: ValueKey(_boardKey),
                  game: _game,
                  pal: pal,
                  style: s.boardStyle,
                  lastFrom: last?.substring(0, 2),
                  lastTo: last?.substring(2, 4),
                  flipped: _practice && !_userWhite,
                  enabled: _practice && !_finished && _userTurn && !_waiting,
                  onMoved: _onUserMove,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _controls() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ctl(Icons.first_page, _ply > 0 ? () => _goto(0) : null),
          const SizedBox(width: 8),
          _ctl(Icons.chevron_left, _ply > 0 ? () => _goto(_ply - 1) : null),
          const SizedBox(width: 8),
          _ctl(
            (_auto?.isActive ?? false) ? Icons.pause : Icons.play_arrow,
            _toggleAuto,
            big: true,
          ),
          const SizedBox(width: 8),
          _ctl(Icons.chevron_right, _ply < _n ? () => _goto(_ply + 1) : null),
          const SizedBox(width: 8),
          _ctl(Icons.last_page, _ply < _n ? () => _goto(_n) : null),
        ],
      );

  Widget _engineLine() {
    final a = _an;
    if (a == null || _practice) return const SizedBox.shrink();
    final i = _ply.clamp(0, a.plies);
    final uci = a.best[i];
    final san = uci.isEmpty ? null : uciToSan(_rr.fens[i], uci);
    final lbl = labelOfPacked(a.evals[i]);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: pal.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: pal.cardBorder),
        ),
        child: Text(
          san == null
              ? '${t('an_eval')}: $lbl'
              : '${t('an_eval')}: $lbl   ·   ${t('an_engine_best', {'m': san})}',
          style: TextStyle(fontWeight: FontWeight.w700, color: pal.text),
        ),
      ),
    );
  }

  Widget _movesWrap() {
    final chips = <Widget>[];
    for (var i = 0; i < _n; i++) {
      if (i.isEven) {
        chips.add(Padding(
          padding: const EdgeInsets.only(top: 6, right: 2),
          child: Text('${i ~/ 2 + 1}.',
              style: TextStyle(color: pal.subtext, fontSize: 13)),
        ));
      }
      final cur = _ply == i + 1;
      final hidden = _practice && i >= _ply;
      final q = hidden ? null : _q(i + 1);
      final qc = q == null || q == MoveQuality.good || q == MoveQuality.best
          ? null
          : _qColor(q);
      chips.add(InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _practice ? null : () => _goto(i + 1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: cur ? pal.accentSoft : qc?.withAlpha(0x33),
            borderRadius: BorderRadius.circular(6),
            border: cur ? Border.all(color: pal.accent) : null,
          ),
          child: Text(
            hidden ? '···' : '${_rr.sans[i]}${_qSuffix(q)}',
            style: TextStyle(
              fontWeight: cur ? FontWeight.w800 : FontWeight.w600,
              color: pal.text,
            ),
          ),
        ),
      ));
    }
    return Wrap(spacing: 2, runSpacing: 2, children: chips);
  }

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: pal.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: pal.cardBorder),
        ),
        child: child,
      );

  Widget _sectionMoves() => _card(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('ol_moves'),
              style: TextStyle(fontWeight: FontWeight.w800, color: pal.text)),
          const SizedBox(height: 6),
          _movesWrap(),
          if (_rr.sans.length < widget.sans.length) ...[
            const SizedBox(height: 6),
            Text(t('ol_truncated'),
                style: TextStyle(fontSize: 12, color: pal.subtext)),
          ],
        ],
      ));

  Widget _countRow(String label, MoveQuality q, int w, int b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _qColor(q),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: TextStyle(color: pal.text))),
            SizedBox(
              width: 44,
              child: Text('$w',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: pal.text)),
            ),
            SizedBox(
              width: 44,
              child: Text('$b',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: pal.text)),
            ),
          ],
        ),
      );

  Widget _sectionAnalysis() {
    final a = _an;
    final chips = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('${t('an_time')}:', style: TextStyle(color: pal.subtext)),
        for (final v in const [300, 800, 2000, 5000])
          ChoiceChip(
            label: Text('${v / 1000} s'),
            selected: _ms == v,
            onSelected: _running ? null : (_) => setState(() => _ms = v),
          ),
      ],
    );
    if (_running) {
      return _card(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('an_running', {'a': '$_done', 'b': '$_total'}),
              style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _stopAnalysis,
            icon: const Icon(Icons.stop, size: 18),
            label: Text(t('an_stop')),
          ),
        ],
      ));
    }
    if (a == null) {
      return _card(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('an_intro'), style: TextStyle(color: pal.text)),
          const SizedBox(height: 10),
          chips,
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _startAnalysis,
            icon: const Icon(Icons.psychology, size: 20),
            label: Text(t('an_start')),
          ),
          if (_anError.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_anError, style: const TextStyle(color: Colors.redAccent)),
          ],
        ],
      ));
    }
    final cnt = {
      for (final q in MoveQuality.values) q: [0, 0],
    };
    for (var p = 1; p <= a.plies && p <= _rr.ucis.length; p++) {
      final q = _q(p);
      if (q == null) continue;
      cnt[q]![p.isOdd ? 0 : 1]++;
    }
    // eng katta xato
    var worst = 0;
    var worstLoss = 0.0;
    for (var p = 1; p <= a.plies; p++) {
      final l = a.loss(p);
      if (l > worstLoss) {
        worstLoss = l;
        worst = p;
      }
    }
    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('an_graph'),
            style: TextStyle(fontWeight: FontWeight.w800, color: pal.text)),
        const SizedBox(height: 8),
        EvalGraph(
          analysis: a,
          current: _ply,
          onSelect: (i) => _goto(i),
          lineColor: pal.accent,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                '${t('an_acc_white')}: ${a.accuracy(true).toStringAsFixed(1)}%',
                style: TextStyle(fontWeight: FontWeight.w800, color: pal.text),
              ),
            ),
            Expanded(
              child: Text(
                '${t('an_acc_black')}: ${a.accuracy(false).toStringAsFixed(1)}%',
                style: TextStyle(fontWeight: FontWeight.w800, color: pal.text),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Spacer(),
            SizedBox(
                width: 44,
                child: Text(t('an_w'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: pal.subtext))),
            SizedBox(
                width: 44,
                child: Text(t('an_b'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: pal.subtext))),
          ],
        ),
        _countRow(t('an_best'), MoveQuality.best, cnt[MoveQuality.best]![0],
            cnt[MoveQuality.best]![1]),
        _countRow(t('an_good'), MoveQuality.good, cnt[MoveQuality.good]![0],
            cnt[MoveQuality.good]![1]),
        _countRow(t('an_inacc'), MoveQuality.inaccuracy,
            cnt[MoveQuality.inaccuracy]![0], cnt[MoveQuality.inaccuracy]![1]),
        _countRow(t('an_mistake'), MoveQuality.mistake,
            cnt[MoveQuality.mistake]![0], cnt[MoveQuality.mistake]![1]),
        _countRow(t('an_blunder'), MoveQuality.blunder,
            cnt[MoveQuality.blunder]![0], cnt[MoveQuality.blunder]![1]),
        if (worst > 0 && worstLoss >= 10) ...[
          const SizedBox(height: 10),
          InkWell(
            onTap: () => _goto(worst),
            child: Text(
              t('an_worst', {
                'm': '${(worst + 1) ~/ 2}${worst.isOdd ? '.' : '...'}${_rr.sans[worst - 1]}',
                'l': worstLoss.toStringAsFixed(0),
              }),
              style: TextStyle(
                color: pal.accent,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        chips,
        const SizedBox(height: 8),
        Text(t('an_done_ms', {'s': (a.ms / 1000).toStringAsFixed(1)}),
            style: TextStyle(fontSize: 12, color: pal.subtext)),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _startAnalysis,
          icon: const Icon(Icons.refresh, size: 20),
          label: Text(t('an_rerun')),
        ),
      ],
    ));
  }

  Widget _sectionPgn() => _card(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('PGN',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: pal.text)),
              const Spacer(),
              if (_an != null)
                FilterChip(
                  label: Text(t('pgn_annotated')),
                  selected: _annotatedPgn,
                  onSelected: (v) => setState(() => _annotatedPgn = v),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: pal.bg1,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: pal.cardBorder),
            ),
            child: SelectableText(
              _pgnText(),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                color: pal.text,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.icon(
                onPressed: _copyPgn,
                icon: const Icon(Icons.copy, size: 18),
                label: Text(t('pgn_copy')),
              ),
              OutlinedButton.icon(
                onPressed: _savePgn,
                icon: const Icon(Icons.save_alt, size: 18),
                label: Text(t('pgn_save')),
              ),
            ],
          ),
        ],
      ));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _board(),
        const SizedBox(height: 12),
        if (!_practice) ...[
          _controls(),
          _engineLine(),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _msgOk ? const Color(0x3343A047) : const Color(0x33E53935),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: pal.cardBorder),
            ),
            child: Text(_msg,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: pal.text)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: _finished ? null : _hint,
                icon: const Icon(Icons.lightbulb_outline, size: 18),
                label: Text(t('ol_hint')),
              ),
              OutlinedButton.icon(
                onPressed: () => _startPractice(_userWhite),
                icon: const Icon(Icons.replay, size: 18),
                label: Text(t('ol_restart')),
              ),
              FilledButton.icon(
                onPressed: () {
                  _opp?.cancel();
                  setState(() {
                    _practice = false;
                    _waiting = false;
                    _setPly(0);
                  });
                },
                icon: const Icon(Icons.visibility, size: 18),
                label: Text(t('ol_view')),
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        if (widget.practice && !_practice) ...[
          Text(t('ol_practice'),
              style: TextStyle(fontWeight: FontWeight.w800, color: pal.text)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.icon(
                onPressed: () => _startPractice(true),
                icon: const Icon(Icons.circle_outlined, size: 18),
                label: Text(t('ol_play_white')),
              ),
              FilledButton.icon(
                onPressed: () => _startPractice(false),
                icon: const Icon(Icons.circle, size: 18),
                label: Text(t('ol_play_black')),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (!_practice)
          Wrap(
            spacing: 8,
            children: [
              for (final e in [
                (0, t('sec_moves')),
                (1, t('sec_analysis')),
                (2, 'PGN'),
              ])
                ChoiceChip(
                  label: Text(e.$2),
                  selected: _section == e.$1,
                  onSelected: (_) => setState(() => _section = e.$1),
                ),
            ],
          ),
        const SizedBox(height: 10),
        if (_practice || _section == 0)
          _sectionMoves()
        else if (_section == 1)
          _sectionAnalysis()
        else
          _sectionPgn(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bitta partiyani ochadigan sahifa
// ---------------------------------------------------------------------------

class GameViewerPage extends StatelessWidget {
  const GameViewerPage({
    super.key,
    required this.settings,
    required this.pal,
    required this.game,
  });
  final AppSettings settings;
  final Pal pal;
  final PgnGame game;

  @override
  Widget build(BuildContext context) {
    final g = game;
    final title = '${g.white} – ${g.black}';
    final sub = [
      if (g.event.isNotEmpty && g.event != '?') g.event,
      if (g.year.isNotEmpty) g.year,
      if (g.eco.isNotEmpty) g.eco,
      g.res,
    ].join(' · ');
    return Scaffold(
      backgroundColor: pal.bg1,
      appBar: AppBar(title: Text(title, style: const TextStyle(fontSize: 16))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Text(sub, style: TextStyle(color: pal.subtext)),
              const SizedBox(height: 10),
              GameBoardPanel(
                settings: settings,
                pal: pal,
                sans: g.sans,
                headers: g.headers,
                result: g.res,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PGN fayl (baza) sahifasi: ChessBase uslubida ko'p partiyali PGN ochish
// ---------------------------------------------------------------------------

class PgnDatabasePage extends StatefulWidget {
  const PgnDatabasePage({super.key, required this.settings, required this.pal});
  final AppSettings settings;
  final Pal pal;

  @override
  State<PgnDatabasePage> createState() => _PgnDatabasePageState();
}

class _PgnDatabasePageState extends State<PgnDatabasePage> {
  List<PgnGame> _games = [];
  String _name = '';
  String _q = '';
  bool _loading = false;
  String _error = '';

  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);

  Future<void> _load(String text, String name) async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final games = await compute(parsePgn, text);
      if (!mounted) return;
      setState(() {
        _games = games;
        _name = name;
        _loading = false;
        if (games.isEmpty) _error = t('db_empty');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = t('db_error');
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      final f = res?.files.single;
      if (f == null) return;
      Uint8List? bytes = f.bytes;
      if (bytes == null && f.path != null) {
        bytes = await File(f.path!).readAsBytes();
      }
      if (bytes == null) return;
      String text;
      try {
        text = utf8.decode(bytes);
      } catch (_) {
        text = latin1.decode(bytes);
      }
      await _load(text, f.name);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = t('db_error'));
    }
  }

  Future<void> _paste() async {
    final ctl = TextEditingController();
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (clip?.text != null && clip!.text!.contains('[')) {
      ctl.text = clip.text!;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('db_paste')),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: ctl,
            minLines: 8,
            maxLines: 14,
            decoration: const InputDecoration(
              hintText: '[Event "?"]\n[White "?"]\n...\n\n1. e4 e5 2. Nf3 ...',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('co_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('db_open_btn')),
          ),
        ],
      ),
    );
    final text = ctl.text;
    ctl.dispose();
    if (ok == true && text.trim().isNotEmpty) {
      await _load(text, 'PGN');
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? _games
        : [
            for (final g in _games)
              if ('${g.white} ${g.black} ${g.event} ${g.eco} ${g.date} ${g.opening}'
                  .toLowerCase()
                  .contains(q))
                g,
          ];
    return Scaffold(
      backgroundColor: pal.bg1,
      appBar: AppBar(title: Text(t('db_title'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        FilledButton.icon(
                          onPressed: _loading ? null : _pickFile,
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: Text(t('db_open')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _loading ? null : _paste,
                          icon: const Icon(Icons.content_paste, size: 18),
                          label: Text(t('db_paste')),
                        ),
                      ],
                    ),
                    if (_games.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      TextField(
                        onChanged: (v) => setState(() => _q = v),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: t('db_filter'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$_name · ${t('db_games', {'n': '${list.length}'})}',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: pal.text),
                      ),
                    ],
                    if (_loading) ...[
                      const SizedBox(height: 10),
                      const LinearProgressIndicator(),
                    ],
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_error,
                          style: const TextStyle(color: Colors.redAccent)),
                    ],
                    if (_games.isEmpty && !_loading && _error.isEmpty) ...[
                      const SizedBox(height: 14),
                      Text(t('db_hint'), style: TextStyle(color: pal.subtext)),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final g = list[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: pal.card,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => GameViewerPage(
                                settings: s,
                                pal: pal,
                                game: g,
                              ),
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: pal.cardBorder),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${g.white} – ${g.black}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: pal.text,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        [
                                          if (g.event.isNotEmpty &&
                                              g.event != '?')
                                            g.event,
                                          if (g.year.isNotEmpty) g.year,
                                          if (g.eco.isNotEmpty) g.eco,
                                          t('db_moves',
                                              {'n': '${(g.sans.length + 1) ~/ 2}'}),
                                        ].join(' · '),
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            color: pal.subtext),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  g.res,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: pal.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
