import 'dart:convert';
import 'dart:math' as math;

import 'package:chess/chess.dart' as ch;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine.dart';

/// Yurish sifati belgilari.
enum MoveQuality { brilliant, best, good, inaccuracy, mistake, blunder }

/// FEN dagi tomon materiali (piyoda=1, ot/fil=3, ladya=5, farzin=9).
int materialOfFen(String fen, bool white) {
  const v = {'p': 1, 'n': 3, 'b': 3, 'r': 5, 'q': 9};
  var sum = 0;
  for (final c in fen.split(' ').first.split('')) {
    final low = c.toLowerCase();
    final val = v[low];
    if (val == null) continue;
    final isWhite = c == c.toUpperCase();
    if (isWhite == white) sum += val;
  }
  return sum;
}

String _fnv(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16);
}

/// Bahoni butun songa o'raydi: santipiyoda yoki mat (|v| >= 90000).
int packEval(EngineEval e) {
  if (e.mate != null) {
    final m = e.mate!;
    if (m == 0) return 100000;
    return (m > 0 ? 1 : -1) * (100000 - m.abs());
  }
  return (e.cp ?? 0).clamp(-8000, 8000);
}

double winPctOfPacked(int v) {
  final c = (v.abs() >= 90000 ? (v > 0 ? 3000 : -3000) : v).toDouble();
  return 50 + 50 * (2 / (1 + math.exp(-0.00368208 * c)) - 1);
}

String labelOfPacked(int v) {
  if (v.abs() >= 90000) {
    final m = 100000 - v.abs();
    return m == 0 ? '#' : (v > 0 ? 'M$m' : '-M$m');
  }
  final x = v / 100.0;
  final s = x.abs().toStringAsFixed(2);
  return x > 0.004 ? '+$s' : (x < -0.004 ? '-$s' : '0.00');
}

/// Bitta partiya/liniya tahlili: har bir pozitsiya uchun baho (oq nuqtai
/// nazaridan) va dvigatelning eng yaxshi yurishi.
class GameAnalysis {
  GameAnalysis({required this.evals, required this.best, required this.ms});
  final List<int> evals; // n+1 ta pozitsiya
  final List<String> best; // UCI yoki ''
  final int ms; // har bir pozitsiyaga ketgan vaqt

  int get plies => evals.length - 1;

  double winPct(int i) => winPctOfPacked(evals[i]);

  /// i-yarim yurish (1..n) qilgan tomon yo'qotgan g'alaba foizi.
  double loss(int ply) {
    final before = winPct(ply - 1);
    final after = winPct(ply);
    final whiteMoved = ply.isOdd;
    return math.max(0, whiteMoved ? before - after : after - before);
  }

  /// Brilliant: eng yaxshi (yoki unga yaqin) yurish, material qurbon qilinadi,
  /// lekin pozitsiya yomonlashmaydi va oldin allaqachon yutuq holatda emas edi.
  bool _isBrilliant(int ply, List<String> fens) {
    if (ply + 1 >= fens.length) return false;
    final white = ply.isOdd;
    final before = materialOfFen(fens[ply - 1], white) -
        materialOfFen(fens[ply - 1], !white);
    final after = materialOfFen(fens[ply + 1], white) -
        materialOfFen(fens[ply + 1], !white);
    final moverWinBefore = white ? winPct(ply - 1) : 100 - winPct(ply - 1);
    final moverWinAfter = white ? winPct(ply) : 100 - winPct(ply);
    return after - before <= -2 &&
        loss(ply) < 3 &&
        moverWinAfter >= 45 &&
        moverWinBefore < 92;
  }

  MoveQuality quality(int ply, String playedUci, {List<String>? fens}) {
    final l = loss(ply);
    if (best[ply - 1].isNotEmpty &&
        playedUci.length >= 4 &&
        best[ply - 1].startsWith(playedUci.substring(0, 4))) {
      if (fens != null && _isBrilliant(ply, fens)) return MoveQuality.brilliant;
      return MoveQuality.best;
    }
    if (fens != null && l < 2 && _isBrilliant(ply, fens)) {
      return MoveQuality.brilliant;
    }
    if (l >= 20) return MoveQuality.blunder;
    if (l >= 10) return MoveQuality.mistake;
    if (l >= 5) return MoveQuality.inaccuracy;
    return MoveQuality.good;
  }

