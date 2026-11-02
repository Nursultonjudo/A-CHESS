import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'settings.dart';
import 'widgets/chess_board.dart';

/// Yechilgan masalalar va ilovada o'tkazilgan vaqtni serverga yuboradi.
Future<void> syncProgress(AppSettings s) async {
  final token = s.token;
  if (token == null) return;
  final days = <String, Map<String, int>>{};
  final now = DateTime.now();
  for (var i = 0; i < 30; i++) {
    final k = AppSettings.dayKey(now.subtract(Duration(days: i)));
    final sec = s.activity[k] ?? 0;
    final blocks = (s.planDone[k] ?? const <int>[]).length;
    if (sec > 0 || blocks > 0) days[k] = {'seconds': sec, 'blocks': blocks};
  }
  await Api.post('/me/solved', token, {'solved': s.solved});
  await Api.post('/me/activity', token, {'days': days});
}

Widget _card(Pal pal, Widget child) => Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: pal.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.cardBorder),
      ),
      child: child,
    );

// ---------------------------------------------------------------------------
// Reyting jadvali
// ---------------------------------------------------------------------------

class RatingView extends StatefulWidget {
  const RatingView({super.key, required this.settings, required this.pal});
  final AppSettings settings;
  final Pal pal;

  @override
  State<RatingView> createState() => _RatingViewState();
}

class _RatingViewState extends State<RatingView> {
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _me;
  int _total = 0;
  bool _loading = true;
  String? _error;

  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = s.token;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      try {
        await syncProgress(s);
      } catch (_) {}
      final res = await Api.get('/leaderboard', token);
      if (!mounted) return;
      setState(() {
        _items = (res['items'] as List).cast<Map<String, dynamic>>();
        _me = res['me'] as Map<String, dynamic>?;
        _total = (res['total'] as num).toInt();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? tr(s.lang, e.l10nKey) : t('err_network');
        _loading = false;
      });
    }
  }

  Widget _row(Map<String, dynamic> r) {
    final rank = (r['rank'] as num).toInt();
    final me = r['isMe'] == true;
    final medal = rank == 1
        ? const Color(0xFFFFC53D)
        : rank == 2
            ? const Color(0xFFB8C2CC)
            : rank == 3
                ? const Color(0xFFD08C5B)
                : null;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: me ? pal.accent.withAlpha(0x26) : pal.bg1.withAlpha(0x66),
        border: Border.all(color: me ? pal.accent : pal.cardBorder),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: medal != null
                ? Icon(Icons.emoji_events, color: medal)
                : Text(
                    '$rank',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: pal.subtext,
                    ),
                  ),
          ),
          Expanded(
            child: Text(
              me ? '${r['name']}  (${t('st_you')})' : r['name'] as String,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: me ? FontWeight.w800 : FontWeight.w600,
                color: pal.text,
              ),
            ),
          ),
          Text(
            '${r['solved']} ${t('st_solved_short')}',
            style: TextStyle(fontSize: 12.5, color: pal.subtext),
          ),
          const SizedBox(width: 14),
          Text(
            '${r['rating']}',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: pal.accent,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card(
              pal,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.leaderboard, color: pal.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t('st_rating_title'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: pal.text,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: t('co_refresh'),
                        onPressed: _loading ? null : _load,
                        icon: Icon(Icons.refresh, color: pal.subtext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_me != null)
                    Row(
                      children: [
                        _big('#${_me!['rank']}', t('st_rank')),
                        const SizedBox(width: 10),
                        _big('${_me!['rating']}', t('st_rating')),
                        const SizedBox(width: 10),
                        _big('${_me!['solved']}', t('st_solved')),
                      ],
                    )
                  else if (!_loading && _error == null)
                    Text(t('st_coach_note'),
                        style: TextStyle(color: pal.subtext)),
                  const SizedBox(height: 10),
                  Text(
                    t('st_points_hint'),
                    style: TextStyle(fontSize: 12.5, color: pal.subtext),
                  ),
                ],
              ),
            ),
            if (_loading)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(t('co_loading'),
                    style: TextStyle(color: pal.subtext)),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.redAccent)),
              )
            else ...[
              if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(t('co_no_students'),
                      style: TextStyle(color: pal.subtext)),
                ),
              for (final r in _items) _row(r),
              if (_total > _items.length)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text('… $_total',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: pal.subtext)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _big(String value, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: pal.accentSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: pal.text,
                ),
              ),
              Text(label, style: TextStyle(fontSize: 12, color: pal.subtext)),
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Mening statistikam
// ---------------------------------------------------------------------------

