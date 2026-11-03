import 'package:flutter/material.dart';

import 'game_viewer.dart';
import 'games_data.dart';
import 'l10n.dart';
import 'openings_data.dart';
import 'pgn.dart';
import 'settings.dart';
import 'widgets/chess_board.dart';

/// Debyut liniyasi: ECO, nomi, asosiy qismi (lichess nomi bilan atalgan
/// pozitsiyagacha), usta partiyalari statistikasi va to'liq asosiy davomi.
class Opening {
  Opening({
    required this.eco,
    required this.name,
    required this.base,
    required this.games,
    required this.white,
    required this.draws,
    required this.black,
    required this.gameIds,
    required this.moves,
  });
  final String eco;
  final String name;
  final int base;
  final int games;
  final int white;
  final int draws;
  final int black;
  final List<int> gameIds;
  final List<String> moves;

  String get family {
    final i = name.indexOf(':');
    return i < 0 ? name : name.substring(0, i);
  }

  String get variation {
    final i = name.indexOf(':');
    return i < 0 ? name : name.substring(i + 1).trim();
  }

  String get group => openingGroupOf(moves);

  Map<String, String> get headers => {
        'Event': 'A-Chess: $name',
        'Site': 'A-Chess',
        'Date': '????.??.??',
        'White': '?',
        'Black': '?',
        'ECO': eco,
        'Opening': family,
        if (variation != family) 'Variation': variation,
      };

}

/// Guruhlar kodlari (l10n: og_<kod>).
const List<String> kOpeningGroups = [
  'open',
  'sicilian',
  'french',
  'caro',
  'e4other',
  'qg',
  'indian',
  'd4other',
  'english',
  'reti',
  'other',
];

String openingGroupOf(List<String> m) {
  if (m.isEmpty) return 'other';
  final a = m.first;
  final b = m.length > 1 ? m[1] : '';
  if (a == 'e4') {
    switch (b) {
      case 'e5':
        return 'open';
      case 'c5':
        return 'sicilian';
      case 'e6':
        return 'french';
      case 'c6':
        return 'caro';
      default:
        return 'e4other';
    }
  }
  if (a == 'd4') {
    if (b == 'd5') return 'qg';
    if (b == 'Nf6') return 'indian';
    return 'd4other';
  }
  if (a == 'c4') return 'english';
  if (a == 'Nf3') return 'reti';
  return 'other';
}

class OpeningFamily {
  OpeningFamily(this.name);
  final String name;
  final List<Opening> lines = [];
  int get games => lines.isEmpty ? 0 : lines.first.games;
  String get ecoRange {
    final codes = lines.map((l) => l.eco).toList()..sort();
    final a = codes.first;
    final b = codes.last;
    return a == b ? a : '$a–$b';
  }

  String get group => lines.first.group;
}

/// Namunaviy haqiqiy partiya.
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

  String get year => date.length >= 4 && date[0] != '?' ? date.substring(0, 4) : '';

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

List<Opening>? _all;
List<OpeningFamily>? _families;
final Map<int, GameRec> _gameCache = {};

List<Opening> get allOpenings => _all ??= [
      for (final row in kOpeningData)
        () {
          final p = row.split('|');
          return Opening(
            eco: p[0],
            name: p[1],
            base: int.parse(p[2]),
            games: int.parse(p[3]),
            white: int.parse(p[4]),
            draws: int.parse(p[5]),
            black: int.parse(p[6]),
            gameIds: p[7].isEmpty
                ? <int>[]
                : p[7].split(',').map(int.parse).toList(),
            moves: p[8].split(' '),
          );
        }(),
    ];

List<OpeningFamily> get allFamilies {
  if (_families != null) return _families!;
  final map = <String, OpeningFamily>{};
  final sorted = [...allOpenings]..sort((a, b) => b.games.compareTo(a.games));
  for (final o in sorted) {
    map.putIfAbsent(o.family, () => OpeningFamily(o.family)).lines.add(o);
  }
  final list = map.values.toList()
    ..sort((a, b) => b.games.compareTo(a.games));
  return _families = list;
}

GameRec gameById(int i) => _gameCache.putIfAbsent(i, () {
      final p = kGameData[i].split('|');
      return GameRec(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8],
          p[9].split(' '));
    });

