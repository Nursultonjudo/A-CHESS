import 'games_data.dart';
import 'pgn.dart';

/// Namunaviy haqiqiy partiya (games_data.dart dan).
/// Format: Oq|Qora|Turnir|Joy|Sana|Natija|ECO|OqElo|QoraElo|yurishlar
class GameRec {
  GameRec(this.white, this.black, this.event, this.site, this.date,
      this.result, this.eco, this.whiteElo, this.blackElo, this.moves);
  final String white;
  final String black;
  final String event;
  final String site;
  final String date;
  final String result;
  final String eco;
  final String whiteElo;
  final String blackElo;
  final List<String> moves;

  String get year =>
      date.length >= 4 && date[0] != '?' ? date.substring(0, 4) : '';

  PgnGame toPgn() => PgnGame(
        headers: {
          'Event': event.isEmpty ? '?' : event,
          'Site': site.isEmpty ? '?' : site,
          'Date': date.isEmpty ? '????.??.??' : date,
          'White': white,
          'Black': black,
          'Result': result,
          if (eco.isNotEmpty) 'ECO': eco,
          if (whiteElo.isNotEmpty) 'WhiteElo': whiteElo,
          if (blackElo.isNotEmpty) 'BlackElo': blackElo,
        },
        sans: List<String>.of(moves),
        result: result,
      );
}

final Map<int, GameRec> _gameCache = {};

GameRec gameById(int i) => _gameCache.putIfAbsent(i, () {
      final p = kGameData[i].split('|');
      return GameRec(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8],
          p[9].split(' '));
    });