  /// Lichess formulasi bo'yicha aniqlik (0..100).
  double accuracy(bool white) {
    var sum = 0.0;
    var n = 0;
    for (var p = 1; p <= plies; p++) {
      if (p.isOdd != white) continue;
      final a = 103.1668 * math.exp(-0.04354 * loss(p)) - 3.1669;
      sum += a.clamp(0, 100);
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  String toJson() => jsonEncode({'e': evals, 'b': best, 'm': ms});

  static GameAnalysis? fromJson(String s) {
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return GameAnalysis(
        evals: (m['e'] as List).map((e) => (e as num).toInt()).toList(),
        best: (m['b'] as List).map((e) => e.toString()).toList(),
        ms: (m['m'] as num).toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

String analysisKey(List<String> sans) => 'an1_${_fnv(sans.join(' '))}';

Future<GameAnalysis?> loadAnalysis(List<String> sans) async {
  try {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(analysisKey(sans));
    if (s == null) return null;
    final a = GameAnalysis.fromJson(s);
    return a != null && a.plies == sans.length ? a : null;
  } catch (_) {
    return null;
  }
}

Future<void> saveAnalysis(List<String> sans, GameAnalysis a) async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(analysisKey(sans), a.toJson());
  } catch (_) {}
}

/// UCI yurishni (masalan e2e4) SAN ga aylantiradi.
String? uciToSan(String fen, String uci) {
  if (uci.length < 4) return null;
  try {
    final g = ch.Chess.fromFEN(fen);
    final list = g.moves({'verbose': true}) as List;
    for (final m in list) {
      final mm = m as Map;
      if ('${mm['from']}${mm['to']}' == uci.substring(0, 4) &&
          (uci.length < 5 || mm['promotion']?.toString() == uci[4])) {
        return mm['san'].toString();
      }
    }
  } catch (_) {}
  return null;
}

/// Yurishlar ro'yxatidan har bir pozitsiyaning FEN ini hosil qiladi va
/// yurishning UCI (from+to) yozuvlarini qaytaradi. Noto'g'ri SAN uchratsa
/// shu yergacha qisqartiradi.
class ReplayResult {
  ReplayResult(this.fens, this.ucis, this.sans);
  final List<String> fens; // n+1
  final List<String> ucis; // n
  final List<String> sans; // n (tozalangan)
}

String _clean(String s) => s.replaceAll('+', '').replaceAll('#', '');

ReplayResult replaySans(List<String> input) {
  final g = ch.Chess();
  final fens = <String>[g.fen];
  final ucis = <String>[];
  final sans = <String>[];
  for (final san in input) {
    final list = g.moves({'verbose': true}) as List;
    Map? found;
    for (final m in list) {
      final mm = m as Map;
      if (_clean(mm['san'].toString()) == _clean(san)) {
        found = mm;
        break;
      }
    }
    if (found == null) break;
    final mv = <String, dynamic>{'from': found['from'], 'to': found['to']};
    if (found['promotion'] != null) mv['promotion'] = found['promotion'];
    g.move(mv);
    fens.add(g.fen);
    ucis.add('${found['from']}${found['to']}${found['promotion'] ?? ''}');
    sans.add(found['san'].toString());
  }
  return ReplayResult(fens, ucis, sans);
}

/// Butun partiyani Stockfish bilan tahlil qiladi.
/// [cancelled] true bo'lsa to'xtaydi (null qaytaradi).
Future<GameAnalysis?> runAnalysis(
  ReplayResult rr, {
  required int movetimeMs,
  required void Function(int done, int total) onProgress,
  required bool Function() cancelled,
}) async {
  final eng = EngineService.instance;
  if (!await eng.ensureReady()) return null;
  final total = rr.fens.length;
  final evals = <int>[];
  final best = <String>[];
  try {
    for (var i = 0; i < total; i++) {
      if (cancelled()) return null;
      final fen = rr.fens[i];
      final g = ch.Chess.fromFEN(fen);
      if (g.in_checkmate) {
        // mat bo'lgan: yurish navbati tomon yutqazdi
        evals.add(g.turn == ch.Color.WHITE ? -100000 : 100000);
        best.add('');
      } else if (g.in_stalemate ||
          g.insufficient_material ||
          g.in_threefold_repetition) {
        evals.add(0);
        best.add('');
      } else {
        final e = await eng.evalOnce(fen, movetimeMs);
        if (cancelled()) return null;
        if (e == null) {
          evals.add(evals.isEmpty ? 0 : evals.last);
          best.add('');
        } else {
          evals.add(packEval(e));
          best.add(e.best ?? '');
        }
      }
      onProgress(i + 1, total);
    }
  } finally {
    eng.endBatch();
  }
  return GameAnalysis(evals: evals, best: best, ms: movetimeMs);
}

/// Baho grafigi: oq/qora ustunlik maydoni, joriy yarim yurish belgisi,
/// bosib/surib yurishga sakrash.
class EvalGraph extends StatelessWidget {
  const EvalGraph({
    super.key,
    required this.analysis,
    required this.current,
    required this.onSelect,
    required this.lineColor,
  });
  final GameAnalysis analysis;
  final int current;
  final void Function(int ply) onSelect;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        void pick(double dx) {
          final n = analysis.plies;
          if (n <= 0) return;
          final i = (dx / c.maxWidth * n).round().clamp(0, n);
          onSelect(i);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => pick(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => pick(d.localPosition.dx),
          child: SizedBox(
            height: 110,
            width: double.infinity,
            child: CustomPaint(
              painter: _GraphPainter(analysis, current, lineColor),
            ),
          ),
        );
      },
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.a, this.current, this.lineColor);
  final GameAnalysis a;
  final int current;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final n = a.plies;
    final bg = Paint()..color = const Color(0xFF1F2937);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      bg,
    );
    if (n <= 0) return;
    double x(int i) => size.width * i / n;
    double y(int i) => size.height * (1 - a.winPct(i) / 100);
    final path = Path()..moveTo(0, size.height);
    for (var i = 0; i <= n; i++) {
      path.lineTo(x(i), y(i));
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFE5E7EB));
    final mid = Paint()
      ..color = const Color(0x66F59E0B)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      mid,
    );
    final line = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final stroke = Path()..moveTo(x(0), y(0));
    for (var i = 1; i <= n; i++) {
      stroke.lineTo(x(i), y(i));
    }
    canvas.drawPath(stroke, line);
    // xatolar nuqtalari
    for (var p = 1; p <= n; p++) {
      final l = a.loss(p);
      if (l >= 10) {
        canvas.drawCircle(
          Offset(x(p), y(p)),
          l >= 20 ? 3.4 : 2.6,
          Paint()..color = l >= 20 ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
        );
      }
    }
    final cur = current.clamp(0, n);
    canvas.drawLine(
      Offset(x(cur), 0),
      Offset(x(cur), size.height),
      Paint()
        ..color = lineColor
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) =>
      old.current != current || old.a != a;
}
