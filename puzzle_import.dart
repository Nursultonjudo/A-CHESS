import 'dart:convert';

import 'package:chess/chess.dart' as ch;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'pgn.dart';
import 'settings.dart';
import 'widgets/chess_board.dart';

/// Fayldan o'qilgan pozitsiya (trener tahrirlab tasdiqlaydi).
class ImportedPosition {
  ImportedPosition(this.fen, this.title, this.solutions, {this.fromAi = false});
  final String fen;
  final String title;
  final List<String> solutions; // 'e2e4' ko'rinishida (bo'lishi ham mumkin, bo'lmasligi ham)
  final bool fromAi;
}

String _cleanSan(String s) => s.replaceAll('+', '').replaceAll('#', '');

/// PGN o'yinini boshlang'ich (yoki FEN sarlavhasidagi) pozitsiyadan qaytadan o'ynaydi.
({List<String> fens, List<String> ucis}) _replay(PgnGame g) {
  final fen = g.headers['FEN'];
  var game = ch.Chess();
  if (fen != null && fen.trim().isNotEmpty) {
    try {
      game = ch.Chess.fromFEN(fen.trim());
    } catch (_) {
      game = ch.Chess();
    }
  }
  final fens = <String>[game.fen];
  final ucis = <String>[];
  for (final san in g.sans) {
    final list = (game.moves({'verbose': true}) as List).cast<Map>();
    Map? found;
    for (final m in list) {
      if (_cleanSan(m['san'].toString()) == _cleanSan(san)) {
        found = m;
        break;
      }
    }
    if (found == null) break;
    game.move({
      'from': found['from'],
      'to': found['to'],
      if (found['promotion'] != null) 'promotion': found['promotion'],
    });
    ucis.add('${found['from']}${found['to']}');
    fens.add(game.fen);
  }
  return (fens: fens, ucis: ucis);
}

