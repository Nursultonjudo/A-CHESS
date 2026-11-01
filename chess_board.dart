import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as ch;

const _lightSquare = Color(0xFFF0D9B5);
const _darkSquare = Color(0xFFB58863);
const _selectedColor = Color(0xFFF6F669);

/// Klassik shaxmat doskasi: bosib tanlab, yurish mumkin bo'lgan kataklar ko'rsatiladi.
class ChessBoard extends StatefulWidget {
  const ChessBoard({super.key, required this.game, required this.onMoved});

  final ch.Chess game;
  final VoidCallback onMoved;

  @override
  State<ChessBoard> createState() => _ChessBoardState();
}

class _ChessBoardState extends State<ChessBoard> {
  String? _selected;
  List<String> _targets = [];

  static String _square(int row, int col) => '${'abcdefgh'[col]}${8 - row}';

  static String _glyph(ch.Piece p) {
    // Ikkala rang uchun to'ldirilgan shakl ishlatiladi, rangni o'zimiz beramiz.
    final t = p.type;
    final String g;
    if (t == ch.PieceType.KING) {
      g = '\u265A';
    } else if (t == ch.PieceType.QUEEN) {
      g = '\u265B';
    } else if (t == ch.PieceType.ROOK) {
      g = '\u265C';
    } else if (t == ch.PieceType.BISHOP) {
      g = '\u265D';
    } else if (t == ch.PieceType.KNIGHT) {
      g = '\u265E';
    } else {
      g = '\u265F';
    }
    // \uFE0E: ba'zi qurilmalarda emoji emas, oddiy belgi ko'rinishi uchun.
    return '$g\uFE0E';
  }

  void _onTap(String sq) {
    final game = widget.game;
    if (_selected != null && _targets.contains(sq)) {
      game.move({'from': _selected, 'to': sq, 'promotion': 'q'});
      setState(() {
        _selected = null;
        _targets = [];
      });
      widget.onMoved();
      return;
    }
    final piece = game.get(sq);
    if (piece != null && piece.color == game.turn) {
      final moves = game.moves({'verbose': true, 'square': sq}) as List;
      setState(() {
        _selected = sq;
        _targets = [for (final m in moves) (m as Map)['to'] as String];
      });
    } else {
      setState(() {
        _selected = null;
        _targets = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, c) {
        final size = c.maxWidth / 8;
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF5D4037), width: 3),
            boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black38)],
          ),
          child: Column(
            children: [
              for (var r = 0; r < 8; r++)
                Expanded(
                  child: Row(
                    children: [
                      for (var f = 0; f < 8; f++)
                        Expanded(child: _cell(r, f, size)),
                    ],
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _cell(int row, int col, double size) {
    final sq = _square(row, col);
    final isLight = (row + col) % 2 == 0;
    final piece = widget.game.get(sq);
    final isTarget = _targets.contains(sq);

    return GestureDetector(
      onTap: () => _onTap(sq),
      child: Container(
        color: sq == _selected
            ? _selectedColor
            : (isLight ? _lightSquare : _darkSquare),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (col == 0)
              Positioned(
                left: 2,
                top: 1,
                child: Text('${8 - row}', style: _coordStyle(isLight, size)),
              ),
            if (row == 7)
              Positioned(
                right: 2,
                bottom: 1,
                child: Text('abcdefgh'[col], style: _coordStyle(isLight, size)),
              ),
            if (isTarget)
              Container(
                width: size * (piece != null ? 0.9 : 0.3),
                height: size * (piece != null ? 0.9 : 0.3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: piece != null ? null : Colors.black26,
                  border: piece != null
                      ? Border.all(color: Colors.black38, width: size * 0.07)
                      : null,
                ),
              ),
            if (piece != null) _pieceWidget(piece, size),
          ],
        ),
      ),
    );
  }

  TextStyle _coordStyle(bool isLight, double size) => TextStyle(
        fontSize: size * 0.18,
        fontWeight: FontWeight.w600,
        color: isLight ? _darkSquare : _lightSquare,
      );

  Widget _pieceWidget(ch.Piece p, double size) {
    final isWhite = p.color == ch.Color.WHITE;
    final glyph = _glyph(p);
    final fontSize = size * 0.8;
    // Oq dona: oq to'ldirish + qora kontur. Qora dona: qora to'ldirish.
    return FittedBox(
      fit: BoxFit.contain,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            glyph,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.1,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = fontSize * 0.06
                ..color = isWhite ? Colors.black : const Color(0xFFEEEEEE),
            ),
          ),
          Text(
            glyph,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.1,
              color: isWhite ? Colors.white : const Color(0xFF1B1B1B),
            ),
          ),
        ],
      ),
    );
  }
}
