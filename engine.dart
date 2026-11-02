import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:stockfish_chess_engine/stockfish_chess_engine.dart';
import 'package:stockfish_chess_engine/stockfish_chess_engine_state.dart';

/// Stockfish bahosi (har doim OQLAR nuqtai nazaridan).
class EngineEval {
  const EngineEval({this.cp, this.mate, required this.depth, this.best});
  final int? cp; // santipiyoda: + oq ustun
  final int? mate; // + oq mat qiladi, - qora mat qiladi
  final int depth;
  final String? best; // eng yaxshi yurish, masalan e2e4

  /// Oqlarning "g'alaba ulushi" 0..1 (chiziq balandligi uchun).
  double get whiteFrac {
    if (mate != null) return mate! > 0 ? 1.0 : 0.0;
    final c = (cp ?? 0).clamp(-1500, 1500).toDouble();
    final w = 2 / (1 + math.exp(-0.00368208 * c)) - 1;
    return (0.5 + 0.5 * w).clamp(0.02, 0.98);
  }

  String get label {
    if (mate != null) return mate! > 0 ? 'M${mate!.abs()}' : '-M${mate!.abs()}';
    final v = (cp ?? 0) / 100.0;
    final s = v.abs().toStringAsFixed(2);
    if (v > 0.004) return '+$s';
    if (v < -0.004) return '-$s';
    return '0.00';
  }

  String? get bestText {
    final b = best;
    if (b == null || b.length < 4) return null;
    return '${b.substring(0, 2)}–${b.substring(2, 4)}'
        '${b.length > 4 ? b.substring(4) : ''}';
  }
}

/// Stockfish dvigatelini ishga tushiradi va pozitsiyalarni tahlil qiladi.
/// Dvigatel ishlamasa (masalan, qurilma qo'llamasa), hech narsa buzilmaydi.
class EngineService {
  EngineService._();
  static final EngineService instance = EngineService._();

  final ValueNotifier<EngineEval?> eval = ValueNotifier(null);
  final ValueNotifier<bool> ready = ValueNotifier(false);

  Stockfish? _sf;
  StreamSubscription<String>? _sub;
  bool _starting = false;
  int _active = 0; // tugamagan qidiruvlar soni
  bool _whiteToMove = true;
  String? _pendingFen;

  Future<void> start() async {
    if (_sf != null || _starting) return;
    _starting = true;
    try {
      final sf = Stockfish();
      _sf = sf;
      _sub = sf.stdout.listen(_onLine);
      for (var i = 0; i < 100; i++) {
        final st = sf.state.value;
        if (st == StockfishState.ready) break;
        if (st == StockfishState.error || st == StockfishState.disposed) {
          throw StateError('Stockfish ishga tushmadi');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (sf.state.value != StockfishState.ready) {
        throw StateError('Stockfish tayyor bo\'lmadi');
      }
      sf.stdin = 'uci';
      sf.stdin = 'setoption name Threads value 1';
      sf.stdin = 'setoption name Hash value 32';
      sf.stdin = 'isready';
      ready.value = true;
      final fen = _pendingFen;
      if (fen != null) analyze(fen);
    } catch (e) {
      debugPrint('Stockfish: $e');
      await stop();
    } finally {
      _starting = false;
    }
  }

  void analyze(String fen) {
    _pendingFen = fen;
    final sf = _sf;
    if (sf == null || !ready.value) return;
    if (_active > 0) sf.stdin = 'stop';
    final parts = fen.split(' ');
    _whiteToMove = parts.length < 2 || parts[1] == 'w';
    sf.stdin = 'position fen $fen';
    sf.stdin = 'go movetime 1500';
    _active++;
  }

  /// Tahlilni to'xtatadi va ko'rsatkichni tozalaydi (o'yin tugaganda).
  void clear() {
    _pendingFen = null;
    final sf = _sf;
    if (sf != null && ready.value && _active > 0) sf.stdin = 'stop';
    eval.value = null;
  }

  void _onLine(String line) {
    if (line.startsWith('bestmove')) {
      if (_active > 0) _active--;
      return;
    }
    if (_active != 1 || !line.startsWith('info') || !line.contains(' score ')) {
      return;
    }
    if (line.contains('lowerbound') || line.contains('upperbound')) return;
    final tk = line.split(' ');
    final si = tk.indexOf('score');
    if (si < 0 || si + 2 >= tk.length) return;
    final val = int.tryParse(tk[si + 2]);
    if (val == null) return;
    final di = tk.indexOf('depth');
    final depth = di >= 0 && di + 1 < tk.length
        ? (int.tryParse(tk[di + 1]) ?? 0)
        : 0;
    final pi = tk.indexOf('pv');
    final best = pi >= 0 && pi + 1 < tk.length ? tk[pi + 1] : null;
    final v = _whiteToMove ? val : -val;
    if (tk[si + 1] == 'cp') {
      eval.value = EngineEval(cp: v, depth: depth, best: best);
    } else if (tk[si + 1] == 'mate') {
      eval.value = EngineEval(mate: v, depth: depth, best: best);
    }
  }

  Future<void> stop() async {
    ready.value = false;
    _active = 0;
    await _sub?.cancel();
    _sub = null;
    final sf = _sf;
    _sf = null;
    try {
      sf?.dispose();
    } catch (_) {}
    eval.value = null;
  }
}