/// Fayl tanlash va undan pozitsiya olish. PGN aniq o'qiladi; rasm va PDF
/// A-CHESS AI (serverda) orqali o'qiladi — trener natijani tekshirishi shart.
Future<ImportedPosition?> importPositionFromFile(
    BuildContext context, AppSettings s, Pal pal) async {
  String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);
  void snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  final res = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const [
      'pgn', 'pdf', 'djvu', 'jpg', 'jpeg', 'png', 'heic', 'heif', 'webp', 'gif'
    ],
    withData: true,
  );
  if (res == null || res.files.isEmpty) return null;
  final f = res.files.first;
  final ext = (f.extension ?? '').toLowerCase();
  final bytes = f.bytes;
  if (bytes == null) {
    snack(t('pi_read_fail'));
    return null;
  }
  if (!context.mounted) return null;
  if (ext == 'djvu' || ext == 'heic' || ext == 'heif') {
    snack(t('pi_convert'));
    return null;
  }
  if (ext == 'pgn') {
    final games = parsePgn(utf8.decode(bytes, allowMalformed: true));
    if (games.isEmpty) {
      snack(t('pi_none'));
      return null;
    }
    PgnGame? g = games.first;
    if (games.length > 1) {
      g = await showDialog<PgnGame>(
        context: context,
        builder: (c) => SimpleDialog(
          title: Text(t('pi_pick_game')),
          children: [
            SizedBox(
              width: 420,
              height: 360,
              child: ListView(
                children: [
                  for (final x in games.take(300))
                    ListTile(
                      dense: true,
                      title: Text('${x.white} – ${x.black}'),
                      subtitle: Text('${x.event} ${x.date}  ·  ${x.sans.length}'),
                      onTap: () => Navigator.pop(c, x),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
      if (g == null) return null;
    }
    if (!context.mounted) return null;
    final rp = _replay(g);
    return _pickPly(context, s, pal, g, rp.fens, rp.ucis);
  }

  // Rasm yoki PDF
  const mimes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'pdf': 'application/pdf',
  };
  final mime = mimes[ext];
  final token = s.token;
  if (mime == null || token == null) return null;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [
        const CircularProgressIndicator(),
        const SizedBox(width: 16),
        Expanded(child: Text(t('pi_reading'))),
      ]),
    ),
  );
  List<Map<String, dynamic>> found = [];
  String? err;
  try {
    final r = await Api.post(
      '/ai/diagram',
      token,
      {'mime': mime, 'data': base64Encode(bytes)},
      timeout: const Duration(seconds: 150),
    );
    found = ((r['positions'] as List?) ?? const []).cast<Map<String, dynamic>>();
  } catch (e) {
    err = e is ApiException ? t(e.l10nKey) : t('err_network');
  }
  if (!context.mounted) return null;
  Navigator.of(context, rootNavigator: true).pop(); // yuklanmoqda oynasi
  if (err != null) {
    snack(err);
    return null;
  }
  if (found.isEmpty) {
    snack(t('pi_none'));
    return null;
  }
  return showDialog<ImportedPosition>(
    context: context,
    builder: (c) => SimpleDialog(
      title: Text(t('pi_pick_pos')),
      children: [
        SizedBox(
          width: 460,
          height: 480,
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(t('pi_ai_warn'),
                    style: TextStyle(fontSize: 12.5, color: pal.subtext)),
              ),
              for (var i = 0; i < found.length; i++)
                _AiTile(
                  p: found[i],
                  pal: pal,
                  s: s,
                  label: '${i + 1}. ${found[i]['caption'] ?? ''}',
                  conf: t('pi_conf_${found[i]['confidence']}'),
                  onTap: () {
                    final sol = '${found[i]['solution'] ?? ''}';
                    Navigator.pop(
                      c,
                      ImportedPosition(
                        '${found[i]['fen']}',
                        '${found[i]['caption'] ?? ''}'.trim(),
                        sol.isEmpty ? const [] : [sol],
                        fromAi: true,
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AiTile extends StatelessWidget {
  const _AiTile({
    required this.p,
    required this.pal,
    required this.s,
    required this.label,
    required this.conf,
    required this.onTap,
  });
  final Map<String, dynamic> p;
  final Pal pal;
  final AppSettings s;
  final String label;
  final String conf;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    ch.Chess? g;
    try {
      g = ch.Chess.fromFEN('${p['fen']}');
    } catch (_) {}
    return ListTile(
      onTap: g == null ? null : onTap,
      leading: SizedBox(
        width: 96,
        height: 96,
        child: g == null
            ? const Icon(Icons.error_outline)
            : IgnorePointer(
                child: ChessBoard(
                  game: g,
                  pal: pal,
                  style: s.boardStyle,
                  enabled: false,
                  onMoved: (_) {},
                ),
              ),
      ),
      title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(conf),
    );
  }
}

Future<ImportedPosition?> _pickPly(BuildContext context, AppSettings s, Pal pal,
    PgnGame g, List<String> fens, List<String> ucis) {
  String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);
  var ply = 0;
  final hasFen = (g.headers['FEN'] ?? '').trim().isNotEmpty;
  // FEN sarlavhali PGN (masala kitoblari): odatda boshlang'ich pozitsiya o'zi masala
  if (hasFen) ply = 0;
  return showDialog<ImportedPosition>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, setSt) {
      final gm = ch.Chess.fromFEN(fens[ply]);
      final nextSolution = ply < ucis.length ? ucis[ply] : null;
      return AlertDialog(
        title: Text(t('pi_pick_ply')),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 260,
                height: 260,
                child: IgnorePointer(
                  child: ChessBoard(
                    key: ValueKey(ply),
                    game: gm,
                    pal: pal,
                    style: s.boardStyle,
                    enabled: false,
                    onMoved: (_) {},
                  ),
                ),
              ),
              Slider(
                value: ply.toDouble(),
                min: 0,
                max: (fens.length - 1).toDouble(),
                divisions: fens.length > 1 ? fens.length - 1 : null,
                label: '$ply',
                onChanged: fens.length > 1 ? (v) => setSt(() => ply = v.round()) : null,
              ),
              Text(
                '${t('pi_ply')}: $ply / ${fens.length - 1}'
                '${nextSolution != null ? '  ·  ${t('pi_next_move')}: ${nextSolution.substring(0, 2)}-${nextSolution.substring(2)}' : ''}',
                style: TextStyle(color: pal.subtext, fontSize: 12.5),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(t('co_cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(
              c,
              ImportedPosition(
                fens[ply],
                '${g.white} – ${g.black}'.trim() == '? – ?' ? '' : '${g.white} – ${g.black}',
                nextSolution == null ? const [] : [nextSolution],
              ),
            ),
            child: Text(t('pi_use')),
          ),
        ],
      );
    }),
  );
}