/// "1.e4 e5 2.Nf3 Nc6 ..." ko'rinishi.
String fmtMoves(List<String> sans, {int max = 12, int upTo = -1}) {
  final b = StringBuffer();
  final n = upTo < 0 ? sans.length : upTo;
  for (var i = 0; i < n && i < max; i++) {
    if (i.isEven) b.write('${i ~/ 2 + 1}.');
    b.write(sans[i]);
    b.write(' ');
  }
  var s = b.toString().trim();
  if (n > max) s = '$s …';
  return s;
}

/// Asosiy oilalar uchun qisqa g'oya (uz / ru / en).
const Map<String, List<String>> kOpeningIdeas = {
  'Sicilian Defense': [
    'Qora 1.e4 ga c5 bilan javob beradi: markazni oq bilan baravar emas, qanotdan kurashadi. Keskin, nomutanosib o\'yin; qora c-vertikalda hujum qiladi, oq shoh qanotida.',
    'Чёрные отвечают на 1.e4 ходом c5 и борются за центр с фланга. Острая несимметричная игра: чёрные атакуют по c-вертикали, белые — на королевском фланге.',
    'Black answers 1.e4 with c5, fighting for the centre from the flank. Sharp, unbalanced play: Black attacks on the c-file, White on the kingside.',
  ],
  'Ruy Lopez': [
    '1.e4 e5 2.Nf3 Nc6 3.Bb5: oq e5 dagi otni qo\'llab turgan otga bosim qiladi. Eng nufuzli klassik debyutlardan; strategik, sekin kurash.',
    '1.e4 e5 2.Nf3 Nc6 3.Bb5: белые давят на коня, защищающего e5. Один из самых авторитетных классических дебютов; позиционная борьба.',
    '1.e4 e5 2.Nf3 Nc6 3.Bb5: White pressures the knight that defends e5. One of the most respected classical openings, rich in strategy.',
  ],
  'French Defense': [
    '1.e4 e6 2.d4 d5: qora mustahkam piyoda zanjiri quradi. Qora fili c8 ko\'pincha yopiq qoladi, lekin pozitsiya chidamli va c5, f6 sinovlari bor.',
    '1.e4 e6 2.d4 d5: чёрные строят прочную пешечную цепь. Слон c8 часто заперт, но позиция надёжна, контригра идёт ходами c5 и f6.',
    '1.e4 e6 2.d4 d5: Black builds a solid pawn chain. The c8-bishop is often locked in, but the position is sturdy with counterplay via c5 and f6.',
  ],
  "Queen's Gambit Declined": [
    '1.d4 d5 2.c4 e6: qora piyodani olmaydi, markazni saqlaydi. Mustahkam, klassik tuzilma; oq azchilik hujumi (c4xd5) bilan bosim qiladi.',
    '1.d4 d5 2.c4 e6: чёрные не берут пешку и держат центр. Надёжная классическая структура; белые давят «меньшинством» на ферзевом фланге.',
    '1.d4 d5 2.c4 e6: Black declines the pawn and keeps the centre. A solid classical structure; White often plays the minority attack.',
  ],
  'Italian Game': [
    '1.e4 e5 2.Nf3 Nc6 3.Bc4: fil f7 ga qaratiladi. Tez rivojlanish va markaz uchun kurash; Giuoco Piano — sokin, Evans gambiti — o\'tkir.',
    '1.e4 e5 2.Nf3 Nc6 3.Bc4: слон целится в f7. Быстрое развитие и борьба за центр; Джуоко Пьяно — спокойное, гамбит Эванса — острое.',
    '1.e4 e5 2.Nf3 Nc6 3.Bc4: the bishop eyes f7. Quick development and fight for the centre; Giuoco Piano is calm, the Evans Gambit is sharp.',
  ],
  'English Opening': [
    '1.c4: oq markazni c4 dan nazorat qiladi, ko\'pincha ferzlik qanotida bosim. Juda moslashuvchan; ko\'p hollarda boshqa debyutlarga o\'tadi.',
    '1.c4: белые контролируют центр с фланга, часто давят на ферзевом фланге. Очень гибкий дебют, нередко переходит в другие схемы.',
    '1.c4: White controls the centre from the flank, often pressing on the queenside. Very flexible and often transposes.',
  ],
  "King's Gambit Accepted": [
    '1.e4 e5 2.f4 exf4: oq piyodani qurbon qilib, tez hujum va markazni oladi. Romantik davr debyuti: keskin, xavfli, ammo ta\'sirli.',
    '1.e4 e5 2.f4 exf4: белые жертвуют пешку ради быстрой атаки и центра. Дебют романтической эпохи: остро, рискованно, но эффектно.',
    '1.e4 e5 2.f4 exf4: White sacrifices a pawn for quick attack and centre. A romantic-era opening: sharp, risky and spectacular.',
  ],
  "King's Indian Defense": [
    'Qora markazni oqqa beradi, so\'ng piyoda zarbalari (e5, c5) bilan hujumga o\'tadi. Shoh qanotida kuchli hujum imkonini beradi; dinamik, tez tugaydigan janglar.',
    'Чёрные уступают центр, затем контратакуют ходами e5 и c5. Сильная атака на королевском фланге; динамичная и острая борьба.',
    'Black concedes the centre, then strikes back with e5 or c5. Strong kingside attacking chances; dynamic, double-edged play.',
  ],
  'Caro-Kann Defense': [
    '1.e4 c6 2.d4 d5: qora mustahkam va xavfsiz. Fil c8 ni tashqariga chiqarish oson, pozitsiya sog\'lom; endshpilda foydali.',
    '1.e4 c6 2.d4 d5: чёрные играют надёжно. Слон c8 легко выходит, позиция здоровая; хорошо для эндшпиля.',
    '1.e4 c6 2.d4 d5: solid and safe for Black. The c8-bishop easily gets out; a healthy structure that suits the endgame.',
  ],
  'Nimzo-Indian Defense': [
    '1.d4 Nf6 2.c4 e6 3.Nc3 Bb4: qora fil bilan oq otni qoziqqa qo\'yadi va e4 ni nazorat qiladi. Eng ishonchli qora tizimlardan biri.',
    '1.d4 Nf6 2.c4 e6 3.Nc3 Bb4: чёрные связывают коня слоном и контролируют e4. Одна из самых надёжных систем за чёрных.',
    '1.d4 Nf6 2.c4 e6 3.Nc3 Bb4: Black pins the knight and controls e4. One of Black\'s most reliable systems.',
  ],
  'Semi-Slav Defense': [
    'Qora c6 va e6 ni birga qo\'yadi: zich, lekin juda keskin nazariya. Meran va Botvinnik variantlari mashhur.',
    'Чёрные ставят c6 и e6: плотная, но очень острая теория. Известны варианты Меран и Ботвинника.',
    'Black plays both c6 and e6: compact but razor-sharp theory. The Meran and Botvinnik variations are famous.',
  ],
  'Slav Defense': [
    '1.d4 d5 2.c4 c6: qora d5 ni mustahkam ushlaydi va filini c8 dan tashqariga chiqaradi. Ishonchli, zamonaviy turnirlarda ko\'p uchraydi.',
    '1.d4 d5 2.c4 c6: чёрные прочно держат d5 и вывод слона c8 наружу. Надёжно, часто встречается в современных турнирах.',
    '1.d4 d5 2.c4 c6: Black holds d5 firmly and develops the c8-bishop outside. Reliable and common at top level.',
  ],
  'Grünfeld Defense': [
    'Qora markazni oqqa berib, keyin uni fil g7 va piyodalar zarbasi bilan buzadi. Dinamik, nazariyaga boy.',
    'Чёрные позволяют белым занять центр, а затем разрушают его слоном g7 и пешечными ударами. Динамично и теоретически насыщенно.',
    'Black lets White build a big centre and then undermines it with the g7-bishop and pawn breaks. Dynamic and theory-heavy.',
  ],
  "Queen's Gambit Accepted": [
    '1.d4 d5 2.c4 dxc4: qora piyodani oladi, lekin uni ushlab tura olmaydi. Oq markazni oladi, qora tez rivojlanishga intiladi.',
    '1.d4 d5 2.c4 dxc4: чёрные берут пешку, но удержать её трудно. Белые получают центр, чёрные стремятся к быстрому развитию.',
    '1.d4 d5 2.c4 dxc4: Black takes the pawn but usually can\'t keep it. White gets the centre, Black aims for quick development.',
  ],
  "Queen's Indian Defense": [
    'Qora fil b7 bilan e4 va markazni nazorat qiladi. Sokin, strategik; pozitsiya egiluvchan.',
    'Чёрные контролируют центр слоном b7. Спокойная стратегическая игра, позиция гибкая.',
    'Black controls the centre with the b7-bishop. Quiet, strategic play with a flexible structure.',
  ],
  'Dutch Defense': [
    '1.d4 f5: qora e4 maydonini nazorat qiladi va shoh qanotida hujum rejasini tanlaydi. Keskin, ammo shoh biroz ochiladi.',
    '1.d4 f5: чёрные контролируют e4 и выбирают атаку на королевском фланге. Остро, но позиция короля слегка ослаблена.',
    '1.d4 f5: Black controls e4 and aims for a kingside attack. Sharp, though the king becomes slightly exposed.',
  ],
  'Scandinavian Defense': [
    '1.e4 d5: qora markazni darhol sinaydi. Sodda g\'oyalar, kam nazariya; ferzni erta chiqarish xavfi bor.',
    '1.e4 d5: чёрные сразу оспаривают центр. Простые идеи, мало теории; ферзь выходит рано.',
    '1.e4 d5: Black challenges the centre at once. Simple ideas and little theory; the queen comes out early.',
  ],
  'Scotch Game': [
    '1.e4 e5 2.Nf3 Nc6 3.d4: oq markazni ochadi va tez faollik oladi. Ochiq pozitsiyalar, aniq rejalar.',
    '1.e4 e5 2.Nf3 Nc6 3.d4: белые вскрывают центр и получают активность. Открытая игра, ясные планы.',
    '1.e4 e5 2.Nf3 Nc6 3.d4: White opens the centre and gains activity. Open positions and clear plans.',
  ],
  "Petrov's Defense": [
    '1.e4 e5 2.Nf3 Nf6: qora simmetriya bilan javob beradi. Juda mustahkam, durang ehtimoli yuqori.',
    '1.e4 e5 2.Nf3 Nf6: чёрные отвечают симметрично. Очень надёжно, ничейная тенденция.',
    '1.e4 e5 2.Nf3 Nf6: Black mirrors White. Very solid, with a high drawing tendency.',
  ],
  'Vienna Game': [
    '1.e4 e5 2.Nc3: oq f4 ni tayyorlab, markazda keskin o\'yin boshlaydi. Egiluvchan, hujumga moyil.',
    '1.e4 e5 2.Nc3: белые готовят f4 и начинают активную игру в центре. Гибкий дебют с атакующим уклоном.',
    '1.e4 e5 2.Nc3: White prepares f4 for an active centre. A flexible opening with attacking potential.',
  ],
  'Catalan Opening': [
    'Oq g3 va Bg2 bilan uzun diagonalni ochadi. Sokin, lekin ushlab turuvchi bosim; endshpilga yaxshi.',
    'Белые разворачивают слона на g2 по длинной диагонали. Спокойное, но постоянное давление; хорошо для эндшпиля.',
    'White fianchettoes the bishop on the long diagonal. Quiet but lasting pressure, good for endgames.',
  ],
  'Pirc Defense': [
    'Qora markazni oqqa berib, fil g7 va piyoda zarbalari bilan kurashadi. Egiluvchan, hujumli tizim.',
    'Чёрные позволяют белым занять центр и борются слоном g7 и пешечными ударами. Гибкая атакующая система.',
    'Black lets White take the centre and fights with the g7-bishop and pawn breaks. A flexible, counter-attacking system.',
  ],
  'Alekhine Defense': [
    '1.e4 Nf6: qora oqni oldinga siljitishga undaydi, keyin markazga hujum qiladi. Giperzamonaviy g\'oya.',
    '1.e4 Nf6: чёрные провоцируют белых на продвижение пешек, затем атакуют центр. Гипермодернистская идея.',
    '1.e4 Nf6: Black provokes White to advance, then attacks the centre. A hypermodern idea.',
  ],
  'Benoni Defense': [
    'Qora assimetrik tuzilma yaratadi: ferzlik qanotida faollik, oq markazda ustunlik. Keskin, dinamik.',
    'Чёрные создают асимметричную структуру: активность на ферзевом фланге против центра белых. Остро и динамично.',
    'Black creates an asymmetrical structure: queenside activity against White\'s centre. Sharp and dynamic.',
  ],
  "Bishop's Opening": [
    '1.e4 e5 2.Bc4: oq filni tez chiqaradi va f7 ni nishonga oladi. Italyan o\'yiniga yaqin, egiluvchan.',
    '1.e4 e5 2.Bc4: белые быстро выводят слона на f7. Близок к итальянской партии, гибкий.',
    '1.e4 e5 2.Bc4: White develops the bishop at once, eyeing f7. Close to the Italian, and flexible.',
  ],
  'Four Knights Game': [
    'Ikkala tomon ham otlarini rivojlantiradi: sokin va mustahkam, strategik kurash.',
    'Обе стороны развивают коней: спокойная и надёжная стратегическая игра.',
    'Both sides develop knights: calm, solid and strategic.',
  ],
  "Queen's Pawn Game": [
    '1.d4 bilan boshlanuvchi ko\'p tizimlar (London, Kolle, Torre): oddiy g\'oyalar, mustahkam rivojlanish.',
    'Множество систем после 1.d4 (Лондон, Колле, Торре): простые идеи и надёжное развитие.',
    'Many systems after 1.d4 (London, Colle, Torre): simple ideas and solid development.',
  ],
  'Réti Opening': [
    '1.Nf3 va c4: oq markazni piyoda emas, figuralar bilan nazorat qiladi. Giperzamonaviy yondashuv.',
    '1.Nf3 и c4: белые контролируют центр фигурами, а не пешками. Гипермодернистский подход.',
    '1.Nf3 and c4: White controls the centre with pieces rather than pawns. A hypermodern approach.',
  ],
  'Philidor Defense': [
    '1.e4 e5 2.Nf3 d6: qora e5 ni mustahkam ushlaydi. Pozitsiya tor, lekin chidamli.',
    '1.e4 e5 2.Nf3 d6: чёрные прочно защищают e5. Позиция тесная, но надёжная.',
    '1.e4 e5 2.Nf3 d6: Black defends e5 solidly. Cramped but resilient.',
  ],
  'Modern Defense': [
    'Qora fil g7 ni ertaroq chiqarib, markazni keyinroq sinaydi. Moslashuvchan, zamonaviy.',
    'Чёрные рано развивают слона g7 и оспаривают центр позже. Гибкая современная система.',
    'Black fianchettoes early and challenges the centre later. Flexible and modern.',
  ],
  "King's Gambit Declined": [
    'Qora gambitni qabul qilmaydi va markazni saqlaydi. Oq hujumi sekinroq, lekin xavfli bo\'lib qoladi.',
    'Чёрные отказываются от гамбита и держат центр. Атака белых медленнее, но остаётся опасной.',
    'Black declines the gambit and holds the centre. White\'s attack is slower but still dangerous.',
  ],
};

