import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

/// UCI dvigatel bilan umumiy aloqa: buyruq yuborish va satrlarni o'qish.
abstract class _Uci {
  set stdin(String cmd);
  Stream<String> get stdout;
  void dispose();
}

/// Paket ichidagi Stockfish (Android va zaxira).
class _PkgUci implements _Uci {
  _PkgUci(this.sf);
  final Stockfish sf;
  @override
  set stdin(String cmd) => sf.stdin = cmd;
  @override
  Stream<String> get stdout => sf.stdout;
  @override
  void dispose() {
    try {
      sf.dispose();
    } catch (_) {}
  }
}

/// Alohida jarayon sifatida ishlaydigan rasmiy Stockfish (Windows).
class _ProcUci implements _Uci {
  _ProcUci(this.proc)
      : stdout = proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .asBroadcastStream();
  final Process proc;
  @override
  final Stream<String> stdout;
  @override
  set stdin(String cmd) {
    try {
      proc.stdin.writeln(cmd);
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      proc.stdin.writeln('quit');
    } catch (_) {}
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      try {
        proc.kill();
      } catch (_) {}
    });
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

  _Uci? _sf;
  final ValueNotifier<String> name = ValueNotifier('');
  StreamSubscription<String>? _sub;
  bool _starting = false;
  bool _whiteToMove = true;
  String? _pendingFen;

  /// Windows: ilova yonidagi `engine/stockfish.exe` (rasmiy Stockfish 18).
  Future<_ProcUci?> _tryProcess() async {
    try {
      final dir = File(Platform.resolvedExecutable).parent.path;
      final sep = Platform.pathSeparator;
      final exe = File('$dir${sep}engine${sep}stockfish.exe');
      if (!await exe.exists()) {
        diag.value = 'engine/stockfish.exe topilmadi';
        return null;
      }
      final proc = await Process.start(exe.path, const []);
      final u = _ProcUci(proc);
      unawaited(proc.stderr.drain<void>());
      // qo'l siqish: 'uci' -> 'uciok'
      var title = '';
      final sub = u.stdout.listen((l) {
        if (l.startsWith('id name ')) title = l.substring(8).trim();
      });
      u.stdin = 'uci';
      try {
        await u.stdout
            .firstWhere((l) => l.trim() == 'uciok')
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        await sub.cancel();
        u.dispose();
        diag.value = 'stockfish.exe javob bermadi';
        return null;
      }
      await sub.cancel();
      final cores = Platform.numberOfProcessors;
      final threads = math.max(1, math.min(cores - 1, 8));
      u.stdin = 'setoption name Threads value $threads';
      u.stdin = 'setoption name Hash value 256';
      name.value = '${title.isEmpty ? 'Stockfish' : title} · $threads thread';
      unawaited(proc.exitCode.then((_) {
        if (_sf == u) stop();
      }));
      return u;
    } catch (e) {
      diag.value = 'jarayon xatosi: $e';
      return null;
    }
  }

  Future<_PkgUci> _tryPackage() async {
    final sf = Stockfish();
    final u = _PkgUci(sf);
    for (var i = 0; i < 100; i++) {
      final st = sf.state.value;
      diag.value = 'holat: ${st.name}';
      if (st == StockfishState.ready) break;
      if (st == StockfishState.error || st == StockfishState.disposed) {
        u.dispose();
        throw StateError('Stockfish ishga tushmadi');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (sf.state.value != StockfishState.ready) {
      u.dispose();
      throw StateError('Stockfish tayyor bo\'lmadi');
    }
    u.stdin = 'setoption name Threads value 1';
    u.stdin = 'setoption name Hash value 32';
    name.value = 'Stockfish 17';
    return u;
  }

  Future<void> start() async {
    if (_sf != null || _starting) return;
    _starting = true;
    diag.value = 'start...';
    _lines = 0;
    try {
      _Uci? eng;
      if (Platform.isWindows) eng = await _tryProcess();
      eng ??= await _tryPackage();
      _sf = eng;
      _sub = eng.stdout.listen(_onLine);
      eng.stdin = 'uci';
      eng.stdin = 'isready';
      ready.value = true;
      diag.value = 'tayyor, javob kutilmoqda';
      Future<void>.delayed(const Duration(seconds: 6), () {
        if (_sf == eng && eval.value == null && _searching) {
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
    if (sf == null || !ready.value || _batch) return;
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

  // ---- To'plam (batch) tahlili: bir nechta pozitsiyani ketma-ket baholash ----
  bool _batch = false;
  bool _bAccept = false;
  bool _bWhite = true;
  String? _bFen;
  int _bMs = 500;
  EngineEval? _bLast;
  Completer<EngineEval?>? _bDone;
  List<String> _bPre = const [];
  List<String> _bPost = const [];
  String? _bGo;

  bool get batchBusy => _batch;

  /// Dvigatel tayyor bo'lishini kutadi (kerak bo'lsa ishga tushiradi).
  Future<bool> ensureReady() async {
    if (!ready.value) await start();
    return ready.value;
  }

  /// Bitta pozitsiyani `movetimeMs` davomida baholaydi (oq nuqtai nazaridan).
  Future<EngineEval?> evalOnce(
    String fen,
    int movetimeMs, {
    List<String> pre = const [],
    List<String> post = const [],
    String? go,
  }) async {
    final sf = _sf;
    if (sf == null || !ready.value) return null;
    _bPre = pre;
    _bPost = post;
    _bGo = go;
    _batch = true;
    _accept = false;
    _waitingReady = false;
    _bAccept = false;
    _bLast = null;
    _bFen = fen;
    _bMs = movetimeMs;
    final parts = fen.split(' ');
    _bWhite = parts.length < 2 || parts[1] == 'w';
    final done = Completer<EngineEval?>();
    _bDone = done;
    sf.stdin = 'stop';
    sf.stdin = 'isready';
    return done.future.timeout(
      Duration(milliseconds: movetimeMs + 5000),
      onTimeout: () {
        _bDone = null;
        _bAccept = false;
        sf.stdin = 'stop';
        for (final c in _bPost) {
          sf.stdin = c;
        }
        return _bLast;
      },
    );
  }

  /// Kompyuter raqib uchun yurish tanlaydi. [elo] — taxminiy kuch
  /// (UCI_Elo 1320..3190; undan past bo'lsa Skill Level ishlatiladi).
  /// Natija UCI ko'rinishida (masalan e2e4 yoki e7e8q), topilmasa null.
  Future<String?> playMove(String fen, {required int elo, required int ms}) async {
    if (!await ensureReady()) return null;
    final pre = <String>[];
    var go = 'go movetime $ms';
    if (elo >= 3190) {
      pre.add('setoption name UCI_LimitStrength value false');
      pre.add('setoption name Skill Level value 20');
    } else if (elo >= 1320) {
      pre.add('setoption name Skill Level value 20');
      pre.add('setoption name UCI_Elo value $elo');
      pre.add('setoption name UCI_LimitStrength value true');
    } else {
      final lvl = ((elo - 400) / 920 * 5).clamp(0, 5).round();
      pre.add('setoption name UCI_LimitStrength value false');
      pre.add('setoption name Skill Level value $lvl');
      go = 'go depth ${1 + (lvl ~/ 2)}';
    }
    final post = const [
      'setoption name UCI_LimitStrength value false',
      'setoption name Skill Level value 20',
    ];
    try {
      final e = await evalOnce(fen, ms, pre: pre, post: post, go: go);
      return e?.best;
    } finally {
      endBatch();
    }
  }

  /// To'plam tahlili tugadi: jonli tahlil yana ishlaydi.
  void endBatch() {
    _batch = false;
    _bDone = null;
    _bFen = null;
    final sf = _sf;
    if (sf != null && ready.value) sf.stdin = 'stop';
    final fen = _pendingFen;
    if (fen != null) analyze(fen);
  }

  void _onBatchLine(String line) {
    final sf = _sf;
    if (sf == null) return;
    if (line.trim() == 'readyok') {
      final fen = _bFen;
      if (!_bAccept && fen != null && _bDone != null) {
        _bAccept = true;
        for (final c in _bPre) {
          sf.stdin = c;
        }
        sf.stdin = 'position fen $fen';
        sf.stdin = _bGo ?? 'go movetime $_bMs';
      }
      return;
    }
    if (!_bAccept) return;
    if (line.startsWith('bestmove')) {
      final tk = line.split(' ');
      final bm = tk.length > 1 && tk[1] != '(none)' ? tk[1] : null;
      final l = _bLast;
      final r = l == null
          ? (bm == null ? null : EngineEval(cp: 0, depth: 0, best: bm))
          : EngineEval(cp: l.cp, mate: l.mate, depth: l.depth, best: bm);
      _bAccept = false;
      for (final c in _bPost) {
        sf.stdin = c;
      }
      final d = _bDone;
      _bDone = null;
      if (d != null && !d.isCompleted) d.complete(r);
      return;
    }
    if (!line.startsWith('info') || !line.contains(' score ')) return;
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
    final v = _bWhite ? val : -val;
    if (tk[si + 1] == 'cp') {
      _bLast = EngineEval(cp: v, depth: depth, best: best);
    } else if (tk[si + 1] == 'mate') {
      _bLast = EngineEval(mate: v, depth: depth, best: best);
    }
  }

  void _onLine(String line) {
    _lines++;
    if (_batch) {
      _onBatchLine(line);
      return;
    }
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
    name.value = '';
  }
}
