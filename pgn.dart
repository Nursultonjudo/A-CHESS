/// PGN (Portable Game Notation) o'qish va yozish.
class PgnGame {
  PgnGame({Map<String, String>? headers, List<String>? sans, String? result})
      : headers = headers ?? <String, String>{},
        sans = sans ?? <String>[],
        result = result ?? '*';

  final Map<String, String> headers;
  final List<String> sans;
  String result;

  String get white => headers['White'] ?? '?';
  String get black => headers['Black'] ?? '?';
  String get event => headers['Event'] ?? '';
  String get date => headers['Date'] ?? '';
  String get eco => headers['ECO'] ?? '';
  String get opening => headers['Opening'] ?? '';
  String get res => headers['Result'] ?? result;

  String get year {
    final d = date;
    return d.length >= 4 && d[0] != '?' ? d.substring(0, 4) : '';
  }

  String toPgn() => buildPgn(headers, sans, res);
}

final RegExp _tagRe = RegExp(r'^\[(\w+)\s+"((?:[^"\\]|\\.)*)"\]\s*$');

String _cleanMoveText(String s) {
  var t = s.replaceAll('\r', '');
  t = t.replaceAll(RegExp(r'\{[^}]*\}'), ' ');
  t = t.replaceAll(RegExp(r';[^\n]*'), ' ');
  String prev;
  do {
    prev = t;
    t = t.replaceAll(RegExp(r'\([^()]*\)'), ' ');
  } while (t != prev);
  t = t.replaceAll(RegExp(r'\$\d+'), ' ');
  t = t.replaceAll(RegExp(r'\d+\s*\.(\s*\.\.)?'), ' ');
  return t;
}

/// Matndagi barcha o'yinlarni o'qiydi (bitta yoki ko'p o'yinli PGN).
List<PgnGame> parsePgn(String text) {
  final games = <PgnGame>[];
  final lines = text.replaceAll('﻿', '').split('\n');
  var headers = <String, String>{};
  final move = StringBuffer();

  void flush() {
    final body = move.toString().trim();
    if (headers.isEmpty && body.isEmpty) return;
    final g = PgnGame(headers: headers);
    final toks = _cleanMoveText(body).split(RegExp(r'\s+'));
    for (var t in toks) {
      if (t.isEmpty) continue;
      if (t == '1-0' || t == '0-1' || t == '1/2-1/2' || t == '*') {
        g.result = t;
        continue;
      }
      t = t.replaceAll(RegExp(r'[!?]+$'), '');
      if (t.startsWith('0-0-0')) t = t.replaceFirst('0-0-0', 'O-O-O');
      if (t.startsWith('0-0')) t = t.replaceFirst('0-0', 'O-O');
      if (t == '--' || t == '...' || t.isEmpty) continue;
      g.sans.add(t);
    }
    if (g.sans.isNotEmpty || g.headers.isNotEmpty) {
      if (g.headers['Result'] != null && g.result == '*') {
        g.result = g.headers['Result']!;
      }
      games.add(g);
    }
    headers = <String, String>{};
    move.clear();
  }

  for (final raw in lines) {
    final line = raw.trimRight();
    final m = _tagRe.firstMatch(line);
    if (m != null) {
      if (move.toString().trim().isNotEmpty) flush();
      headers[m.group(1)!] = m.group(2)!.replaceAll(r'\"', '"');
    } else {
      move.write(' $line');
    }
  }
  flush();
  return games;
}

/// SAN ro'yxatdan PGN matn yasaydi (7 ta asosiy teg + qo'shimchalar).
String buildPgn(
  Map<String, String> headers,
  List<String> sans,
  String result, {
  List<String>? suffix, // har bir yurishdan keyin: '?!', '?', '??'
  List<String>? comments, // har bir yurishdan keyin {izoh}
}) {
  final h = <String, String>{
    'Event': headers['Event'] ?? '?',
    'Site': headers['Site'] ?? '?',
    'Date': headers['Date'] ?? '????.??.??',
    'Round': headers['Round'] ?? '?',
    'White': headers['White'] ?? '?',
    'Black': headers['Black'] ?? '?',
    'Result': result,
  };
  headers.forEach((k, v) {
    if (!h.containsKey(k)) h[k] = v;
  });
  final b = StringBuffer();
  h.forEach((k, v) => b.writeln('[$k "${v.replaceAll('"', r'\"')}"]'));
  b.writeln();
  final mv = StringBuffer();
  for (var i = 0; i < sans.length; i++) {
    if (i.isEven) mv.write('${i ~/ 2 + 1}. ');
    mv.write('${sans[i]}${suffix != null && i < suffix.length ? suffix[i] : ''} ');
    if (comments != null && i < comments.length && comments[i].isNotEmpty) {
      mv.write('{${comments[i].replaceAll('{', '(').replaceAll('}', ')')}} ');
      if (i.isEven && i + 1 < sans.length) mv.write('${i ~/ 2 + 1}... ');
    }
  }
  mv.write(result);
  // 80 belgidan oshmasin
  final words = mv.toString().split(' ');
  var line = '';
  for (final w in words) {
    if (line.isNotEmpty && line.length + w.length + 1 > 80) {
      b.writeln(line);
      line = w;
    } else {
      line = line.isEmpty ? w : '$line $w';
    }
  }
  if (line.isNotEmpty) b.writeln(line);
  return b.toString();
}
