import 'dart:math' as math;

import 'package:chess/chess.dart' as ch;
import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'puzzles.dart';
import 'settings.dart';
import 'widgets/chess_board.dart';

/// Trener uchun boshqotirma yaratish oynasi.
/// Yangi boshqotirma saqlansa, uning id si qaytadi.
Future<int?> showPuzzleMaker(
        BuildContext context, AppSettings s, Pal pal) =>
    Navigator.of(context).push<int>(MaterialPageRoute(
      builder: (_) => PuzzleMakerPage(settings: s, pal: pal),
    ));

class PuzzleMakerPage extends StatefulWidget {
  const PuzzleMakerPage({super.key, required this.settings, required this.pal});
  final AppSettings settings;
  final Pal pal;

  @override
  State<PuzzleMakerPage> createState() => _PuzzleMakerPageState();
}

class _PuzzleMakerPageState extends State<PuzzleMakerPage> {
  // grid[0] = 8-qator (yuqori), grid[7] = 1-qator
  late List<List<String?>> _grid = _startGrid();
  String? _tool; // 'K','q',... yoki 'x' = o'chirgich
  bool _whiteToMove = true;
  int _step = 0;
  final _title = TextEditingController();
  final _fenCtl = TextEditingController();
  String? _error;
  bool _busy = false;