String openingIdea(String lang, String family) {
  final v = kOpeningIdeas[family];
  if (v == null) return '';
  return v[lang == 'uz' ? 0 : (lang == 'ru' ? 1 : 2)];
}


// ---------------------------------------------------------------------------
// Umumiy kichik vidjetlar
// ---------------------------------------------------------------------------

/// Oq / durang / qora foizlari chizig'i.
class ResultBar extends StatelessWidget {
  const ResultBar({
    super.key,
    required this.w,
    required this.d,
    required this.b,
    this.height = 18,
  });
  final int w;
  final int d;
  final int b;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tot = (w + d + b).clamp(1, 1 << 30);
    String pc(int x) => '${(x * 100 / tot).round()}%';
    Widget seg(int x, Color bg, Color fg) => Expanded(
          flex: x == 0 ? 1 : x,
          child: Container(
            height: height,
            alignment: Alignment.center,
            color: bg,
            child: x * 100 / tot >= 12
                ? Text(pc(x),
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800, color: fg))
                : null,
          ),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Row(
        children: [
          seg(w, const Color(0xFFF1F5F9), const Color(0xFF0F172A)),
          seg(d, const Color(0xFF94A3B8), const Color(0xFF0F172A)),
          seg(b, const Color(0xFF1E293B), const Color(0xFFF1F5F9)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Darsliklar bosh sahifasi
// ---------------------------------------------------------------------------

class OpeningsView extends StatefulWidget {
  const OpeningsView({super.key, required this.settings, required this.pal});
  final AppSettings settings;
  final Pal pal;

  @override
  State<OpeningsView> createState() => _OpeningsViewState();
}

class _OpeningsViewState extends State<OpeningsView> {
  final _ctl = TextEditingController();
  String _group = 'all';
  String _q = '';

  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _openFamily(OpeningFamily f) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OpeningFamilyPage(settings: s, pal: pal, family: f),
    ));
  }

  void _openLine(Opening o) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OpeningLinePage(settings: s, pal: pal, opening: o),
    ));
  }

  Widget _card({required Widget child, VoidCallback? onTap}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: pal.card,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: pal.cardBorder),
              ),
              child: child,
            ),
          ),
        ),
      );

  Widget _ecoChip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: pal.accentSoft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: pal.text,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final searching = q.length >= 2;
    final fams = [
      for (final f in allFamilies)
        if (_group == 'all' || f.group == _group) f,
    ];
    final counts = <String, int>{};
    for (final f in allFamilies) {
      counts[f.group] = (counts[f.group] ?? 0) + f.lines.length;
    }
    List<Opening> found = const [];
    if (searching) {
      found = [
        for (final o in allOpenings)
          if ((_group == 'all' || o.group == _group) &&
              (o.name.toLowerCase().contains(q) ||
                  o.eco.toLowerCase() == q ||
                  o.moves.join(' ').toLowerCase().contains(q)))
            o,
      ]..sort((a, b) => b.games.compareTo(a.games));
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Icon(Icons.menu_book, color: pal.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t('nav_lessons'),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: pal.text,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PgnDatabasePage(settings: s, pal: pal),
                    ),
                  ),
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: Text(t('db_open_pgn')),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              t('ol_intro', {
                'a': '${allFamilies.length}',
                'b': '${allOpenings.length}',
                'c': '${kGameData.length}',
              }),
              style: TextStyle(color: pal.subtext),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctl,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t('ol_search'),
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _ctl.clear();
                          _q = '';
                        }),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: Text(t('pz_all')),
                  selected: _group == 'all',
                  onSelected: (_) => setState(() => _group = 'all'),
                ),
                for (final g in kOpeningGroups)
                  if ((counts[g] ?? 0) > 0)
                    ChoiceChip(
                      label: Text('${t('og_$g')} · ${counts[g]}'),
                      selected: _group == g,
                      onSelected: (_) => setState(() => _group = g),
                    ),
              ],
            ),
            const SizedBox(height: 12),
            if (searching) ...[
              Text(
                t('ol_found', {'n': '${found.length}'}),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: pal.text,
                ),
              ),
              const SizedBox(height: 8),
              for (final o in found.take(150)) _lineCard(o),
              if (found.length > 150)
                Text(t('ol_more'), style: TextStyle(color: pal.subtext)),
            ] else
              for (final f in fams) _familyCard(f),
          ],
        ),
      ),
    );
  }

  Widget _lineCard(Opening o) => _card(
        onTap: () => _openLine(o),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    o.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: pal.text,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _ecoChip(o.eco),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              fmtMoves(o.moves, max: 12),
              style: TextStyle(fontSize: 13, color: pal.subtext),
            ),
            const SizedBox(height: 6),
            ResultBar(w: o.white, d: o.draws, b: o.black, height: 14),
          ],
        ),
      );

  Widget _familyCard(OpeningFamily f) {
    final idea = openingIdea(s.lang, f.name);
    final top = f.lines.first;
    return _card(
      onTap: () => _openFamily(f),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  f.name,
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: pal.text,
                  ),
                ),
              ),
              _ecoChip(f.ecoRange),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${t('ol_lines', {'n': '${f.lines.length}'})} · ${t('ol_games', {'n': '${top.games}'})}',
            style: TextStyle(fontSize: 13, color: pal.subtext),
          ),
          const SizedBox(height: 6),
          ResultBar(w: top.white, d: top.draws, b: top.black, height: 14),
          if (idea.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              idea,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, color: pal.text),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Oila sahifasi: barcha liniyalar