class StatsView extends StatefulWidget {
  const StatsView({super.key, required this.settings, required this.pal});
  final AppSettings settings;
  final Pal pal;

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  Map<String, dynamic>? _me;

  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);

  @override
  void initState() {
    super.initState();
    _loadRank();
  }

  Future<void> _loadRank() async {
    final token = s.token;
    if (token == null) return;
    try {
      try {
        await syncProgress(s);
      } catch (_) {}
      final res = await Api.get('/leaderboard', token);
      if (mounted) setState(() => _me = res['me'] as Map<String, dynamic>?);
    } catch (_) {
      // Server bo'lmasa, mahalliy statistika baribir ko'rinadi.
    }
  }

  List<DateTime> _lastDays(int n) {
    final now = DateTime.now();
    return [
      for (var i = n - 1; i >= 0; i--)
        DateTime(now.year, now.month, now.day).subtract(Duration(days: i)),
    ];
  }

  int _minutesSince(int days) {
    var sec = 0;
    for (final d in _lastDays(days)) {
      sec += s.activity[AppSettings.dayKey(d)] ?? 0;
    }
    return (sec / 60).round();
  }

  int _solvedOn(DateTime d) {
    final from = d.millisecondsSinceEpoch;
    final to = d.add(const Duration(days: 1)).millisecondsSinceEpoch;
    return s.solved.values.where((v) => v >= from && v < to).length;
  }

  Widget _tile(String value, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: pal.accentSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: pal.text,
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: pal.subtext),
              ),
            ],
          ),
        ),
      );

  Widget _bars(String title, List<DateTime> days, List<int> values) {
    final maxV = values.fold<int>(1, (m, v) => v > m ? v : m);
    return _card(
      pal,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15.5,
              color: pal.text,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < days.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            values[i] > 0 ? '${values[i]}' : '',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: pal.subtext,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            height: values[i] == 0
                                ? 3
                                : 12 + 78 * values[i] / maxV,
                            decoration: BoxDecoration(
                              color: values[i] == 0
                                  ? pal.cardBorder
                                  : pal.accent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${days[i].day}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: pal.subtext,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final days = _lastDays(7);
        final minutes = [
          for (final d in days)
            ((s.activity[AppSettings.dayKey(d)] ?? 0) / 60).round(),
        ];
        final solved = [for (final d in days) _solvedOn(d)];
        final blocks = [
          for (final d in days)
            (s.planDone[AppSettings.dayKey(d)] ?? const <int>[]).length,
        ];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _card(
                  pal,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.insights, color: pal.accent),
                          const SizedBox(width: 10),
                          Text(
                            t('nav_stats'),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: pal.text,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _tile(_me == null ? '—' : '${_me!['rating']}',
                              t('st_rating')),
                          const SizedBox(width: 8),
                          _tile(_me == null ? '—' : '#${_me!['rank']}',
                              t('st_rank')),
                          const SizedBox(width: 8),
                          _tile('${s.solved.length}', t('st_solved')),
                          const SizedBox(width: 8),
                          _tile('${s.streak}', t('st_streak')),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _card(
                  pal,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('st_time'),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                          color: pal.text,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _tile('${_minutesSince(1)}', '${t('today')} (${t('st_min')})'),
                          const SizedBox(width: 8),
                          _tile('${_minutesSince(7)}', '${t('week')} (${t('st_min')})'),
                          const SizedBox(width: 8),
                          _tile('${_minutesSince(30)}', '${t('month')} (${t('st_min')})'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _bars(t('st_time_chart'), days, minutes),
                const SizedBox(height: 14),
                _bars(t('st_puzzles_chart'), days, solved),
                const SizedBox(height: 14),
                _bars(t('st_blocks_chart'), days, blocks),
              ],
            ),
          ),
        );
      },
    );
  }
}