  ch.Chess? _game;
  int _boardKey = 0;
  MoveRecord? _pending;
  final List<String> _solutions = [];

  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);

  @override
  void initState() {
    super.initState();
    loadCustomPuzzles(s);
    customPuzzlesRev.addListener(_refresh);
  }

  @override
  void dispose() {
    customPuzzlesRev.removeListener(_refresh);
    _title.dispose();
    _fenCtl.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  static List<List<String?>> _gridFromPlacement(String placement) {
    final rows = placement.split('/');
    final g = <List<String?>>[];
    for (final r in rows.take(8)) {
      final row = <String?>[];
      for (final c in r.split('')) {
        final n = int.tryParse(c);
        if (n != null) {
          for (var i = 0; i < n; i++) {
            row.add(null);
          }
        } else {
          row.add(c);
        }
      }
      while (row.length < 8) {
        row.add(null);
      }
      g.add(row.take(8).toList());
    }
    while (g.length < 8) {
      g.add(List<String?>.filled(8, null));
    }
    return g;
  }

  static List<List<String?>> _startGrid() =>
      _gridFromPlacement('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR');

  String _placement() {
    final out = <String>[];
    for (final row in _grid) {
      var line = '';
      var empty = 0;
      for (final c in row) {
        if (c == null) {
          empty++;
        } else {
          if (empty > 0) line += '$empty';
          empty = 0;
          line += c;
        }
      }
      if (empty > 0) line += '$empty';
      out.add(line);
    }
    return out.join('/');
  }

  String _fen() => '${_placement()} ${_whiteToMove ? 'w' : 'b'} - - 0 1';

  /// Pozitsiya to'g'ri bo'lsa true.
  bool _validPosition() {
    var wk = 0, bk = 0;
    for (var r = 0; r < 8; r++) {
      for (final c in _grid[r]) {
        if (c == 'K') wk++;
        if (c == 'k') bk++;
        if ((c == 'P' || c == 'p') && (r == 0 || r == 7)) return false;
      }
    }
    if (wk != 1 || bk != 1) return false;
    try {
      ch.Chess.fromFEN(_fen());
      // Yurmayotgan tomonning shohi shaxda bo'lmasligi kerak
      final other = '${_placement()} ${_whiteToMove ? 'b' : 'w'} - - 0 1';
      if (ch.Chess.fromFEN(other).in_check) return false;
    } catch (_) {
      return false;
    }
    return true;
  }

  void _applyFen() {
    final raw = _fenCtl.text.trim();
    if (raw.isEmpty) return;
    final parts = raw.split(RegExp(r'\s+'));
    setState(() {
      try {
        _grid = _gridFromPlacement(parts.first);
        _whiteToMove = parts.length < 2 || parts[1] != 'b';
        _error = null;
      } catch (_) {
        _error = t('pm_bad_pos');
      }
    });
  }

  void _toSolution() {
    if (!_validPosition()) {
      setState(() => _error = t('pm_bad_pos'));
      return;
    }
    setState(() {
      _error = null;
      _step = 1;
      _game = ch.Chess.fromFEN(_fen());
      _boardKey++;
      _pending = null;
      _solutions.clear();
    });
  }

  void _addSolution() {
    final r = _pending;
    final g = _game;
    if (r == null || g == null) return;
    final mv = r.from + r.to;
    g.undo_move();
    setState(() {
      if (!_solutions.contains(mv)) _solutions.add(mv);
      _pending = null;
      _boardKey++;
    });
  }

  void _cancelPending() {
    final g = _game;
    if (g == null || _pending == null) return;
    g.undo_move();
    setState(() {
      _pending = null;
      _boardKey++;
    });
  }

  Future<void> _save() async {
    if (_solutions.isEmpty) {
      setState(() => _error = t('pm_need_sol'));
      return;
    }
    final token = s.token;
    if (token == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final title = _title.text.trim().isEmpty ? t('pm_default_name') : _title.text.trim();
      final res = await Api.post('/coach/puzzles', token, {
        'title': title,
        'fen': _fen(),
        'solutions': _solutions,
      });
      await loadCustomPuzzles(s);
      final id = ((res['puzzle'] as Map)['id'] as num).toInt();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('pm_saved'))));
      Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is ApiException ? tr(s.lang, e.l10nKey) : t('err_network');
        });
      }
    }
  }

  Future<void> _delete(Puzzle p) async {
    final token = s.token;
    if (token == null) return;
    try {
      await Api.post('/coach/puzzles/${p.id - kCustomBase}/delete', token, {});
      await loadCustomPuzzles(s);
    } catch (_) {}
  }

  static (PieceKind, bool) _piece(String c) {
    final white = c == c.toUpperCase();
    switch (c.toLowerCase()) {
      case 'k':
        return (PieceKind.king, white);
      case 'q':
        return (PieceKind.queen, white);
      case 'r':
        return (PieceKind.rook, white);
      case 'b':
        return (PieceKind.bishop, white);
      case 'n':
        return (PieceKind.knight, white);
      default:
        return (PieceKind.pawn, white);
    }
  }

  Widget _editorBoard(double side) {
    final cell = side / 8;
    return SizedBox(
      width: side,
      height: side,
      child: Column(
        children: [
          for (var r = 0; r < 8; r++)
            Expanded(
              child: Row(
                children: [
                  for (var f = 0; f < 8; f++)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          final tool = _tool;
                          if (tool == null) return;
                          _grid[r][f] = tool == 'x' ? null : tool;
                        }),
                        child: ColoredBox(
                          color: (r + f) % 2 == 0
                              ? pal.boardLight
                              : pal.boardDark,
                          child: _grid[r][f] == null
                              ? const SizedBox.expand()
                              : Center(
                                  child: Builder(builder: (_) {
                                    final (k, w) = _piece(_grid[r][f]!);
                                    return PieceView(
                                      kind: k,
                                      white: w,
                                      size: cell * 0.92,
                                      style: s.boardStyle,
                                    );
                                  }),
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _palette() {
    const white = ['K', 'Q', 'R', 'B', 'N', 'P'];
    Widget chip(String c) {
      final (k, w) = _piece(c);
      final sel = _tool == c;
      return InkWell(
        onTap: () => setState(() => _tool = sel ? null : c),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: sel ? pal.accentSoft : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: sel ? pal.accent : pal.cardBorder, width: sel ? 2 : 1),
          ),
          child: Center(
            child: PieceView(kind: k, white: w, size: 34, style: s.boardStyle),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final c in white) chip(c),
        for (final c in white) chip(c.toLowerCase()),
        InkWell(
          onTap: () => setState(() => _tool = _tool == 'x' ? null : 'x'),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _tool == 'x' ? pal.accentSoft : null,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: _tool == 'x' ? pal.accent : pal.cardBorder,
                  width: _tool == 'x' ? 2 : 1),
            ),
            child: Icon(Icons.backspace_outlined, color: pal.text, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _cardBox(Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: pal.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pal.cardBorder),
        ),
        child: child,
      );

  Widget _stepPosition(double side) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cardBox(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _title,
              decoration: InputDecoration(labelText: t('pm_name')),
            ),
            const SizedBox(height: 14),
            Text(t('pm_pos'),
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 15.5, color: pal.text)),
            const SizedBox(height: 10),
            Center(child: _editorBoard(side)),
            const SizedBox(height: 10),
            _palette(),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _grid = _startGrid()),
                  child: Text(t('pm_start')),
                ),
                OutlinedButton(
                  onPressed: () => setState(() =>
                      _grid = List.generate(8, (_) => List<String?>.filled(8, null))),
                  child: Text(t('pm_clear')),
                ),
                ChoiceChip(
                  label: Text(t('pm_white')),
                  selected: _whiteToMove,
                  onSelected: (_) => setState(() => _whiteToMove = true),
                ),
                ChoiceChip(
                  label: Text(t('pm_black')),
                  selected: !_whiteToMove,
                  onSelected: (_) => setState(() => _whiteToMove = false),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _fenCtl,
                    decoration: InputDecoration(labelText: t('pm_fen')),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                    onPressed: _applyFen, child: Text(t('pm_fen_apply'))),
              ],
            ),
          ],
        )),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _toSolution,
          icon: const Icon(Icons.arrow_forward),
          label: Text(t('pm_next')),
        ),
      ],
    );
  }

  Widget _stepSolution(double side) {
    final g = _game!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cardBox(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('pm_sol'),
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 15.5, color: pal.text)),
            const SizedBox(height: 6),
            Text(t('pm_sol_hint'),
                style: TextStyle(color: pal.subtext, fontSize: 12.5)),
            const SizedBox(height: 10),
            Center(
              child: SizedBox(
                width: side,
                child: ChessBoard(
                  key: ValueKey(_boardKey),
                  game: g,
                  pal: pal,
                  style: s.boardStyle,
                  flipped: !_whiteToMove,
                  onMoved: (r) => setState(() => _pending = r),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_pending != null)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _addSolution,
                      icon: const Icon(Icons.check),
                      label: Text('${t('pm_add_sol')}: ${_pending!.san}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _cancelPending,
                    child: const Icon(Icons.undo),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Text('${t('pm_solutions')}: ${_solutions.length}',
                style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
            Wrap(
              spacing: 6,
              children: [
                for (final m in _solutions)
                  InputChip(
                    label: Text('${m.substring(0, 2)}-${m.substring(2)}'),
                    onDeleted: () => setState(() => _solutions.remove(m)),
                  ),
              ],
            ),
          ],
        )),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => setState(() => _step = 0),
              icon: const Icon(Icons.arrow_back),
              label: Text(t('pm_back')),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save),
                label: Text(t('pm_save')),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _mine() {
    if (kCustomPuzzles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: _cardBox(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('pm_mine'),
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15.5, color: pal.text)),
          for (final p in kCustomPuzzles)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(Icons.extension, color: pal.accent),
              title: Text('#${shownNo(p)}  ·  ${p.fen.contains(' b ') ? t('black_to_move') : t('white_to_move')}',
                  style: TextStyle(color: pal.text)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(p),
              ),
            ),
        ],
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pal.bg1,
      appBar: AppBar(
        backgroundColor: pal.navTop,
        foregroundColor: pal.navText,
        title: Text(t('pm_title')),
      ),
      body: LayoutBuilder(builder: (context, c) {
        final side = math.min(440.0, c.maxWidth - 64);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _step == 0 ? _stepPosition(side) : _stepSolution(side),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                if (_step == 0) _mine(),
              ],
            ),
          ),
        );
      }),
    );
  }
}
