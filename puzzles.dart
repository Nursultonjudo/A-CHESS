import 'dart:math' as math;

import 'package:chess/chess.dart' as ch;
import 'package:flutter/material.dart';

import 'l10n.dart';
import 'settings.dart';
import 'widgets/chess_board.dart';

/// Shaxmat masalalari. kind=1: 1 yurishda mat; kind=2: 2 yurishda mat.
/// sols: 'birinchi yurish:raqib javobi' (kind=2), sol: mat yurishi (kind=1)
class Puzzle {
  const Puzzle(this.id, this.kind, this.fen, this.sols);
  final int id;
  final int kind;
  final String fen;
  final Map<String, String> sols;
}

const List<Puzzle> kPuzzles = [
  Puzzle(1, 1, 'k7/2Q5/1pp5/4p3/8/1R6/B7/4K3 w - - 0 1', {'b3a3': ''}),
  Puzzle(2, 1, '5k1N/1Q6/8/8/1p4K1/3p4/8/8 w - - 0 1', {'b7f7': ''}),
  Puzzle(3, 1, 'kr6/5Q1p/p3R3/3r4/8/1p6/8/2K5 w - - 0 1', {'e6a6': ''}),
  Puzzle(4, 1, '6k1/1pR4p/3R4/8/8/8/6K1/8 w - - 0 1', {'d6d8': ''}),
  Puzzle(5, 1, '2k1n1B1/R6r/8/1Q6/8/3p2K1/8/8 w - - 0 1', {'b5e8': ''}),
  Puzzle(6, 1, '3kb3/5Q2/4R2p/8/8/1p6/3K4/8 w - - 0 1', {'e6e8': ''}),
  Puzzle(7, 1, 'k7/8/8/3nn3/7p/1Q6/7R/2K5 w - - 0 1', {'h2a2': ''}),
  Puzzle(8, 1, '4k3/8/5Q2/2B3Rr/8/4p1p1/8/3K4 w - - 0 1', {'f6e7': ''}),
  Puzzle(9, 1, '4rn1k/2Q4n/8/7N/p2p4/8/8/6K1 w - - 0 1', {'c7g7': ''}),
  Puzzle(10, 1, 'k4b2/1p6/1R4rp/8/4Q3/2pB4/8/4K3 w - - 0 1', {'e4b7': ''}),
  Puzzle(11, 1, 'k7/8/rQp5/8/6p1/2p5/5K2/7B w - - 0 1', {'h1c6': ''}),
  Puzzle(12, 1, '3k4/3p4/5pB1/4B3/8/6K1/2R5/8 w - - 0 1', {'e5f6': ''}),
  Puzzle(13, 1, '2k5/8/1p1Q2p1/8/1K6/8/8/5B2 w - - 0 1', {'f1a6': ''}),
  Puzzle(14, 1, '3k4/8/ppQ5/8/5p2/8/5B2/4K3 w - - 0 1', {'f2h4': ''}),
  Puzzle(15, 1, '7k/5n2/3Nn1Q1/5p2/8/8/6K1/8 w - - 0 1', {'d6f7': ''}),
  Puzzle(16, 1, 'k7/p1b5/4N3/8/1R6/7K/2P5/8 w - - 0 1', {'e6c7': ''}),
  Puzzle(17, 1, 'kb6/4RBb1/8/1pB5/6K1/6p1/8/8 w - - 0 1', {'f7d5': ''}),
  Puzzle(18, 1, '7k/1R6/3p4/3B4/p6N/8/8/1K6 w - - 0 1', {'h4g6': ''}),
  Puzzle(19, 2, '7Q/k5b1/2R4p/8/1pK5/4p3/8/8 w - - 0 1', {'h8c8': 'e3e2'}),
  Puzzle(20, 2, '8/k1pp4/5QR1/p7/3K4/3p4/8/8 w - - 0 1', {'f6a6': 'a7b8'}),
  Puzzle(21, 2, 'k7/6R1/8/1b6/1K5p/2p5/8/4R3 w - - 0 1', {'b4b5': 'c3c2'}),
  Puzzle(22, 2, '1k6/2R5/1B6/1N2p3/8/1p6/8/7K w - - 0 1', {'b5d6': 'b3b2'}),
  Puzzle(23, 2, '8/k1n2Q2/3p4/p4Rp1/2p5/8/8/6K1 w - - 0 1', {'f7c7': 'a7a6'}),
  Puzzle(24, 2, '5k2/1b6/8/8/1R2p1K1/8/8/R7 w - - 0 1', {'b4b7': 'e4e3'}),
  Puzzle(25, 2, 'k7/6p1/8/1Np5/8/2K3Q1/8/8 w - - 0 1', {'g3c7': 'c5c4'}),
  Puzzle(26, 2, '1rb3k1/R7/p7/6r1/p7/6Q1/8/5K2 w - - 0 1', {'g3g5': 'g8f8'}),
  Puzzle(27, 2, '7k/2B5/1b6/8/pp6/1p6/3Q3K/5R2 w - - 0 1', {'d2h6': 'h8g8'}),
  Puzzle(28, 2, '2r4k/3Q4/1p6/8/1B6/K4R2/8/8 w - - 0 1', {'f3h3': 'h8g8'}),
  Puzzle(29, 2, '1Q6/5p2/k6n/6R1/5p2/4p3/8/4K3 w - - 0 1', {'g5b5': 'e3e2'}),
  Puzzle(30, 2, '2k5/8/4pRp1/p7/7B/5Q2/2K5/8 w - - 0 1', {'f6f7': 'g6g5'}),
];

