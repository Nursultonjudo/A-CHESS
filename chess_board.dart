// A-CHESS: ranglar, donalar, doska, o'yinchi kartalari, soat va yurishlar ro'yxati.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show FontFeature;

import 'package:chess/chess.dart' as ch;
import 'package:flutter/gestures.dart'
    show EagerGestureRecognizer, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../sound.dart';

// ---------------------------------------------------------------------------
// Ranglar: 3 uslub (0 = klassik yog'och, 1 = marmar va oltin, 2 = zamonaviy)
// x kunduzgi/tungi rejim
// ---------------------------------------------------------------------------

class Pal {
  const Pal({
    required this.bg1,
    required this.bg2,
    required this.card,
    required this.cardBorder,
    required this.text,
    required this.subtext,
    required this.accent,
    required this.navTop,
    required this.navBottom,
    required this.navText,
    required this.navIcon,
    required this.boardLight,
    required this.boardDark,
    required this.frameA,
    required this.frameB,
    required this.frameLine,
    required this.frameText,
    required this.avatarWhite,
    required this.avatarBlack,
  });

  final Color bg1, bg2, card, cardBorder, text, subtext, accent;
  final Color navTop, navBottom, navText, navIcon;
  final Color boardLight, boardDark, frameA, frameB, frameLine, frameText;
  final Color avatarWhite, avatarBlack;

  Color get accentSoft => accent.withAlpha(0x2E);

  /// [style] doska uslubi (doska va ramka ranglari), [ui] ekran dizayni
  /// (fon, kartalar, yon panel ranglari).
  static Pal of(int style, bool dark, [int ui = 0]) {
    final s = (style < 0 || style > 2) ? 0 : style;
    final u = (ui < 0 || ui > 2) ? 0 : ui;
    final b = _pals[s][dark ? 1 : 0];
    final c = _uiPals[u][dark ? 1 : 0];
    return Pal(
      bg1: c.bg1, bg2: c.bg2,
      card: c.card, cardBorder: c.cardBorder,
      text: c.text, subtext: c.subtext,
      accent: c.accent,
      navTop: c.navTop, navBottom: c.navBottom,
      navText: c.navText, navIcon: c.navIcon,
      boardLight: b.boardLight, boardDark: b.boardDark,
      frameA: b.frameA, frameB: b.frameB,
      frameLine: b.frameLine, frameText: b.frameText,
      avatarWhite: b.avatarWhite, avatarBlack: b.avatarBlack,
    );
  }
}

class _UiPal {
  const _UiPal({
    required this.bg1,
    required this.bg2,
    required this.card,
    required this.cardBorder,
    required this.text,
    required this.subtext,
    required this.accent,
    required this.navTop,
    required this.navBottom,
    required this.navText,
    required this.navIcon,
  });
  final Color bg1, bg2, card, cardBorder, text, subtext, accent;
  final Color navTop, navBottom, navText, navIcon;
}

// Ekran dizaynlari: 0 = Maktab (to'q ko'k + amber), 1 = Zumrad (yashil), 2 = Okean (ko'k)
// har biri [kunduzgi, tungi]
const List<List<_UiPal>> _uiPals = [
  [
    _UiPal(
      bg1: Color(0xFFF3F5F9), bg2: Color(0xFFF3F5F9),
      card: Color(0xFFFFFFFF), cardBorder: Color(0xFFDCE2EC),
      text: Color(0xFF0F172A), subtext: Color(0xFF64708A),
      accent: Color(0xFFF59E0B),
      navTop: Color(0xFF0F172A), navBottom: Color(0xFF0F172A),
      navText: Color(0xFFF1F5F9), navIcon: Color(0xFF94A3B8),
    ),
    _UiPal(
      bg1: Color(0xFF0B1220), bg2: Color(0xFF0B1220),
      card: Color(0xFF141D30), cardBorder: Color(0xFF25314A),
      text: Color(0xFFF1F5F9), subtext: Color(0xFF94A3B8),
      accent: Color(0xFFF59E0B),
      navTop: Color(0xFF0A101D), navBottom: Color(0xFF0A101D),
      navText: Color(0xFFF1F5F9), navIcon: Color(0xFF94A3B8),
    ),
  ],
  [
    _UiPal(
      bg1: Color(0xFFF1F1EC), bg2: Color(0xFFF1F1EC),
      card: Color(0xFFFFFFFF), cardBorder: Color(0xFFDEDDD5),
      text: Color(0xFF262421), subtext: Color(0xFF77756E),
      accent: Color(0xFF5E9A33),
      navTop: Color(0xFF2B2926), navBottom: Color(0xFF2B2926),
      navText: Color(0xFFF3F3EF), navIcon: Color(0xFFA9A7A1),
    ),
    _UiPal(
      bg1: Color(0xFF262421), bg2: Color(0xFF262421),
      card: Color(0xFF302E2B), cardBorder: Color(0xFF403D39),
      text: Color(0xFFF3F3EF), subtext: Color(0xFFA3A19B),
      accent: Color(0xFF81B64C),
      navTop: Color(0xFF1F1E1B), navBottom: Color(0xFF1F1E1B),
      navText: Color(0xFFF3F3EF), navIcon: Color(0xFFA3A19B),
    ),
  ],
  [
    _UiPal(
      bg1: Color(0xFFF6F7F9), bg2: Color(0xFFF6F7F9),
      card: Color(0xFFFFFFFF), cardBorder: Color(0xFFDCE0E6),
      text: Color(0xFF23272D), subtext: Color(0xFF6E7681),
      accent: Color(0xFF2F80D8),
      navTop: Color(0xFF1E2329), navBottom: Color(0xFF1E2329),
      navText: Color(0xFFEEF1F5), navIcon: Color(0xFF9CA5B1),
    ),
    _UiPal(
      bg1: Color(0xFF161A1F), bg2: Color(0xFF161A1F),
      card: Color(0xFF20262D), cardBorder: Color(0xFF2F3741),
      text: Color(0xFFE4E8ED), subtext: Color(0xFF8F9AA6),
      accent: Color(0xFF4DA3F5),
      navTop: Color(0xFF111418), navBottom: Color(0xFF111418),
      navText: Color(0xFFE4E8ED), navIcon: Color(0xFF8F9AA6),
    ),
  ],
];

const List<List<Pal>> _pals = [
  // 0: klassik yog'och
  [
    Pal(
      bg1: Color(0xFFF8EEDC), bg2: Color(0xFFEBD7B2),
      card: Color(0xFFFFF9EC), cardBorder: Color(0xFFE3CFA6),
      text: Color(0xFF3B2A1A), subtext: Color(0xFF7A634A),
      accent: Color(0xFFE2B455),
      navTop: Color(0xFF3A2416), navBottom: Color(0xFF22140B),
      navText: Color(0xFFEBDDBB), navIcon: Color(0xFFD9C7A0),
      boardLight: Color(0xFFF0D9B5), boardDark: Color(0xFFB58863),
      frameA: Color(0xFF7A4B2A), frameB: Color(0xFF4B2C17),
      frameLine: Color(0xFF3A2312), frameText: Color(0xFFE9D3A8),
      avatarWhite: Color(0xFFD9C7A0), avatarBlack: Color(0xFF3A2A20),
    ),
    Pal(
      bg1: Color(0xFF1B130E), bg2: Color(0xFF2C2018),
      card: Color(0xFF2B2018), cardBorder: Color(0xFF45331F),
      text: Color(0xFFF3E6CF), subtext: Color(0xFFB9A688),
      accent: Color(0xFFE2B455),
      navTop: Color(0xFF3A2416), navBottom: Color(0xFF22140B),
      navText: Color(0xFFEBDDBB), navIcon: Color(0xFFD9C7A0),
      boardLight: Color(0xFFF0D9B5), boardDark: Color(0xFFB58863),
      frameA: Color(0xFF7A4B2A), frameB: Color(0xFF4B2C17),
      frameLine: Color(0xFF3A2312), frameText: Color(0xFFE9D3A8),
      avatarWhite: Color(0xFFD9C7A0), avatarBlack: Color(0xFF3A2A20),
    ),
  ],
  // 1: marmar va oltin
  [
    Pal(
      bg1: Color(0xFFF4F3EE), bg2: Color(0xFFE2E0D6),
      card: Color(0xFFFFFFFF), cardBorder: Color(0xFFD9D6C9),
      text: Color(0xFF2A2F2B), subtext: Color(0xFF6B746C),
      accent: Color(0xFFC9A24B),
      navTop: Color(0xFF24332C), navBottom: Color(0xFF121B16),
      navText: Color(0xFFE8E4D2), navIcon: Color(0xFFB8C4B4),
      boardLight: Color(0xFFECEAE4), boardDark: Color(0xFF4F6D5C),
      frameA: Color(0xFF2A3A32), frameB: Color(0xFF16201B),
      frameLine: Color(0xFFC9A24B), frameText: Color(0xFFD6AE55),
      avatarWhite: Color(0xFFE8E4D2), avatarBlack: Color(0xFF24302A),
    ),
    Pal(
      bg1: Color(0xFF1D2924), bg2: Color(0xFF0F1512),
      card: Color(0xFF22302A), cardBorder: Color(0xFF3C5247),
      text: Color(0xFFEFE8D5), subtext: Color(0xFFA7B4A6),
      accent: Color(0xFFD6AE55),
      navTop: Color(0xFF24332C), navBottom: Color(0xFF121B16),
      navText: Color(0xFFE8E4D2), navIcon: Color(0xFFB8C4B4),
      boardLight: Color(0xFFECEAE4), boardDark: Color(0xFF4F6D5C),
      frameA: Color(0xFF2A3A32), frameB: Color(0xFF16201B),
      frameLine: Color(0xFFC9A24B), frameText: Color(0xFFD6AE55),
      avatarWhite: Color(0xFFE8E4D2), avatarBlack: Color(0xFF24302A),
    ),
  ],
  // 2: zamonaviy
  [
    Pal(
      bg1: Color(0xFFEEF2F6), bg2: Color(0xFFD9E1E9),
      card: Color(0xFFFFFFFF), cardBorder: Color(0xFFCBD6E0),
      text: Color(0xFF1C2733), subtext: Color(0xFF5E7388),
      accent: Color(0xFF3E8EDE),
      navTop: Color(0xFF1F3144), navBottom: Color(0xFF111B26),
      navText: Color(0xFFE8EEF4), navIcon: Color(0xFF9FB4C8),
      boardLight: Color(0xFFE2E8F0), boardDark: Color(0xFF475569),
      frameA: Color(0xFF1E293B), frameB: Color(0xFF0F172A),
      frameLine: Color(0xFF2E4155), frameText: Color(0xFF8AA0B6),
      avatarWhite: Color(0xFFD9E1E9), avatarBlack: Color(0xFF1F3144),
    ),
    Pal(
      bg1: Color(0xFF111B26), bg2: Color(0xFF0B121A),
      card: Color(0xFF1B2735), cardBorder: Color(0xFF2E4155),
      text: Color(0xFFE8EEF4), subtext: Color(0xFF8AA0B6),
      accent: Color(0xFF5AB0FF),
      navTop: Color(0xFF1F3144), navBottom: Color(0xFF111B26),
      navText: Color(0xFFE8EEF4), navIcon: Color(0xFF9FB4C8),
      boardLight: Color(0xFFE2E8F0), boardDark: Color(0xFF475569),
      frameA: Color(0xFF1E293B), frameB: Color(0xFF0F172A),
      frameLine: Color(0xFF2E4155), frameText: Color(0xFF8AA0B6),
      avatarWhite: Color(0xFFD9E1E9), avatarBlack: Color(0xFF1F3144),
    ),
  ],
];