// ---------------------------------------------------------------------------

class OpeningFamilyPage extends StatefulWidget {
  const OpeningFamilyPage({
    super.key,
    required this.settings,
    required this.pal,
    required this.family,
  });
  final AppSettings settings;
  final Pal pal;
  final OpeningFamily family;

  @override
  State<OpeningFamilyPage> createState() => _OpeningFamilyPageState();
}

class _OpeningFamilyPageState extends State<OpeningFamilyPage> {
  String _q = '';
  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);

  @override
  Widget build(BuildContext context) {
    final f = widget.family;
    final idea = openingIdea(s.lang, f.name);
    final q = _q.trim().toLowerCase();
    final lines = [
      for (final o in f.lines)
        if (q.isEmpty ||
            o.name.toLowerCase().contains(q) ||
            o.eco.toLowerCase() == q)
          o,
    ];
    return Scaffold(
      backgroundColor: pal.bg1,
      appBar: AppBar(title: Text(f.name)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (idea.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: pal.accentSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: pal.accent),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lightbulb_outline, color: pal.accent),
                          const SizedBox(width: 6),
                          Text(
                            t('ol_idea'),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: pal.text,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(idea, style: TextStyle(color: pal.text)),
                    ],
                  ),
                ),
              if (f.lines.length > 8)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: t('ol_search_var'),
                    ),
                  ),
                ),
              Text(
                t('ol_lines', {'n': '${lines.length}'}),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: pal.text,
                ),
              ),
              const SizedBox(height: 8),
              for (final o in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: pal.card,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => OpeningLinePage(
                            settings: s,
                            pal: pal,
                            opening: o,
                          ),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: pal.cardBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    o.variation == f.name
                                        ? f.name
                                        : o.variation,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: pal.text,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  o.eco,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: pal.accent,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              fmtMoves(o.moves, max: 14),
                              style: TextStyle(
                                fontSize: 12.5,
                                color: pal.subtext,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ResultBar(
                              w: o.white,
                              d: o.draws,
                              b: o.black,
                              height: 13,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${t('ol_games', {'n': '${o.games}'})} · ${t('ol_moves_count', {'n': '${(o.moves.length + 1) ~/ 2}'})}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: pal.subtext,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Liniya sahifasi: PGN, mashq, Stockfish tahlili va namunaviy partiyalar
// ---------------------------------------------------------------------------

class OpeningLinePage extends StatelessWidget {
  const OpeningLinePage({
    super.key,
    required this.settings,
    required this.pal,
    required this.opening,
  });
  final AppSettings settings;
  final Pal pal;
  final Opening opening;

  String t(String k, [Map<String, String> a = const {}]) =>
      tr(settings.lang, k, a);

  @override
  Widget build(BuildContext context) {
    final o = opening;
    final idea = openingIdea(settings.lang, o.family);
    return Scaffold(
      backgroundColor: pal.bg1,
      appBar: AppBar(title: Text(o.name, style: const TextStyle(fontSize: 16))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: pal.accentSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      o.eco,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: pal.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${t('ol_games', {'n': '${o.games}'})} · ${t('ol_moves_count', {'n': '${(o.moves.length + 1) ~/ 2}'})}',
                      style: TextStyle(color: pal.subtext),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ResultBar(w: o.white, d: o.draws, b: o.black),
              const SizedBox(height: 12),
              GameBoardPanel(
                settings: settings,
                pal: pal,
                sans: o.moves,
                headers: o.headers,
                result: '*',
                practice: true,
              ),
              const SizedBox(height: 16),
              Text(
                t('ol_real_games'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: pal.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t('ol_real_games_hint'),
                style: TextStyle(fontSize: 12.5, color: pal.subtext),
              ),
              const SizedBox(height: 8),
              for (final id in o.gameIds) _gameTile(context, gameById(id)),
              if (idea.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: pal.accentSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: pal.accent),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${t('ol_idea')}: ${o.family}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: pal.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(idea, style: TextStyle(color: pal.text)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gameTile(BuildContext context, GameRec g) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: pal.card,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GameViewerPage(
                  settings: settings,
                  pal: pal,
                  game: g.toPgn(),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                            if (g.event.isNotEmpty && g.event != '?') g.event,
                            if (g.year.isNotEmpty) g.year,
                            if (g.whiteElo.isNotEmpty || g.blackElo.isNotEmpty)
                              '${g.whiteElo.isEmpty ? '?' : g.whiteElo}/${g.blackElo.isEmpty ? '?' : g.blackElo}',
                          ].join(' · '),
                          style: TextStyle(fontSize: 12.5, color: pal.subtext),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    g.result,
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
}
