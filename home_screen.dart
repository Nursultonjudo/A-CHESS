import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as ch;
import '../l10n.dart';
import '../settings.dart';
import '../widgets/chess_board.dart';

/// Asosiy oyna: chap tomonda bo'limlar, o'ngda shaxmat doskasi.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ch.Chess _game = ch.Chess();
  int _tab = 0;
  int _boardKey = 0;

  AppSettings get s => widget.settings;
  String t(String key, [Map<String, String> args = const {}]) =>
      tr(s.lang, key, args);

  String get _status {
    if (_game.in_checkmate) {
      final winner = _game.turn == ch.Color.WHITE ? t('black') : t('white');
      return t('checkmate', {'winner': winner});
    }
    if (_game.in_draw) return t('draw');
    final turn = _game.turn == ch.Color.WHITE ? t('turn_white') : t('turn_black');
    return _game.in_check ? '${t('check')} $turn' : turn;
  }

  void _newGame() => setState(() {
        _game.reset();
        _boardKey++;
      });

  void _undo() => setState(() {
        _game.undo_move();
        _boardKey++;
      });

  Widget _playTab() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChessBoard(
                key: ValueKey(_boardKey),
                game: _game,
                onMoved: () => setState(() {}),
              ),
              const SizedBox(height: 16),
              Text(_status, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _newGame,
                    icon: const Icon(Icons.refresh),
                    label: Text(t('new_game')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _game.history.isEmpty ? null : _undo,
                    icon: const Icon(Icons.undo),
                    label: Text(t('undo')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _soonTab(IconData icon, String title) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          Text(t('soon')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <(IconData, String)>[
      (Icons.sports_esports, t('nav_play')),
      (Icons.leaderboard, t('nav_rating')),
      (Icons.insights, t('nav_stats')),
      (Icons.assignment, t('nav_tasks')),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(t('app_title')),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: s.lang,
              items: [
                for (final e in languageNames.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => v == null ? null : s.setLang(v),
            ),
          ),
          IconButton(
            tooltip: t('theme'),
            icon: Icon(s.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => s.setDark(!s.dark),
          ),
          Center(child: Text(s.phone ?? '')),
          IconButton(
            tooltip: t('logout'),
            icon: const Icon(Icons.logout),
            onPressed: s.signOut,
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _tab,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              for (final tab in tabs)
                NavigationRailDestination(icon: Icon(tab.$1), label: Text(tab.$2)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _tab == 0 ? _playTab() : _soonTab(tabs[_tab].$1, tabs[_tab].$2),
          ),
        ],
      ),
    );
  }
}