// ---------------------------------------------------------------------------
// Vazifalar oynasi: statistika + masalalar ro'yxati + yechish oynasi
// ---------------------------------------------------------------------------

class TasksView extends StatelessWidget {
  const TasksView({
    super.key,
    required this.settings,
    required this.pal,
    this.onPlay,
  });
  final AppSettings settings;
  final Pal pal;
  final VoidCallback? onPlay;

  String t(String key, [Map<String, String> args = const {}]) =>
      tr(settings.lang, key, args);

  int _since(Duration d) {
    final from = DateTime.now().subtract(d).millisecondsSinceEpoch;
    return settings.solved.values.where((v) => v >= from).length;
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: pal.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: pal.cardBorder),
        ),
        child: child,
      );

  Widget _stat(String label, int value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: pal.accentSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: pal.text,
                ),
              ),
              Text(label, style: TextStyle(fontSize: 12, color: pal.subtext)),
            ],
          ),
        ),
      );

  void _open(BuildContext context, Puzzle p) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PuzzlePage(settings: settings, pal: pal, puzzle: p),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final total = kPuzzles.length;
        final done = kPuzzles.where((p) => settings.solved.containsKey('${p.id}')).length;
        final percent = total == 0 ? 0.0 : done / total;

        Widget tile(Puzzle p) {
          final solved = settings.solved.containsKey('${p.id}');
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _open(context, p),
            child: Container(
              width: 74,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: solved ? pal.accentSoft : null,
                border: Border.all(
                  color: solved ? pal.accent : pal.cardBorder,
                  width: solved ? 1.8 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    solved ? Icons.check_circle : Icons.extension_outlined,
                    color: solved ? pal.accent : pal.subtext,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${p.id}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: pal.text,
                    ),
                  ),
                  Text(
                    p.kind == 1 ? '#1' : '#2',
                    style: TextStyle(fontSize: 11, color: pal.subtext),
                  ),
                ],
              ),
            ),
          );
        }

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DailyPlanCard(
                    settings: settings,
                    pal: pal,
                    onPlay: onPlay,
                    onOpen: (p) => _open(context, p),
                  ),
                  const SizedBox(height: 14),
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('task_progress'),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: pal.text,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            SizedBox(
                              width: 84,
                              height: 84,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: 84,
                                    height: 84,
                                    child: CircularProgressIndicator(
                                      value: percent,
                                      strokeWidth: 9,
                                      backgroundColor: pal.cardBorder,
                                      color: pal.accent,
                                    ),
                                  ),
                                  Text(
                                    '${(percent * 100).round()}%',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: pal.text,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Text(
                                t('solved_count', {
                                  'n': '$done',
                                  'total': '$total',
                                }),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: pal.text,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            _stat(t('today'), _since(const Duration(hours: 24))),
                            const SizedBox(width: 8),
                            _stat(t('week'), _since(const Duration(days: 7))),
                            const SizedBox(width: 8),
                            _stat(t('month'), _since(const Duration(days: 30))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.extension, color: pal.accent),
                            const SizedBox(width: 8),
                            Text(
                              t('puzzles_title'),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: pal.text,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '#1 = ${t('mate_in_1')}   #2 = ${t('mate_in_2')}',
                          style: TextStyle(fontSize: 12.5, color: pal.subtext),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [for (final p in kPuzzles) tile(p)],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _card(
                    child: Row(
                      children: [
                        Icon(Icons.school_outlined, color: pal.accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t('coach_tasks'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: pal.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                t('coach_soon'),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: pal.subtext,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Kunlik mashg'ulot kalendari: 4 blok, seriya, foiz chizig'i.
class DailyPlanCard extends StatelessWidget {
  const DailyPlanCard({
    super.key,
    required this.settings,
    required this.pal,
    required this.onOpen,
    this.onPlay,
  });
  final AppSettings settings;
  final Pal pal;
  final void Function(Puzzle) onOpen;
  final VoidCallback? onPlay;

  static const _minutes = [15, 20, 20, 25];

  String t(String key, [Map<String, String> args = const {}]) =>
      tr(settings.lang, key, args);

  Puzzle? _firstDue() {
    for (final p in kPuzzles) {
      if (settings.isDue(p.id)) return p;
    }
    return null;
  }

  Puzzle? _firstNew() {
    for (final p in kPuzzles) {
      if (!settings.solved.containsKey('${p.id}')) return p;
    }
    return null;
  }

  int _dueCount() => kPuzzles.where((p) => settings.isDue(p.id)).length;

  Widget _block(int i) {
    final done = settings.planToday;
    final isDone = done.contains(i);
    final unlocked = i == 0 || done.contains(i - 1);
    final current = !isDone && unlocked;
    final accent = pal.accent;
    final color = isDone
        ? const Color(0xFF34D399)
        : (current ? accent : pal.subtext);

    String extra = '';
    VoidCallback? start;
    if (i == 0) {
      final n = _dueCount();
      extra = n > 0 ? t('plan_due', {'n': '$n'}) : t('plan_nodue');
      final p = _firstDue();
      if (p != null) start = () => onOpen(p);
    } else if (i == 1) {
      final p = _firstNew() ?? (kPuzzles.isEmpty ? null : kPuzzles.first);
      if (p != null) start = () => onOpen(p);
    } else if (i == 3) {
      start = onPlay;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: current ? accent.withAlpha(0x1F) : pal.bg1.withAlpha(0x80),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDone
              ? const Color(0xFF34D399).withAlpha(0x88)
              : (current ? accent : pal.cardBorder),
          width: current ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withAlpha(0x26),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_minutes[i]} ${t('minutes_short')}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              const Spacer(),
              Icon(
                isDone
                    ? Icons.check_circle
                    : (unlocked ? Icons.radio_button_unchecked : Icons.lock),
                size: 22,
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${i + 1}. ${t('plan_b${i + 1}')}',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: unlocked ? pal.text : pal.subtext,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            extra.isEmpty ? t('plan_b${i + 1}d') : extra,
            style: TextStyle(fontSize: 12.5, color: pal.subtext),
          ),
          const SizedBox(height: 12),
          if (isDone)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => settings.setPlanBlock(i, false),
                child: Text(t('plan_done')),
              ),
            )
          else if (!unlocked)
            Text(
              t('plan_wait'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: pal.subtext,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (start != null)
                  FilledButton(
                    onPressed: start,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                    ),
                    child: Text(t('plan_start')),
                  ),
                OutlinedButton(
                  onPressed: () => settings.setPlanBlock(i, true),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                  ),
                  child: Text(t('plan_mark')),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final done = settings.planToday.length;
    final percent = done / 4.0;
    final streak = settings.streak;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: pal.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_fire_department,
                  size: 20,
                  color: streak > 0 ? pal.accent : pal.subtext),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  t('streak_days', {'n': '$streak'}).toUpperCase(),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: streak > 0 ? pal.accent : pal.subtext,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t('plan_title'),
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
              color: pal.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            t('plan_sub'),
            style: TextStyle(fontSize: 13, color: pal.subtext),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                '${t('plan_progress')}: ',
                style: TextStyle(color: pal.subtext, fontSize: 13),
              ),
              Text(
                '${(percent * 100).round()}% ($done/4)',
                style: TextStyle(
                  color: pal.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 8,
              backgroundColor: pal.cardBorder,
              color: pal.accent,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _block(i),
          ],
        ],
      ),
    );
  }
}

class PuzzlePage extends StatefulWidget {
  const PuzzlePage({
    super.key,
    required this.settings,
    required this.pal,
    required this.puzzle,
  });
  final AppSettings settings;
  final Pal pal;
  final Puzzle puzzle;

  @override
  State<PuzzlePage> createState() => _PuzzlePageState();
}

class _PuzzlePageState extends State<PuzzlePage> {
  late Puzzle _p = widget.puzzle;
  late ch.Chess _game = ch.Chess.fromFEN(_p.fen);
  int _boardKey = 0;
  int _stage = 0; // 0: birinchi yurish, 1: ikkinchi yurish (mat)
  String _msgKey = '';
  bool _ok = false;
  bool _solved = false;
  String? _lastFrom;
  String? _lastTo;

  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String key, [Map<String, String> args = const {}]) =>
      tr(s.lang, key, args);

  void _load(Puzzle p) {
    setState(() {
      _p = p;
      _game = ch.Chess.fromFEN(p.fen);
      _boardKey++;
      _stage = 0;
      _msgKey = '';
      _ok = false;
      _solved = false;
      _lastFrom = null;
      _lastTo = null;
    });
  }

  void _wrong() {
    _game.undo_move();
    setState(() {
      _boardKey++;
      _msgKey = 'wrong_move';
      _ok = false;
    });
  }

  void _win() {
    s.markSolved(_p.id);
    setState(() {
      _solved = true;
      _ok = true;
      _msgKey = 'puzzle_solved';
      _lastFrom = null;
      _lastTo = null;
    });
  }

  void _onMoved(MoveRecord r) {
    if (_solved) return;
    if (_p.kind == 1) {
      _game.in_checkmate ? _win() : _wrong();
      return;
    }
    if (_stage == 0) {
      final reply = _p.sols[r.from + r.to];
      if (reply == null || reply.isEmpty) {
        _wrong();
        return;
      }
      _game.move({
        'from': reply.substring(0, 2),
        'to': reply.substring(2, 4),
        'promotion': 'q',
      });
      setState(() {
        _stage = 1;
        _boardKey++;
        _msgKey = 'correct_continue';
        _ok = true;
        _lastFrom = reply.substring(0, 2);
        _lastTo = reply.substring(2, 4);
      });
      return;
    }
    _game.in_checkmate ? _win() : _wrong();
  }

  @override
  Widget build(BuildContext context) {
    final idx = kPuzzles.indexWhere((x) => x.id == _p.id);
    final next = idx >= 0 && idx + 1 < kPuzzles.length ? kPuzzles[idx + 1] : null;

    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        backgroundColor: pal.bg1,
        appBar: AppBar(
          backgroundColor: pal.navTop,
          foregroundColor: pal.navText,
          title: Text(t('puzzle_n', {'n': '${_p.id}'})),
        ),
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [pal.bg1, pal.bg2],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final side = math.min(c.maxWidth - 24, c.maxHeight - 190);
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: math.max(260.0, side),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: pal.card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: pal.cardBorder),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.extension, color: pal.accent),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${t(_p.kind == 1 ? 'mate_in_1' : 'mate_in_2')} · ${t('white_to_move')}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: pal.text,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        ChessBoard(
                          key: ValueKey(_boardKey),
                          game: _game,
                          pal: pal,
                          style: s.boardStyle,
                          lastFrom: _lastFrom,
                          lastTo: _lastTo,
                          enabled: !_solved,
                          onMoved: _onMoved,
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _msgKey.isEmpty
                                ? pal.card
                                : (_ok
                                    ? const Color(0x3343A047)
                                    : const Color(0x33E53935)),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: pal.cardBorder),
                          ),
                          child: Text(
                            _msgKey.isEmpty ? t('find_mate') : t(_msgKey),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: pal.text,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _load(_p),
                                icon: const Icon(Icons.refresh),
                                label: Text(t('retry')),
                              ),
                            ),
                            if (_solved && next != null) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => _load(next),
                                  icon: const Icon(Icons.arrow_forward),
                                  label: Text(t('next_puzzle')),
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
        ),
      ),
    );
  }
}