// A-CHESS logotipi
const String _logoSvg = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs>
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4A2F1B"/><stop offset="1" stop-color="#1E1209"/></linearGradient>
<linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FBE6A6"/><stop offset="0.55" stop-color="#E2B455"/><stop offset="1" stop-color="#B8862B"/></linearGradient>
</defs><circle cx="50" cy="50" r="48" fill="url(#bg)"/>
<circle cx="50" cy="50" r="45" fill="none" stroke="url(#gold)" stroke-width="2.6"/>
<path fill-rule="evenodd" fill="url(#gold)" d="M44.6 16 H55.4 L77.5 77 H65 L61 66 H39 L35 77 H22.5 Z M42.6 54.6 H57.4 L50 33.4 Z"/>
<rect x="27" y="82.4" width="46" height="4.6" rx="2.3" fill="url(#gold)"/></svg>''';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) =>
      SvgPicture.string(_logoSvg, width: size, height: size);
}

/// Foydalanuvchi avatari: rasm bo'lsa rasm, bo'lmasa bosh harflar.
class AvatarView extends StatelessWidget {
  const AvatarView({
    super.key,
    required this.size,
    required this.initials,
    required this.pal,
    this.bytes,
  });
  final double size;
  final String initials;
  final Pal pal;
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: pal.accentSoft,
        border: Border.all(color: pal.accent, width: size > 60 ? 2.4 : 1.5),
      ),
      child: ClipOval(
        child: bytes != null
            ? Image.memory(
                bytes!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            : Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: size * 0.38,
                    fontWeight: FontWeight.w800,
                    color: pal.accent,
                  ),
                ),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Donalar (SVG, o'zim chizganman)
// ---------------------------------------------------------------------------

enum PieceKind { king, queen, rook, bishop, knight, pawn }

PieceKind kindOf(ch.PieceType t) {
  if (t == ch.PieceType.KING) return PieceKind.king;
  if (t == ch.PieceType.QUEEN) return PieceKind.queen;
  if (t == ch.PieceType.ROOK) return PieceKind.rook;
  if (t == ch.PieceType.BISHOP) return PieceKind.bishop;
  if (t == ch.PieceType.KNIGHT) return PieceKind.knight;
  return PieceKind.pawn;
}

int pieceValue(PieceKind k) {
  switch (k) {
    case PieceKind.king:
      return 0;
    case PieceKind.queen:
      return 9;
    case PieceKind.rook:
      return 5;
    case PieceKind.bishop:
      return 3;
    case PieceKind.knight:
      return 3;
    case PieceKind.pawn:
      return 1;
  }
}

const Map<PieceKind, String> _stauntonShapes = {
  PieceKind.king: r'''<rect x="46.6" y="3.6" width="6.8" height="26" rx="1.8" {O}/><rect x="40.6" y="9.4" width="18.8" height="6.8" rx="1.8" {O}/><path d="M26.6 40 C26.6 29 36 23.6 44.4 29.6 L50 33.4 L55.6 29.6 C64 23.6 73.4 29 73.4 40 C73.4 49 70.4 55 68 60 C66.6 65 67.6 70 70 76 H30 C32.4 70 33.4 65 32 60 C29.6 55 26.6 49 26.6 40 Z" {O}/><rect x="36.4" y="54" width="27.2" height="6" rx="3" {O}/><rect x="23" y="80" width="54" height="10.4" rx="4.4" {O}/><rect x="30" y="73" width="40" height="9" rx="3.6" {O}/><rect x="46.6" y="3.6" width="6.8" height="26" rx="1.8" {N}/><rect x="40.6" y="9.4" width="18.8" height="6.8" rx="1.8" {N}/><path d="M26.6 40 C26.6 29 36 23.6 44.4 29.6 L50 33.4 L55.6 29.6 C64 23.6 73.4 29 73.4 40 C73.4 49 70.4 55 68 60 C66.6 65 67.6 70 70 76 H30 C32.4 70 33.4 65 32 60 C29.6 55 26.6 49 26.6 40 Z" {N}/><rect x="36.4" y="54" width="27.2" height="6" rx="3" {N}/><rect x="23" y="80" width="54" height="10.4" rx="4.4" {N}/><rect x="30" y="73" width="40" height="9" rx="3.6" {N}/><path d="M31.6 40 C31.6 32 38 29.6 44 35.4 L46.4 38" {G}/><path d="M68.4 40 C68.4 32 62 29.6 56 35.4 L53.6 38" {G}/><path d="M43 62 C43 67 41.4 70 38.4 73" {H}/><path d="M31 84.2 H69" {G}/><path d="M31 87.4 H69" {G}/>''',
  PieceKind.queen: r'''<circle cx="24" cy="26" r="4.6" {O}/><circle cx="37" cy="19" r="4.6" {O}/><circle cx="50" cy="16" r="4.6" {O}/><circle cx="63" cy="19" r="4.6" {O}/><circle cx="76" cy="26" r="4.6" {O}/><path d="M24 26 L30.4 46 L37 19 L43.6 42 L50 16 L56.4 42 L63 19 L69.6 46 L76 26 L70.6 58 C68.6 64 68.6 70 71 76 H29 C31.4 70 31.4 64 29.4 58 Z" {O}/><rect x="35.4" y="52" width="29.2" height="6" rx="3" {O}/><rect x="23" y="80" width="54" height="10.4" rx="4.4" {O}/><rect x="30" y="73" width="40" height="9" rx="3.6" {O}/><circle cx="24" cy="26" r="4.6" {N}/><circle cx="37" cy="19" r="4.6" {N}/><circle cx="50" cy="16" r="4.6" {N}/><circle cx="63" cy="19" r="4.6" {N}/><circle cx="76" cy="26" r="4.6" {N}/><path d="M24 26 L30.4 46 L37 19 L43.6 42 L50 16 L56.4 42 L63 19 L69.6 46 L76 26 L70.6 58 C68.6 64 68.6 70 71 76 H29 C31.4 70 31.4 64 29.4 58 Z" {N}/><rect x="35.4" y="52" width="29.2" height="6" rx="3" {N}/><rect x="23" y="80" width="54" height="10.4" rx="4.4" {N}/><rect x="30" y="73" width="40" height="9" rx="3.6" {N}/><path d="M32.4 49 H67.6" {G}/><path d="M43.4 60 C43.4 66 41.6 70 38.4 73" {H}/><path d="M31 84.2 H69" {G}/><path d="M31 87.4 H69" {G}/>''',
  PieceKind.rook: r'''<path d="M31 12 H42.6 V20.4 H46.2 V12 H53.8 V20.4 H57.4 V12 H69 V35 L63.6 40 H36.4 L31 35 Z" {O}/><path d="M37.4 38 H62.6 C62.6 52 63.6 62 70.6 76 H29.4 C36.4 62 37.4 52 37.4 38 Z" {O}/><rect x="23" y="80" width="54" height="10.4" rx="4.4" {O}/><rect x="30" y="73" width="40" height="9" rx="3.6" {O}/><path d="M31 12 H42.6 V20.4 H46.2 V12 H53.8 V20.4 H57.4 V12 H69 V35 L63.6 40 H36.4 L31 35 Z" {N}/><path d="M37.4 38 H62.6 C62.6 52 63.6 62 70.6 76 H29.4 C36.4 62 37.4 52 37.4 38 Z" {N}/><rect x="23" y="80" width="54" height="10.4" rx="4.4" {N}/><rect x="30" y="73" width="40" height="9" rx="3.6" {N}/><path d="M31.4 33 H68.6" {G}/><path d="M36 17 V28" {H}/><path d="M42.4 46 C42.4 56 40.6 65 36.4 71" {H}/><path d="M31 84.2 H69" {G}/><path d="M31 87.4 H69" {G}/>''',
  PieceKind.bishop: r'''<path d="M50 9 C60.6 20 67 31 63 43 C62 46 60.4 48 60.4 51 C60.4 62 63 69 70 76 H30 C37 69 39.6 62 39.6 51 C39.6 48 38 46 37 43 C33 31 39.4 20 50 9 Z" {O}/><rect x="36.6" y="44.6" width="26.8" height="6" rx="3" {O}/><rect x="23" y="80" width="54" height="10.4" rx="4.4" {O}/><rect x="30" y="73" width="40" height="9" rx="3.6" {O}/><path d="M50 9 C60.6 20 67 31 63 43 C62 46 60.4 48 60.4 51 C60.4 62 63 69 70 76 H30 C37 69 39.6 62 39.6 51 C39.6 48 38 46 37 43 C33 31 39.4 20 50 9 Z" {N}/><rect x="36.6" y="44.6" width="26.8" height="6" rx="3" {N}/><rect x="23" y="80" width="54" height="10.4" rx="4.4" {N}/><rect x="30" y="73" width="40" height="9" rx="3.6" {N}/><path d="M52.6 20 C46 27 42.6 34 41.6 40" stroke="{D}" stroke-width="3.4" stroke-linecap="round" fill="none"/><path d="M44 54 C44 61 42 67 38 72" {H}/><path d="M31 84.2 H69" {G}/><path d="M31 87.4 H69" {G}/>''',
  PieceKind.knight: r'''<path d="M28.6 76 C28.6 66 31.6 58.6 38 53 C41 50.4 40.2 48.6 36.6 49 C32.6 49.4 28.6 50.8 25.4 50.2 C21.4 49.4 19.4 45.4 20.8 41.6 C22.2 38.2 25.6 36.6 28.4 33.4 C31.6 29.6 33 24.4 34 18.4 L34.6 10 L41.6 15.4 C44.4 14 48 13.4 51.4 13.8 C65.4 16.4 74.4 32.4 75 52 C75.4 62 73.4 69 72.6 76 Z" {O}/><rect x="23" y="80" width="54" height="10.4" rx="4.4" {O}/><rect x="30" y="73" width="40" height="9" rx="3.6" {O}/><path d="M28.6 76 C28.6 66 31.6 58.6 38 53 C41 50.4 40.2 48.6 36.6 49 C32.6 49.4 28.6 50.8 25.4 50.2 C21.4 49.4 19.4 45.4 20.8 41.6 C22.2 38.2 25.6 36.6 28.4 33.4 C31.6 29.6 33 24.4 34 18.4 L34.6 10 L41.6 15.4 C44.4 14 48 13.4 51.4 13.8 C65.4 16.4 74.4 32.4 75 52 C75.4 62 73.4 69 72.6 76 Z" {N}/><rect x="23" y="80" width="54" height="10.4" rx="4.4" {N}/><rect x="30" y="73" width="40" height="9" rx="3.6" {N}/><path d="M52 18.6 C62.6 24.6 67.6 37 66.6 56" stroke="{D}" stroke-width="2.6" stroke-linecap="round" fill="none"/><path d="M46.6 21.6 C55.6 27.6 60 38 59 54" stroke="{D}" stroke-width="2" stroke-linecap="round" fill="none"/><path d="M25.4 50 C29 50.6 32.8 49.4 35.4 47" stroke="{D}" stroke-width="1.8" stroke-linecap="round" fill="none"/><circle cx="36" cy="30" r="2.4" fill="{E}"/><circle cx="23.4" cy="42.4" r="1.5" fill="{E}"/><path d="M27.4 38 C30.4 33 32 28 32.8 22.6" {H}/><path d="M31 84.2 H69" {G}/><path d="M31 87.4 H69" {G}/>''',
  PieceKind.pawn: r'''<circle cx="50" cy="27" r="12.4" {O}/><rect x="36" y="37" width="28" height="6" rx="3" {O}/><path d="M40.5 42 H59.5 C59.5 54 61 64 69 76 H31 C39 64 40.5 54 40.5 42 Z" {O}/><rect x="23" y="80" width="54" height="10.4" rx="4.4" {O}/><rect x="30" y="73" width="40" height="9" rx="3.6" {O}/><circle cx="50" cy="27" r="12.4" {N}/><rect x="36" y="37" width="28" height="6" rx="3" {N}/><path d="M40.5 42 H59.5 C59.5 54 61 64 69 76 H31 C39 64 40.5 54 40.5 42 Z" {N}/><rect x="23" y="80" width="54" height="10.4" rx="4.4" {N}/><rect x="30" y="73" width="40" height="9" rx="3.6" {N}/><path d="M43 20 C44.6 18.2 46.8 17.4 49 17.4" {H}/><path d="M44 50 C44 58 42 65 37.6 71" {H}/><path d="M31 84.2 H69" {G}/><path d="M31 87.4 H69" {G}/>''',
};

const Map<PieceKind, String> _modernShapes = {
  PieceKind.king: r'''
  <rect x="46.4" y="4" width="7.2" height="22" rx="1.5" {F}/>
  <rect x="39.5" y="11" width="21" height="7.2" rx="1.5" {F}/>
  <path d="M29 45 C26 33 36 26 50 26 C64 26 74 33 71 45 Z" {F}/>
  <path d="M36 45 H64 L68 70 H32 Z" {F}/>
  <rect x="28" y="70" width="44" height="8" rx="2" {F}/>
  <rect x="24" y="78" width="52" height="10" rx="3" {F}/>
