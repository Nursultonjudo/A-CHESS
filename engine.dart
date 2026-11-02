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

  /// Tashxis: dvigatel holati yoki xato matni (kartada ko'rsatiladi).
  final ValueNotifier<String> diag = ValueNotifier('');
  int _lines = 0;

  Stockfish? _sf;
  StreamSubscription<String>? _sub;
  bool _starting = false;
  bool _whiteToMove = true;
  String? _pendingFen;

  Future<void> start() async {
    if (_sf != null || _starting) return;
    _starting = true;
    diag.value = 'start...';
    _lines = 0;
    try {
      final sf = Stockfish();
      _sf = sf;
      _sub = sf.stdout.listen(_onLine);
      for (var i = 0; i < 100; i++) {
        final st = sf.state.value;
        diag.value = 'holat: ${st.name}';
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
      diag.value = 'tayyor, javob kutilmoqda';
      Future<void>.delayed(const Duration(seconds: 6), () {
        if (_sf == sf && eval.value == null && _searching) {
          diag.value = 'javob yo\'q (qatorlar: $_lines)';
        }
      });
      final fen = _pendingFen;
      if (fen != null) analyze(fen);
    } catch (e) {
      debugPrint('Stockfish: $e');
      final msg = '$e';
      await stop();
      diag.value = 'xato: ${msg.length > 160 ? msg.substring(0, 160) : msg}';
    } finally {
      _starting = false;
    }
  }

  bool _searching = false; // dvigatel hozir qidirmoqda
  bool _waitingReady = false; // 'readyok' kutilmoqda
  bool _accept = false; // faqat yangi qidiruv javoblari qabul qilinadi

  /// Yangi pozitsiyani tahlil qiladi. Avval eski qidiruv to'xtatiladi,
  /// 'readyok' kelgach yangisi boshlanadi (javoblar chalkashmasligi uchun).
  void analyze(String fen) {
    _pendingFen = fen;
    final sf = _sf;
    if (sf == null || !ready.value) return;
    _accept = false;
    _waitingReady = true;
    if (_searching) sf.stdin = 'stop';
    sf.stdin = 'isready';
  }

  /// Tahlilni to'xtatadi va ko'rsatkichni tozalaydi (o'yin tugaganda).
  void clear() {
    _pendingFen = null;
    _accept = false;
    _waitingReady = false;
    final sf = _sf;
    if (sf != null && ready.value && _searching) sf.stdin = 'stop';
    eval.value = null;
  }

  void _onLine(String line) {
    _lines++;
    final sf = _sf;
    if (line.startsWith('bestmove')) {
      _searching = false;
      return;
    }
    if (line.trim() == 'readyok') {
      final fen = _pendingFen;
      if (_waitingReady && fen != null && sf != null) {
        _waitingReady = false;
        final parts = fen.split(' ');
        _whiteToMove = parts.length < 2 || parts[1] == 'w';
        _accept = true;
        _searching = true;
        sf.stdin = 'position fen $fen';
        sf.stdin = 'go movetime 1500';
      }
      return;
    }
    if (!_accept || !line.startsWith('info') || !line.contains(' score ')) {
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
    _searching = false;
    _waitingReady = false;
    _accept = false;
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