''',
  PieceKind.queen: r'''
  <circle cx="22" cy="20" r="4" {F}/>
  <circle cx="36" cy="13" r="4" {F}/>
  <circle cx="50" cy="10" r="4" {F}/>
  <circle cx="64" cy="13" r="4" {F}/>
  <circle cx="78" cy="20" r="4" {F}/>
  <path d="M25 26 L33 19 L37 25 L45 17 L50 24 L55 17 L63 25 L67 19 L75 26 L70 45 H30 Z" {F}/>
  <path d="M36 45 H64 L68 70 H32 Z" {F}/>
  <rect x="28" y="70" width="44" height="8" rx="2" {F}/>
  <rect x="24" y="78" width="52" height="10" rx="3" {F}/>
''',
  PieceKind.rook: r'''
  <path d="M29 16 H39.5 V25 H44.5 V16 H55.5 V25 H60.5 V16 H71 V36 H29 Z" {F}/>
  <path d="M34 36 H66 L63 44 H37 Z" {F}/>
  <path d="M37 44 H63 L67 70 H33 Z" {F}/>
  <rect x="28" y="70" width="44" height="8" rx="2" {F}/>
  <rect x="24" y="78" width="52" height="10" rx="3" {F}/>
''',
  PieceKind.bishop: r'''
  <circle cx="50" cy="13" r="4.5" {F}/>
  <path d="M50 18 C63 28 66 41 58 48 H42 C34 41 37 28 50 18 Z" {F}/>
  <path d="M54 27 L46 39" stroke="{D}" stroke-width="3.6" stroke-linecap="round" fill="none"/>
  <rect x="36" y="47" width="28" height="7" rx="2" {F}/>
  <path d="M41 54 H59 L64 71 H36 Z" {F}/>
  <rect x="28" y="70" width="44" height="8" rx="2" {F}/>
  <rect x="24" y="78" width="52" height="10" rx="3" {F}/>
''',
  PieceKind.knight: r'''
  <path d="M30 71 C30 60 34 53 42 47 L24 49 L19 40 L34 22 L36 11 L46 18 C66 18 76 38 74 71 Z" {F}/>
  <circle cx="38" cy="33" r="2.6" fill="{E}"/>
  <path d="M50 26 C60 32 64 44 63 62" stroke="{D}" stroke-width="3" stroke-linecap="round" fill="none"/>
  <rect x="28" y="70" width="44" height="8" rx="2" {F}/>
  <rect x="24" y="78" width="52" height="10" rx="3" {F}/>
''',
  PieceKind.pawn: r'''
  <circle cx="50" cy="28" r="12" {F}/>
  <path d="M41 41 H59 L63.5 71 H36.5 Z" {F}/>
  <rect x="30" y="70" width="40" height="8" rx="2" {F}/>
  <rect x="24" y="78" width="52" height="10" rx="3" {F}/>
''',
};


/// Dona to'plami: 0 = klassik (yangi turnir shakllari), 1 = eski (doska uslubiga
/// bog'liq). Sozlamalar o'zgarganda [applyPieceSet] orqali yangilanadi.
int pieceSetPref = 0;
void applyPieceSet(int v) => pieceSetPref = v;

const Map<PieceKind, String> _fideShapes = {
  PieceKind.king: r'''<circle cx="50" cy="15" r="4.4" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><rect x="47.8" y="17" width="4.4" height="8" rx="2" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><circle cx="50" cy="32" r="7" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><circle cx="36" cy="34" r="6.4" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><circle cx="45" cy="28" r="6.4" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><circle cx="55" cy="28" r="6.4" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><circle cx="64" cy="34" r="6.4" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><path d="M31 34 H69 L66 46 H34 Z" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><rect x="37.5" y="44" width="25.0" height="5.4" rx="2.7" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><path d="M44 47 H56 C56 61 59.6 63 64 72 H36 C40.4 63 44 61 44 47 Z" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><rect x="30" y="71" width="40" height="8" rx="3.6" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><rect x="26" y="77" width="48" height="10.4" rx="4.4" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><circle cx="50" cy="15" r="4.4" fill="@FILL@"/><rect x="47.8" y="17" width="4.4" height="8" rx="2" fill="@FILL@"/><circle cx="50" cy="32" r="7" fill="@FILL@"/><circle cx="36" cy="34" r="6.4" fill="@FILL@"/><circle cx="45" cy="28" r="6.4" fill="@FILL@"/><circle cx="55" cy="28" r="6.4" fill="@FILL@"/><circle cx="64" cy="34" r="6.4" fill="@FILL@"/><path d="M31 34 H69 L66 46 H34 Z" fill="@FILL@"/><rect x="37.5" y="44" width="25.0" height="5.4" rx="2.7" fill="@FILL@"/><path d="M44 47 H56 C56 61 59.6 63 64 72 H36 C40.4 63 44 61 44 47 Z" fill="@FILL@"/><rect x="30" y="71" width="40" height="8" rx="3.6" fill="@FILL@"/><rect x="26" y="77" width="48" height="10.4" rx="4.4" fill="@FILL@"/><g clip-path="url(#r)" opacity="@OP@"><circle cx="50" cy="15" r="4.4" fill="@SHADE@"/><rect x="47.8" y="17" width="4.4" height="8" rx="2" fill="@SHADE@"/><circle cx="50" cy="32" r="7" fill="@SHADE@"/><circle cx="36" cy="34" r="6.4" fill="@SHADE@"/><circle cx="45" cy="28" r="6.4" fill="@SHADE@"/><circle cx="55" cy="28" r="6.4" fill="@SHADE@"/><circle cx="64" cy="34" r="6.4" fill="@SHADE@"/><path d="M31 34 H69 L66 46 H34 Z" fill="@SHADE@"/><rect x="37.5" y="44" width="25.0" height="5.4" rx="2.7" fill="@SHADE@"/><path d="M44 47 H56 C56 61 59.6 63 64 72 H36 C40.4 63 44 61 44 47 Z" fill="@SHADE@"/><rect x="30" y="71" width="40" height="8" rx="3.6" fill="@SHADE@"/><rect x="26" y="77" width="48" height="10.4" rx="4.4" fill="@SHADE@"/></g><path d="M36 40 H64" stroke="@D@" stroke-width="1.6" stroke-linecap="round"/>''',
  PieceKind.queen: r'''<g transform="translate(0,-9)"><circle cx="28.55" cy="32.00" r="3.3"  fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><circle cx="38.17" cy="24.62" r="3.3"  fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><circle cx="50.00" cy="22.00" r="3.3"  fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><circle cx="61.83" cy="24.62" r="3.3"  fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><circle cx="71.45" cy="32.00" r="3.3"  fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><path d="M34.53 43.55 L30.08 33.29 L40.96 35.89 Z"  fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><path d="M38.71 37.61 L39.01 26.44 L47.77 33.39 Z"  fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><path d="M45.00 34.00 L50.00 24.00 L55.00 34.00 Z"  fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><path d="M52.23 33.39 L60.99 26.44 L61.29 37.61 Z"  fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><path d="M59.04 35.89 L69.92 33.29 L65.47 43.55 Z"  fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><path d="M43 56 L57 56 L64 46 L64.6 37.8 L61.6 34.9 L58.0 32.8 L54.1 31.5 L50.0 31.0 L45.9 31.5 L42.0 32.8 L38.4 34.9 L35.4 37.8 L36 46 Z" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/></g><path d="M43 45 L57 45 C58 57 62 66 66 73 H34 C38 66 42 57 43 45 Z" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><rect x="30" y="71" width="40" height="8" rx="3.6" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><rect x="26" y="77" width="48" height="10.4" rx="4.4" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><g transform="translate(0,-9)"><circle cx="28.55" cy="32.00" r="3.3"  fill="@FILL@"/><circle cx="38.17" cy="24.62" r="3.3"  fill="@FILL@"/><circle cx="50.00" cy="22.00" r="3.3"  fill="@FILL@"/><circle cx="61.83" cy="24.62" r="3.3"  fill="@FILL@"/><circle cx="71.45" cy="32.00" r="3.3"  fill="@FILL@"/><path d="M34.53 43.55 L30.08 33.29 L40.96 35.89 Z"  fill="@FILL@"/><path d="M38.71 37.61 L39.01 26.44 L47.77 33.39 Z"  fill="@FILL@"/><path d="M45.00 34.00 L50.00 24.00 L55.00 34.00 Z"  fill="@FILL@"/><path d="M52.23 33.39 L60.99 26.44 L61.29 37.61 Z"  fill="@FILL@"/><path d="M59.04 35.89 L69.92 33.29 L65.47 43.55 Z"  fill="@FILL@"/><path d="M43 56 L57 56 L64 46 L64.6 37.8 L61.6 34.9 L58.0 32.8 L54.1 31.5 L50.0 31.0 L45.9 31.5 L42.0 32.8 L38.4 34.9 L35.4 37.8 L36 46 Z" fill="@FILL@"/></g><path d="M43 45 L57 45 C58 57 62 66 66 73 H34 C38 66 42 57 43 45 Z" fill="@FILL@"/><rect x="30" y="71" width="40" height="8" rx="3.6" fill="@FILL@"/><rect x="26" y="77" width="48" height="10.4" rx="4.4" fill="@FILL@"/><g clip-path="url(#r)" opacity="@OP@"><g transform="translate(0,-9)"><circle cx="28.55" cy="32.00" r="3.3"  fill="@SHADE@"/><circle cx="38.17" cy="24.62" r="3.3"  fill="@SHADE@"/><circle cx="50.00" cy="22.00" r="3.3"  fill="@SHADE@"/><circle cx="61.83" cy="24.62" r="3.3"  fill="@SHADE@"/><circle cx="71.45" cy="32.00" r="3.3"  fill="@SHADE@"/><path d="M34.53 43.55 L30.08 33.29 L40.96 35.89 Z"  fill="@SHADE@"/><path d="M38.71 37.61 L39.01 26.44 L47.77 33.39 Z"  fill="@SHADE@"/><path d="M45.00 34.00 L50.00 24.00 L55.00 34.00 Z"  fill="@SHADE@"/><path d="M52.23 33.39 L60.99 26.44 L61.29 37.61 Z"  fill="@SHADE@"/><path d="M59.04 35.89 L69.92 33.29 L65.47 43.55 Z"  fill="@SHADE@"/><path d="M43 56 L57 56 L64 46 L64.6 37.8 L61.6 34.9 L58.0 32.8 L54.1 31.5 L50.0 31.0 L45.9 31.5 L42.0 32.8 L38.4 34.9 L35.4 37.8 L36 46 Z" fill="@SHADE@"/></g><path d="M43 45 L57 45 C58 57 62 66 66 73 H34 C38 66 42 57 43 45 Z" fill="@SHADE@"/><rect x="30" y="71" width="40" height="8" rx="3.6" fill="@SHADE@"/><rect x="26" y="77" width="48" height="10.4" rx="4.4" fill="@SHADE@"/></g><path d="M44.4 46 H55.6" stroke="@D@" stroke-width="1.6" stroke-linecap="round"/>''',
  PieceKind.rook: r'''<path d="M32 14 H42 V20 H46.4 V14 H53.6 V20 H58 V14 H68 V31 H32 Z" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><rect x="35" y="29" width="30" height="8" rx="3" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><path d="M41 36 H59 C59 50 62.6 63 67 72 H33 C37.4 63 41 50 41 36 Z" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><rect x="30" y="71" width="40" height="8" rx="3.6" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><rect x="26" y="77" width="48" height="10.4" rx="4.4" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><path d="M32 14 H42 V20 H46.4 V14 H53.6 V20 H58 V14 H68 V31 H32 Z" fill="@FILL@"/><rect x="35" y="29" width="30" height="8" rx="3" fill="@FILL@"/><path d="M41 36 H59 C59 50 62.6 63 67 72 H33 C37.4 63 41 50 41 36 Z" fill="@FILL@"/><rect x="30" y="71" width="40" height="8" rx="3.6" fill="@FILL@"/><rect x="26" y="77" width="48" height="10.4" rx="4.4" fill="@FILL@"/><g clip-path="url(#r)" opacity="@OP@"><path d="M32 14 H42 V20 H46.4 V14 H53.6 V20 H58 V14 H68 V31 H32 Z" fill="@SHADE@"/><rect x="35" y="29" width="30" height="8" rx="3" fill="@SHADE@"/><path d="M41 36 H59 C59 50 62.6 63 67 72 H33 C37.4 63 41 50 41 36 Z" fill="@SHADE@"/><rect x="30" y="71" width="40" height="8" rx="3.6" fill="@SHADE@"/><rect x="26" y="77" width="48" height="10.4" rx="4.4" fill="@SHADE@"/></g><path d="M33 25 H67" stroke="@D@" stroke-width="1.6" stroke-linecap="round"/>''',
  PieceKind.bishop: r'''<circle cx="50" cy="11" r="4.4" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><path d="M50 14 C58 21 66 27 62 38 C61 41 62 43 64 45 H36 C38 43 39 41 38 38 C34 27 42 21 50 14 Z" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><path d="M43 44 L57 44 C58 57 62 66 66 73 H34 C38 66 42 57 43 44 Z" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><rect x="30" y="71" width="40" height="8" rx="3.6" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><rect x="26" y="77" width="48" height="10.4" rx="4.4" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><circle cx="50" cy="11" r="4.4" fill="@FILL@"/><path d="M50 14 C58 21 66 27 62 38 C61 41 62 43 64 45 H36 C38 43 39 41 38 38 C34 27 42 21 50 14 Z" fill="@FILL@"/><path d="M43 44 L57 44 C58 57 62 66 66 73 H34 C38 66 42 57 43 44 Z" fill="@FILL@"/><rect x="30" y="71" width="40" height="8" rx="3.6" fill="@FILL@"/><rect x="26" y="77" width="48" height="10.4" rx="4.4" fill="@FILL@"/><g clip-path="url(#r)" opacity="@OP@"><circle cx="50" cy="11" r="4.4" fill="@SHADE@"/><path d="M50 14 C58 21 66 27 62 38 C61 41 62 43 64 45 H36 C38 43 39 41 38 38 C34 27 42 21 50 14 Z" fill="@SHADE@"/><path d="M43 44 L57 44 C58 57 62 66 66 73 H34 C38 66 42 57 43 44 Z" fill="@SHADE@"/><rect x="30" y="71" width="40" height="8" rx="3.6" fill="@SHADE@"/><rect x="26" y="77" width="48" height="10.4" rx="4.4" fill="@SHADE@"/></g><path d="M45 32 C48 30 52 30 55 32" stroke="@D@" stroke-width="2" fill="none" stroke-linecap="round"/><path d="M50 20 L50 28" stroke="@D@" stroke-width="2.4" stroke-linecap="round"/>''',
  PieceKind.knight: r'''<g transform="translate(50.8 86.4) scale(1.07 0.94) translate(-50.8 -86.4)"><path d="M28.6 86.4 L73 86.4 C73 80 71 74 70 66 C69 56 72.6 44 70.2 35 C68.8 27 64 22.6 60.6 20.4 L58.6 11.6 L55 17 L50 12 L49 20 C44 26 39 32 34.8 37.4 C33 39.4 31.6 41.8 31.4 44.6 C31.2 47.6 34.6 49.4 38.4 47.6 L45 44.4 C50 46.6 52 49 52 52 C52 53.6 49 54.6 44.6 56.6 C34 61.6 28.6 72 28.6 86.4 Z" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/></g><g transform="translate(50.8 86.4) scale(1.07 0.94) translate(-50.8 -86.4)"><path d="M28.6 86.4 L73 86.4 C73 80 71 74 70 66 C69 56 72.6 44 70.2 35 C68.8 27 64 22.6 60.6 20.4 L58.6 11.6 L55 17 L50 12 L49 20 C44 26 39 32 34.8 37.4 C33 39.4 31.6 41.8 31.4 44.6 C31.2 47.6 34.6 49.4 38.4 47.6 L45 44.4 C50 46.6 52 49 52 52 C52 53.6 49 54.6 44.6 56.6 C34 61.6 28.6 72 28.6 86.4 Z" fill="@FILL@"/></g><g clip-path="url(#r)" opacity="@OP@"><g transform="translate(50.8 86.4) scale(1.07 0.94) translate(-50.8 -86.4)"><path d="M28.6 86.4 L73 86.4 C73 80 71 74 70 66 C69 56 72.6 44 70.2 35 C68.8 27 64 22.6 60.6 20.4 L58.6 11.6 L55 17 L50 12 L49 20 C44 26 39 32 34.8 37.4 C33 39.4 31.6 41.8 31.4 44.6 C31.2 47.6 34.6 49.4 38.4 47.6 L45 44.4 C50 46.6 52 49 52 52 C52 53.6 49 54.6 44.6 56.6 C34 61.6 28.6 72 28.6 86.4 Z" fill="@SHADE@"/></g></g><g transform="translate(50.8 86.4) scale(1.07 0.94) translate(-50.8 -86.4)"><path d="M46 31.4 Q49.6 28.8 53.4 30.6 Q49.8 33 46 31.4 Z" fill="@E@"/><path d="M54.6 26.6 L45 29.6" stroke="@D@" stroke-width="1.9" stroke-linecap="round" fill="none"/><path d="M62 24 C66.4 30 66.4 40 65.4 50 C64.4 58 65.4 64 66.4 71" stroke="@D@" stroke-width="2" stroke-linecap="round" fill="none"/><path d="M33 43.6 l2.6 1.4" stroke="@D@" stroke-width="1.6" stroke-linecap="round"/><path d="M34.2 48.800000000000004 L39 46.2" stroke="@D@" stroke-width="1.5" stroke-linecap="round"/></g>''',
  PieceKind.pawn: r'''<circle cx="50" cy="27" r="11" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><rect x="36" y="35.4" width="28" height="5.4" rx="2.7" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><path d="M42 39.4 H58 C58 53.4 61.6 63 66 72 H34 C38.4 63 42 53.4 42 39.4 Z" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><rect x="30" y="71" width="40" height="8" rx="3.6" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><rect x="26" y="77" width="48" height="10.4" rx="4.4" fill="@EDGE@" stroke="@EDGE@" stroke-width="3.2" stroke-linejoin="round"/><circle cx="50" cy="27" r="11" fill="@FILL@"/><rect x="36" y="35.4" width="28" height="5.4" rx="2.7" fill="@FILL@"/><path d="M42 39.4 H58 C58 53.4 61.6 63 66 72 H34 C38.4 63 42 53.4 42 39.4 Z" fill="@FILL@"/><rect x="30" y="71" width="40" height="8" rx="3.6" fill="@FILL@"/><rect x="26" y="77" width="48" height="10.4" rx="4.4" fill="@FILL@"/><g clip-path="url(#r)" opacity="@OP@"><circle cx="50" cy="27" r="11" fill="@SHADE@"/><rect x="36" y="35.4" width="28" height="5.4" rx="2.7" fill="@SHADE@"/><path d="M42 39.4 H58 C58 53.4 61.6 63 66 72 H34 C38.4 63 42 53.4 42 39.4 Z" fill="@SHADE@"/><rect x="30" y="71" width="40" height="8" rx="3.6" fill="@SHADE@"/><rect x="26" y="77" width="48" height="10.4" rx="4.4" fill="@SHADE@"/></g>''',
};

String _buildFideSvg(PieceKind kind, bool white) {
  final shape = _fideShapes[kind]!;
  final String edge = white ? '#2E261C' : '#0B0908';
  final String fill = white ? '#F4ECDC' : '#3A3531';
  final String shade = white ? '#8F7B55' : '#000000';
  final String d = white ? '#8F7B55' : '#B3A99A';
  final String e = white ? '#2E261C' : '#F4ECDC';
  final String h = white ? '#FFFFFF' : '#9A9186';
  final String op = white ? '0.30' : '0.35';
  final body = shape
      .replaceAll('@EDGE@', edge)
      .replaceAll('@FILL@', fill)
      .replaceAll('@SHADE@', shade)
      .replaceAll('@D@', d)
      .replaceAll('@E@', e)
      .replaceAll('@H@', h)
      .replaceAll('@OP@', op);
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="4 4 92 92">'
      '<defs><clipPath id="r"><rect x="50" y="0" width="60" height="100"/>'
      '</clipPath></defs>'
      '<ellipse cx="50" cy="88.6" rx="26" ry="1.8" fill="#000" opacity="0.22"/>'
      '$body</svg>';
}


class _PiecePaint {
  const _PiecePaint({
    required this.colors,
    required this.offsets,
    required this.stroke,
    required this.strokeWidth,
    this.trim = '#000000',
    this.detail = '#000000',
    this.eye = '#000000',
    this.hi = '#FFFFFF',
    this.hiOpacity = 0.0,
  });

  final List<String> colors;
  final List<double> offsets;
  final String stroke;
  final double strokeWidth;
  final String trim;
  final String detail;
  final String eye;
  final String hi;
  final double hiOpacity;
}

// [uslub][0 = oq, 1 = qora]
const List<List<_PiecePaint>> _paints = [
  [
    _PiecePaint(
      colors: ['#FFF9EA', '#F1E1BC', '#D4BB8C', '#A98F5F'],
      offsets: [0.0, 0.28, 0.68, 1.0],
      stroke: '#3A2815', strokeWidth: 1.5,
      trim: '#8A6B3F', detail: '#8A6B3F', eye: '#2B1D12', hiOpacity: 0.55,
    ),
    _PiecePaint(
      colors: ['#8A705D', '#5A4332', '#2F2015', '#120B07'],
      offsets: [0.0, 0.28, 0.68, 1.0],
      stroke: '#0A0603', strokeWidth: 1.5,
      trim: '#A58A72', detail: '#B39B86', eye: '#EFE3D0', hiOpacity: 0.28,
    ),
  ],
  [
    _PiecePaint(
      colors: ['#FFFFFF', '#F4F3F0', '#DAD8D2', '#A9A69E'],
      offsets: [0.0, 0.28, 0.68, 1.0],
      stroke: '#5C5A55', strokeWidth: 1.3,
      trim: '#C9A24B', detail: '#A9A296', eye: '#3A3732', hiOpacity: 0.7,
    ),
    _PiecePaint(
      colors: ['#5A5F66', '#33373D', '#1A1C20', '#08090B'],
      offsets: [0.0, 0.28, 0.68, 1.0],
      stroke: '#000000', strokeWidth: 1.3,
      trim: '#D6AE55', detail: '#9AA0A8', eye: '#E9DDBC', hiOpacity: 0.30,
    ),
  ],
  [
    _PiecePaint(
      colors: ['#FFFFFF', '#FFFFFF', '#D9E1E9', '#D9E1E9'],
      offsets: [0.0, 0.52, 0.52, 1.0],
      stroke: '#1C2733', strokeWidth: 2.0,
      detail: '#9AA8B6', eye: '#1C2733',
    ),
    _PiecePaint(
      colors: ['#3B536B', '#3B536B', '#1F3144', '#1F3144'],
      offsets: [0.0, 0.52, 0.52, 1.0],
      stroke: '#0A1118', strokeWidth: 2.0,
      detail: '#8AA0B6', eye: '#E8EEF4',
    ),
  ],
];

int _coordSize = 1;
int _coordFont = 0;

/// Doska chetidagi harf va raqamlar: [size] 0..2, [font] 0..2.
void applyCoordStyle(int size, int font) {
  _coordSize = size.clamp(0, 2);
  _coordFont = font.clamp(0, 2);
}

/// Doska chetidagi yozuv uslubi ([base] = ramka qalinligi yoki shunga teng o'lcham).
TextStyle coordTextStyle(Color color, double base) {
  const factors = [0.36, 0.5, 0.64];
  String? family;
  List<String>? fallback;
  if (_coordFont == 1) {
    family = 'Georgia';
    fallback = const ['Times New Roman', 'serif'];
  } else if (_coordFont == 2) {
    family = 'Consolas';
    fallback = const ['Courier New', 'monospace'];
  }
  return TextStyle(
    fontSize: base * factors[_coordSize],
    fontWeight: FontWeight.w700,
    fontFamily: family,
    fontFamilyFallback: fallback,
    color: color,
  );
}

final Map<String, String> _svgCache = {};

String _svgFor(int style, PieceKind kind, bool white, [int? set]) {
  if ((set ?? pieceSetPref) == 0) {
    final fkey = 'f${kind.name}${white ? 'w' : 'b'}';
    return _svgCache.putIfAbsent(fkey, () {
      final svg = _buildFideSvg(kind, white);
      // Almashmay qolgan belgi bo'lsa, eski shaklga qaytamiz (bo'sh katak chiqmasin)
      if (svg.contains('@')) return _buildSvg(style, kind, white);
      return svg;
    });
  }
  final key = '$style${kind.name}${white ? 'w' : 'b'}';
  return _svgCache.putIfAbsent(key, () => _buildSvg(style, kind, white));
}

String _buildSvg(int style, PieceKind kind, bool white) {
  final s = (style < 0 || style > 2) ? 0 : style;
  final p = _paints[s][white ? 0 : 1];
  final shapes = (s == 2 ? _modernShapes : _stauntonShapes)[kind]!;

  final fill = 'fill="url(#g)" stroke="${p.stroke}" '
      'stroke-width="${p.strokeWidth}" stroke-linejoin="round"';
  final trim = 'fill="none" stroke="${p.trim}" stroke-width="1.1" '
      'stroke-linecap="round" opacity="0.9"';
  final outline = 'fill="${p.stroke}" stroke="${p.stroke}" '
      'stroke-width="${p.strokeWidth * 2}" stroke-linejoin="round"';
  const solid = 'fill="url(#g)"';
  final hi = 'fill="none" stroke="${p.hi}" stroke-width="2.2" '
      'stroke-linecap="round" opacity="${p.hiOpacity}"';

  final body = shapes
      .replaceAll('{O}', outline)
      .replaceAll('{N}', solid)
      .replaceAll('{F}', fill)
      .replaceAll('{G}', trim)
      .replaceAll('{H}', hi)
      .replaceAll('{D}', p.detail)
      .replaceAll('{E}', p.eye);

  final stops = StringBuffer();
  for (var i = 0; i < p.colors.length; i++) {
    stops.write(
        '<stop offset="${p.offsets[i]}" stop-color="${p.colors[i]}"/>');
  }

  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="5 2 90 90">'
      '<defs><linearGradient id="g" gradientUnits="userSpaceOnUse" '
      'x1="20" y1="0" x2="80" y2="0">$stops</linearGradient></defs>'
      '<ellipse cx="50" cy="91.2" rx="31" ry="3.2" fill="#000" opacity="0.30"/>'
      '$body</svg>';
}

/// Taxtadagi moddiy ustunlik (oq - qora), FEN bo'yicha.
int materialBalance(String fen) {
  const v = {'p': 1, 'n': 3, 'b': 3, 'r': 5, 'q': 9};
  var sum = 0;
  for (final c in fen.split(' ').first.split('')) {
    final x = v[c.toLowerCase()];
    if (x == null) continue;
    sum += c == c.toLowerCase() ? -x : x;
  }
  return sum;
}

/// Taxta yonidagi vertikal ustunlik chizig'i (oq pastda).
class EvalBar extends StatelessWidget {
  const EvalBar({
    super.key,
    required this.balance,
    required this.pal,
    this.whiteFrac,
    this.label,
  });
  final int balance;
  final Pal pal;
  final double? whiteFrac; // dvigatel bahosi bo'lsa
  final String? label;

  @override
  Widget build(BuildContext context) {
    final frac = whiteFrac ?? 1 / (1 + math.exp(-balance / 4.0));
    final txt = label ??
        (balance == 0 ? '0' : (balance > 0 ? '+$balance' : '$balance'));
    return Tooltip(
      message: txt,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LayoutBuilder(
          builder: (_, c) => Stack(
            children: [
              Container(color: const Color(0xFF111827)),
              Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: c.maxHeight * frac,
                  color: const Color(0xFFF1F5F9),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: c.maxHeight * 0.5 - 0.5,
                height: 1,
                child: ColoredBox(color: pal.accent.withAlpha(0xAA)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PieceView extends StatelessWidget {
  const PieceView({
    super.key,
    required this.kind,
    required this.white,
    required this.size,
    this.style = 0,
    this.pieceSet,
  });

  final PieceKind kind;
  final bool white;
  final double size;
  final int style;
  final int? pieceSet;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      _svgFor(style, kind, white, pieceSet),
      width: size,
      height: size,
    );
  }
}

// ---------------------------------------------------------------------------
// Yurish yozuvi
// ---------------------------------------------------------------------------

class MoveRecord {
  const MoveRecord({
    required this.san,
    required this.from,
    required this.to,
    required this.white,
    this.captured,
  });

  final String san;
  final String from;
  final String to;
  final bool white;
  final PieceKind? captured;
}

String formatClock(int seconds) {
  final m = (seconds ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

// ---------------------------------------------------------------------------
// Doska
// ---------------------------------------------------------------------------

/// Kataklarni chizadi: yog'och tolalari, marmar tomirlari yoki tekis rang.
class _SquarePainter extends CustomPainter {
  const _SquarePainter({
    required this.style,
    required this.light,
    required this.seed,
    required this.base,
  });

  final int style;
  final bool light;
  final int seed;
  final Color base;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (style == 2) {
      canvas.drawRect(rect, Paint()..color = base);
      return;
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(base, Colors.white, 0.06)!,
            Color.lerp(base, Colors.black, 0.07)!,
          ],
        ).createShader(rect),
    );

    final rnd = math.Random(seed * 7919 + (light ? 1 : 2));
    final w = size.width;
    final h = size.height;

    if (style == 0) {
      final grain = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, w * 0.012)
        ..color = light ? const Color(0x1F8A5A2B) : const Color(0x33281406);
      for (var i = 0; i < 6; i++) {
        final y = h * (0.08 + i * 0.16) + rnd.nextDouble() * h * 0.05;
        final path = Path()
          ..moveTo(0, y)
          ..cubicTo(
            w * 0.3,
            y + (rnd.nextDouble() - 0.5) * h * 0.08,
            w * 0.65,
            y + (rnd.nextDouble() - 0.5) * h * 0.08,
            w,
            y + (rnd.nextDouble() - 0.5) * h * 0.06,
          );
        canvas.drawPath(path, grain);
      }
    } else {
      final vein = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.7, w * 0.014)
        ..color = light ? const Color(0x2A6B6B6B) : const Color(0x33D9E6DC);
      for (var i = 0; i < 2; i++) {
        final x0 = rnd.nextDouble() * w;
        final path = Path()
          ..moveTo(x0, 0)
          ..cubicTo(
            x0 + (rnd.nextDouble() - 0.5) * w,
            h * 0.3,
            x0 + (rnd.nextDouble() - 0.5) * w,
            h * 0.65,
            rnd.nextDouble() * w,
            h,
          );
        canvas.drawPath(path, vein);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SquarePainter old) =>
      old.style != style ||
      old.light != light ||
      old.seed != seed ||
      old.base != base;
}

/// Doska: tanlash, yurish mumkin bo'lgan kataklar, oxirgi yurish,
/// shoh ostidagi ogohlantirish. Ko'rinishi [style] ga bog'liq.
class ChessBoard extends StatefulWidget {
  const ChessBoard({
    super.key,
    required this.game,
    required this.onMoved,
    required this.pal,
    required this.style,
    this.lastFrom,
    this.lastTo,
    this.enabled = true,
    this.flipped = false,
    this.premoveColor,
    this.premoveFrom,
    this.premoveTo,
    this.onPremove,
  });

  /// Premove: raqib yurayotganda keyingi yurishni oldindan belgilash.
  final ch.Color? premoveColor;
  final String? premoveFrom;
  final String? premoveTo;
  final void Function(String? from, String? to)? onPremove;

  final bool flipped;
  final ch.Chess game;
  final void Function(MoveRecord) onMoved;
  final Pal pal;
  final int style;
  final String? lastFrom;
  final String? lastTo;
  final bool enabled;

  @override
  State<ChessBoard> createState() => _ChessBoardState();
}

class _ChessBoardState extends State<ChessBoard> {
  static const String _files = 'abcdefgh';

  String? _selected;
  List<String> _targets = [];
  List<Map<String, dynamic>> _selMoves = [];

  String _square(int row, int col) => widget.flipped
      ? '${_files[7 - col]}${row + 1}'
      : '${_files[col]}${8 - row}';

  void _clear() {
    _selected = null;
    _targets = [];
    _selMoves = [];
    _dragFrom = null;
    _dragActive = false;
    _hoverSq = null;
  }

  // ---- Figurani ushlab sudrash (drag and drop) ----
  String? _dragFrom; // ushlab olingan figura turgan katak
  bool _dragActive = false; // sichqoncha/barmoq haqiqatan siljidi
  Offset _dragPos = Offset.zero; // doska ichidagi joriy nuqta
  Offset _dragStart = Offset.zero;
  String? _hoverSq;
  bool _wasSelected = false;

  String? _sqAt(Offset p, double cell) {
    if (cell <= 0) return null;
    final col = (p.dx / cell).floor();
    final row = (p.dy / cell).floor();
    if (col < 0 || col > 7 || row < 0 || row > 7) return null;
    return _square(row, col);
  }

  bool get _premoveMode =>
      !widget.enabled &&
      widget.premoveColor != null &&
      widget.onPremove != null &&
      widget.game.turn != widget.premoveColor;

  ch.Color get _ownColor =>
      _premoveMode ? widget.premoveColor! : widget.game.turn;

  List _movesFrom(String sq) {
    if (_premoveMode) {
      // Premove: navbat bizda bo'lganda mumkin bo'ladigan yurishlar (taxminiy)
      final parts = widget.game.fen.split(' ');
      if (parts.length < 4) return const [];
      parts[1] = widget.premoveColor == ch.Color.WHITE ? 'w' : 'b';
      parts[3] = '-';
      try {
        final g = ch.Chess.fromFEN(parts.join(' '));
        return g.moves({'verbose': true, 'square': sq}) as List;
      } catch (_) {
        return const [];
      }
    }
    return widget.game.moves({'verbose': true, 'square': sq}) as List;
  }

  void _select(String sq) {
    final moves = _movesFrom(sq);
    final list = [
      for (final m in moves) Map<String, dynamic>.from(m as Map),
    ];
    _selected = sq;
    _selMoves = list;
    _targets = [for (final m in list) m['to'] as String];
  }

  void _pDown(Offset p, double cell) {
    if (!widget.enabled && !_premoveMode) return;
    final sq = _sqAt(p, cell);
    if (sq == null) return;
    final game = widget.game;
    _wasSelected = _selected == sq;
    // Tanlangan figura bor va bu mumkin bo'lgan katak: oddiy bosib yurish.
    if (_selected != null && _targets.contains(sq)) {
      _onTap(sq);
      return;
    }
    final piece = game.get(sq);
    if (piece != null && piece.color == _ownColor) {
      setState(() {
        _select(sq);
        _dragFrom = sq;
        _dragActive = false;
        _dragStart = p;
        _dragPos = p;
        _hoverSq = sq;
      });
    } else {
      setState(_clear);
    }
  }

  void _pMove(Offset p, double cell) {
    if (_dragFrom == null) return;
    if (!_dragActive && (p - _dragStart).distance < 5) return;
    setState(() {
      _dragActive = true;
      _dragPos = p;
      _hoverSq = _sqAt(p, cell);
    });
  }

  void _pUp(Offset p, double cell) {
    final from = _dragFrom;
    if (from == null) return;
    if (_dragActive) {
      final target = _sqAt(p, cell);
      if (target != null && _targets.contains(target)) {
        _doMove(from, target);
        return;
      }
      setState(() {
        _dragActive = false;
        _dragFrom = null;
        _hoverSq = null;
        if (target != from) {
          _selected = null;
          _targets = [];
          _selMoves = [];
        }
      });
    } else {
      setState(() {
        _dragFrom = null;
        _hoverSq = null;
        if (_wasSelected) {
          _selected = null;
          _targets = [];
          _selMoves = [];
        }
      });
    }
  }

  void _pCancel() {
    if (_dragFrom == null) return;
    setState(() {
      _dragActive = false;
      _dragFrom = null;
      _hoverSq = null;
    });
  }

  void _onTap(String sq) {
    if (!widget.enabled && !_premoveMode) return;
    final game = widget.game;
    final from = _selected;

    if (from != null && _targets.contains(sq)) {
      _doMove(from, sq);
      return;
    }

    final piece = game.get(sq);
    if (piece != null && piece.color == _ownColor) {
      setState(() => _select(sq));
    } else {
      setState(_clear);
    }
  }

  void _doMove(String from, String sq) {
    final game = widget.game;
    if (_premoveMode) {
      setState(_clear);
      widget.onPremove!(from, sq);
      return;
    }
    {
      final mover = game.get(from);
      final target = game.get(sq);
      PieceKind? captured = target == null ? null : kindOf(target.type);
      if (captured == null &&
          mover != null &&
          mover.type == ch.PieceType.PAWN &&
          from[0] != sq[0]) {
        captured = PieceKind.pawn; // en passant
      }

      final candidates = _selMoves.where((m) => m['to'] == sq).toList();
      String? san;
      if (candidates.isNotEmpty) {
        final pick = candidates.firstWhere(
          (m) => candidates.length == 1 || m['promotion']?.toString() == 'q',
          orElse: () => candidates.first,
        );
        san = pick['san']?.toString();
      }

      final before = game.history.length;
      game.move({'from': from, 'to': sq, 'promotion': 'q'});
      if (game.history.length == before) {
        setState(_clear);
        return;
      }

      final record = MoveRecord(
        san: san ?? '$from$sq',
        from: from,
        to: sq,
        white: mover?.color == ch.Color.WHITE,
        captured: captured,
      );
      setState(_clear);
      Sfx.instance.playSan(record.san);
      widget.onMoved(record);
    }
  }

  String? _checkedKing() {
    final game = widget.game;
    if (!game.in_check) return null;
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        final sq = _square(r, c);
        final p = game.get(sq);
        if (p != null && p.type == ch.PieceType.KING && p.color == game.turn) {
          return sq;
        }
      }
    }
    return null;
  }

  TextStyle _frameStyle(double frame) =>
      coordTextStyle(widget.pal.frameText, frame);

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(builder: (context, c) {
          final total = math.min(c.maxWidth, c.maxHeight);
          final frame = total * 0.05;
          final inner = total - frame * 2;
          final cell = inner / 8;
          final checked = _checkedKing();

          return Container(
            width: total,
            height: total,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(total * 0.012),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [pal.frameA, pal.frameB],
              ),
              border: widget.style == 1
                  ? Border.all(
                      color: pal.frameLine,
                      width: math.max(1.5, total * 0.004),
                    )
                  : null,
              boxShadow: const [
                BoxShadow(
                  blurRadius: 24,
                  offset: Offset(0, 10),
                  color: Colors.black45,
                ),
              ],
            ),
            child: Stack(
              children: [
                for (var i = 0; i < 8; i++) ...[
                  Positioned(
                    left: 0,
                    top: frame + i * cell,
                    width: frame,
                    height: cell,
                    child: Center(
                      child: Text(widget.flipped ? '${i + 1}' : '${8 - i}',
                          style: _frameStyle(frame)),
                    ),
                  ),
                  Positioned(
                    left: frame + i * cell,
                    bottom: 0,
                    width: cell,
                    height: frame,
                    child: Center(
                      child: Text(_files[widget.flipped ? 7 - i : i],
                          style: _frameStyle(frame)),
                    ),
                  ),
                ],
                Positioned(
                  left: frame,
                  top: frame,
                  width: inner,
                  height: inner,
                  child: RawGestureDetector(
                    // Telefonda doska ustida sudrash sahifani aylantirmasligi uchun
                    gestures: {
                      EagerGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                              EagerGestureRecognizer>(
                        () => EagerGestureRecognizer(),
                        (_) {},
                      ),
                    },
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) {
                        if (e.buttons == kSecondaryMouseButton) {
                          // O'ng tugma: premove ni bekor qilish
                          widget.onPremove?.call(null, null);
                          setState(_clear);
                          return;
                        }
                        _pDown(e.localPosition, cell);
                      },
                      onPointerMove: (e) => _pMove(e.localPosition, cell),
                      onPointerUp: (e) => _pUp(e.localPosition, cell),
                      onPointerCancel: (_) => _pCancel(),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: pal.frameLine, width: 1.2),
                        ),
                        child: Column(
                          children: [
                            for (var r = 0; r < 8; r++)
                              Expanded(
                                child: Row(
                                  children: [
                                    for (var f = 0; f < 8; f++)
                                      Expanded(
                                          child: _cell(r, f, cell, checked)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (_dragActive && _dragFrom != null)
                  Positioned(
                    left: frame + _dragPos.dx - cell * 0.58,
                    top: frame + _dragPos.dy - cell * 0.58,
                    width: cell * 1.16,
                    height: cell * 1.16,
                    child: IgnorePointer(
                      child: Builder(builder: (_) {
                        final pc = widget.game.get(_dragFrom!);
                        if (pc == null) return const SizedBox.shrink();
                        return PieceView(
                          kind: kindOf(pc.type),
                          white: pc.color == ch.Color.WHITE,
                          size: cell * 1.16,
                          style: widget.style,
                        );
                      }),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _cell(int row, int col, double cell, String? checked) {
    final sq = _square(row, col);
    final isLight = (row + col) % 2 == 0;
    final piece = widget.game.get(sq);
    final isTarget = _targets.contains(sq);
    final isLast = sq == widget.lastFrom || sq == widget.lastTo;
    final isSel = sq == _selected;

    final isPremove = sq == widget.premoveFrom || sq == widget.premoveTo;
    final hiddenPiece = _dragActive && sq == _dragFrom;
    final hover = _dragActive && sq == _hoverSq && isTarget;
    return ColoredBox(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _SquarePainter(
              style: widget.style,
              light: isLight,
              seed: row * 8 + col,
              base: isLight ? widget.pal.boardLight : widget.pal.boardDark,
            ),
          ),
          if (isLast) const ColoredBox(color: Color(0x80CDD26A)),
          if (isSel) const ColoredBox(color: Color(0x99F6F669)),
          if (checked == sq)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [Color(0xCCE53935), Color(0x00E53935)],
                ),
              ),
            ),
          if (isPremove)
            const ColoredBox(color: Color(0x88E8590C)),
          if (hover)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xCCFFFFFF),
                  width: cell * 0.06,
                ),
              ),
            ),
          if (isTarget && piece == null)
            Center(
              child: Container(
                width: cell * 0.3,
                height: cell * 0.3,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x55000000),
                ),
              ),
            ),
          if (isTarget && piece != null)
            Container(
              margin: EdgeInsets.all(cell * 0.04),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0x66000000),
                  width: cell * 0.08,
                ),
              ),
            ),
          if (piece != null && !hiddenPiece)
            Padding(
              padding: EdgeInsets.all(cell * 0.02),
              child: AnimatedScale(
                scale: isSel ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 120),
                child: PieceView(
                  kind: kindOf(piece.type),
                  white: piece.color == ch.Color.WHITE,
                  size: cell * 0.96,
                  style: widget.style,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tanlash oynasidagi kichik doska namunasi.
class BoardPreview extends StatelessWidget {
  const BoardPreview({super.key, required this.style, required this.size});
  final int style;
  final double size;

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(style, false);
    final cell = size / 4;

    (PieceKind, bool)? pieceAt(int r, int c) {
      if (r == 0 && c == 2) return (PieceKind.king, false);
      if (r == 1 && c == 1) return (PieceKind.knight, true);
      if (r == 2 && c == 3) return (PieceKind.pawn, false);
      if (r == 3 && c == 0) return (PieceKind.queen, true);
      return null;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: Column(
          children: [
            for (var r = 0; r < 4; r++)
              Expanded(
                child: Row(
                  children: [
                    for (var c = 0; c < 4; c++)
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CustomPaint(
                              painter: _SquarePainter(
                                style: style,
                                light: (r + c) % 2 == 0,
                                seed: r * 4 + c,
                                base: (r + c) % 2 == 0
                                    ? pal.boardLight
                                    : pal.boardDark,
                              ),
                            ),
                            if (pieceAt(r, c) != null)
                              Padding(
                                padding: EdgeInsets.all(cell * 0.02),
                                child: PieceView(
                                  kind: pieceAt(r, c)!.$1,
                                  white: pieceAt(r, c)!.$2,
                                  size: cell * 0.96,
                                  style: style,
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
    );
  }
}

// ---------------------------------------------------------------------------
// Soat: 0 = LCD, 1 = ag'dariladigan (flip) kartochkalar, 2 = klassik serif
// ---------------------------------------------------------------------------

const Color _redLow = Color(0xFFFF6B5E);

const Map<String, String> _digitSegs = {
  '0': 'abcdef',
  '1': 'bc',
  '2': 'abged',
  '3': 'abgcd',
  '4': 'fgbc',
  '5': 'afgcd',
  '6': 'afgedc',
  '7': 'abc',
  '8': 'abcdefg',
  '9': 'abcdfg',
};

Map<String, List<Offset>> _segPolys(double w, double h) {
  final t = h * 0.13;
  final g = h * 0.012;

  List<Offset> hor(double yc) {
    final x0 = t / 2 + g;
    final x1 = w - t / 2 - g;
    return [
      Offset(x0, yc),
      Offset(x0 + t / 2, yc - t / 2),
      Offset(x1 - t / 2, yc - t / 2),
      Offset(x1, yc),
      Offset(x1 - t / 2, yc + t / 2),
      Offset(x0 + t / 2, yc + t / 2),
    ];
  }

  List<Offset> ver(double xc, double y0, double y1) => [
        Offset(xc, y0),
        Offset(xc + t / 2, y0 + t / 2),
        Offset(xc + t / 2, y1 - t / 2),
        Offset(xc, y1),
        Offset(xc - t / 2, y1 - t / 2),
        Offset(xc - t / 2, y0 + t / 2),
      ];

  final top = t / 2;
  final mid = h / 2;
  final bot = h - t / 2;
  return {
    'a': hor(top),
    'g': hor(mid),
    'd': hor(bot),
    'f': ver(t / 2, top + g, mid - g),
    'b': ver(w - t / 2, top + g, mid - g),
    'e': ver(t / 2, mid + g, bot - g),
    'c': ver(w - t / 2, mid + g, bot - g),
  };
}

class _LcdPainter extends CustomPainter {
  const _LcdPainter({required this.text, required this.on, required this.off});
  final String text;
  final Color on;
  final Color off;

  @override
  void paint(Canvas canvas, Size size) {
    final dh = size.height * 0.62;
    final dw = dh * 0.52;
    final gap = dw * 0.28;
    final colw = dw * 0.4;
    final total = 4 * dw + 5 * gap + colw;
    var pos = (size.width - total) / 2;
    final cy = (size.height - dh) / 2;

    final onPaint = Paint()..color = on;
    final offPaint = Paint()..color = off;
    final glow = Paint()
      ..color = on.withAlpha(110)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);

    for (final c in text.split('')) {
      if (c == ':') {
        final r = dh * 0.055;
        final cx = pos + colw / 2 + gap / 2;
        for (final yy in [cy + dh * 0.33, cy + dh * 0.67]) {
          canvas.drawCircle(Offset(cx, yy), r * 1.8, glow);
          canvas.drawCircle(Offset(cx, yy), r, onPaint);
        }
        pos += colw + gap * 2;
      } else {
        final segs = _digitSegs[c] ?? '';
        _segPolys(dw, dh).forEach((name, poly) {
          final path = Path()
            ..addPolygon([for (final p in poly) p.translate(pos, cy)], true);
          if (segs.contains(name)) {
            canvas.drawPath(path, glow);
            canvas.drawPath(path, onPaint);
          } else {
            canvas.drawPath(path, offPaint);
          }
        });
        pos += dw + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LcdPainter old) =>
      old.text != text || old.on != on || old.off != off;
}

class ClockView extends StatelessWidget {
  const ClockView({
    super.key,
    required this.style,
    required this.seconds,
    required this.active,
    required this.low,
    this.width = 172,
  });

  final int style;
  final int seconds;
  final bool active;
  final bool low;
  final double width;

  Widget _lcd(String text) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B140E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? const Color(0xFF4DDB74) : const Color(0xFF1E3A28),
          width: 1.5,
        ),
      ),
      child: CustomPaint(
        painter: _LcdPainter(
          text: text,
          on: low ? _redLow : const Color(0xFF6BFF8E),
          off: const Color(0xFF143021),
        ),
      ),
    );
  }

  Widget _flip(String text) {
    Widget tile(String d) => Container(
          width: 33,
          height: 50,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A30),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? const Color(0xFFE2B455) : const Color(0xFF3A3A42),
              width: 1.2,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                d,
                style: TextStyle(
                  fontSize: 31,
                  height: 1.0,
                  fontWeight: FontWeight.w700,
                  color: low ? _redLow : const Color(0xFFF3E9D0),
                ),
              ),
              Container(height: 1.6, color: const Color(0xFF0A0A0C)),
            ],
          ),
        );

    Widget dot() => Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFE9DDBC),
          ),
        );

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          tile(text[0]),
          const SizedBox(width: 4),
          tile(text[1]),
          SizedBox(
            width: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [dot(), const SizedBox(height: 12), dot()],
            ),
          ),
          tile(text[3]),
          const SizedBox(width: 4),
          tile(text[4]),
        ],
      ),
    );
  }

  Widget _classic(String text) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF4A2F1B), Color(0xFF2B1A0F)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? const Color(0xFFE2B455) : const Color(0xFF7A5A2A),
          width: 1.6,
        ),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Georgia',
            fontFamilyFallback: const ['Times New Roman', 'serif'],
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: low ? _redLow : const Color(0xFFF0D79A),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = formatClock(seconds);
    final Widget inner;
    switch (style) {
      case 1:
        inner = _flip(text);
        break;
      case 2:
        inner = _classic(text);
        break;
      default:
        inner = _lcd(text);
    }
    return SizedBox(
      width: width,
      height: width * 60 / 176,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(width: 176, height: 60, child: inner),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// O'yinchi kartasi: ism-familiya, reyting, olingan donalar va soat yonma-yon
// ---------------------------------------------------------------------------

class PlayerCard extends StatelessWidget {
  const PlayerCard({
    super.key,
    required this.pal,
    required this.boardStyle,
    required this.clockStyle,
    required this.name,
    required this.rating,
    required this.subtitle,
    required this.white,
    required this.captured,
    required this.advantage,
    required this.seconds,
    required this.active,
    this.avatar,
    this.initials = '',
  });

  final Uint8List? avatar;
  final String initials;
  final Pal pal;
  final int boardStyle;
  final int clockStyle;
  final String name;
  final String rating;
  final String subtitle;
  final bool white;

  /// Bu o'yinchi olgan (raqibning) donalari.
  final List<PieceKind> captured;
  final int advantage;
  final int seconds;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final sorted = [...captured]
      ..sort((a, b) => pieceValue(b).compareTo(pieceValue(a)));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: pal.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? pal.accent : pal.cardBorder,
          width: active ? 1.6 : 1,
        ),
        boxShadow: active
            ? [BoxShadow(color: pal.accent.withAlpha(0x40), blurRadius: 12)]
            : null,
      ),
      child: Row(
        children: [
          avatar != null || initials.isNotEmpty
              ? AvatarView(
                  size: 46,
                  initials: initials,
                  pal: pal,
                  bytes: avatar,
                )
              : Container(
                  width: 46,
                  height: 46,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: white ? pal.avatarWhite : pal.avatarBlack,
                    border: Border.all(color: pal.cardBorder),
                  ),
                  child: PieceView(
                    kind: PieceKind.king,
                    white: white,
                    size: 38,
                    style: boardStyle,
                  ),
                ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: pal.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: pal.accentSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: pal.accent),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded, size: 14, color: pal.accent),
                          const SizedBox(width: 3),
                          Text(
                            rating,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: pal.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: pal.subtext),
                ),
                if (sorted.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SizedBox(
                      height: 20,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final k in sorted)
                              Align(
                                widthFactor: 0.55,
                                child: PieceView(
                                  kind: k,
                                  white: !white,
                                  size: 20,
                                  style: boardStyle,
                                ),
                              ),
                            if (advantage > 0)
                              Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: Text(
                                  '+$advantage',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: pal.subtext,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ClockView(
            style: clockStyle,
            seconds: seconds,
            active: active,
            low: seconds <= 30,
            width: 158,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Yurishlar ro'yxati
// ---------------------------------------------------------------------------

class MoveListPanel extends StatefulWidget {
  const MoveListPanel({
    super.key,
    required this.pal,
    required this.moves,
    required this.title,
    required this.emptyText,
  });

  final Pal pal;
  final List<MoveRecord> moves;
  final String title;
  final String emptyText;

  @override
  State<MoveListPanel> createState() => _MoveListPanelState();
}

class _MoveListPanelState extends State<MoveListPanel> {
  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(covariant MoveListPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _moveCell(MoveRecord? m, bool latest) {
    final pal = widget.pal;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: latest ? pal.accentSoft : null,
        ),
        child: Text(
          m?.san ?? '',
          style: TextStyle(
            fontSize: 14,
            fontWeight: latest ? FontWeight.w700 : FontWeight.w500,
            color: pal.text,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.pal;
    final moves = widget.moves;
    final rows = (moves.length + 1) ~/ 2;

    return Container(
      decoration: BoxDecoration(
        color: pal.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(Icons.format_list_numbered, size: 20, color: pal.accent),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: pal.text,
                  ),
                ),
                const Spacer(),
                Text(
                  '${moves.length}',
                  style: TextStyle(color: pal.subtext, fontSize: 13),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: pal.cardBorder),
          Expanded(
            child: moves.isEmpty
                ? Center(
                    child: Text(
                      widget.emptyText,
                      style: TextStyle(color: pal.subtext),
                    ),
                  )
                : ListView.builder(
                    controller: _controller,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    itemCount: rows,
                    itemBuilder: (context, i) {
                      final white = moves[2 * i];
                      final black = 2 * i + 1 < moves.length
                          ? moves[2 * i + 1]
                          : null;
                      return Row(
                        children: [
                          SizedBox(
                            width: 34,
                            child: Text(
                              '${i + 1}.',
                              style: TextStyle(
                                color: pal.subtext,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          _moveCell(white, 2 * i == moves.length - 1),
                          _moveCell(black, 2 * i + 1 == moves.length - 1),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
