import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'settings.dart';
import 'widgets/chess_board.dart';

/// Yechilgan masalalar va ilovada o'tkazilgan vaqtni serverga yuboradi.
Future<void> syncProgress(AppSettings s) async {
  final token = s.token;
  if (token == null) return;
  final days = <String, Map<String, Object>>{};
  final now = DateTime.now();
  for (var i = 0; i < 30; i++) {
    final k = AppSettings.dayKey(now.subtract(Duration(days: i)));
    final cats = s.catSeconds(k);
    final sec = (s.activity[k] ?? 0) - (cats['passive'] ?? 0);
    final blocks = (s.planDone[k] ?? const <int>[]).length;
    if (sec > 0 || blocks > 0) days[k] = {'seconds': sec < 0 ? 0 : sec, 'blocks': blocks, 'cats': cats};
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
  bool _lazy = false; // false: yetakchilar, true: dangasalar doskasi
  List<Map<String, dynamic>> _lazyItems = [];
  Map<String, dynamic>? _lazyMe;
  int _lazyTotal = 0;
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
      final lz = await Api.get('/leaderboard/lazy', token);
      if (!mounted) return;
      setState(() {
        _items = (res['items'] as List).cast<Map<String, dynamic>>();
        _me = res['me'] as Map<String, dynamic>?;
        _total = (res['total'] as num).toInt();
        _lazyItems = (lz['items'] as List).cast<Map<String, dynamic>>();
        _lazyMe = lz['me'] as Map<String, dynamic>?;
        _lazyTotal = (lz['total'] as num).toInt();
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

  Widget _lazyRow(Map<String, dynamic> r) {
    final rank = (r['rank'] as num).toInt();
    final me = r['isMe'] == true;
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
            child: rank <= 3
                ? Text(
                    rank == 1 ? '🦥' : (rank == 2 ? '🐌' : '🐢'),
                    style: const TextStyle(fontSize: 20),
                  )
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
            '${r['solved']} ${t('st_solved_short')}  ·  ${r['blocks']} ${t('st_blocks_short')}',
            style: TextStyle(fontSize: 12.5, color: pal.subtext),
          ),
          const SizedBox(width: 14),
          Text(
            '${r['minutes']} ${t('st_min')}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: pal.accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _boardSwitch() => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: false,
              icon: const Icon(Icons.emoji_events, size: 18),
              label: Text(t('st_board_top')),
            ),
            ButtonSegment(
              value: true,
              icon: const Icon(Icons.bedtime_outlined, size: 18),
              label: Text(t('st_board_lazy')),
            ),
          ],
          selected: {_lazy},
          onSelectionChanged: (v) => setState(() => _lazy = v.first),
        ),
      );

  Widget _lazyBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card(
          pal,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🦥', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t('st_lazy_title'),
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
              if (_lazyMe != null)
                Row(
                  children: [
                    _big('#${_lazyMe!['rank']}', t('st_rank')),
                    const SizedBox(width: 10),
                    _big('${_lazyMe!['minutes']}', t('st_active_min7')),
                    const SizedBox(width: 10),
                    _big('${_lazyMe!['solved']}', t('st_solved7')),
                  ],
                ),
              const SizedBox(height: 10),
              Text(
                t('st_lazy_hint'),
                style: TextStyle(fontSize: 12.5, color: pal.subtext),
              ),
            ],
          ),
        ),
        for (final r in _lazyItems) _lazyRow(r),
        if (_lazyTotal > _lazyItems.length)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('… $_lazyTotal',
                textAlign: TextAlign.center,
                style: TextStyle(color: pal.subtext)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_lazy && !_loading && _error == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [_boardSwitch(), _lazyBody()],
          ),
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _boardSwitch(),
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
  int _period = 0; // 0 bugun, 1 hafta, 2 oy
  List<Map<String, dynamic>> _students = [];
  bool get _isCoach => s.role == 'coach';

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
      if (_isCoach) {
        final cs = await Api.get('/coach/students', token);
        if (mounted) {
          setState(() => _students = [
                for (final x in (cs['students'] as List? ?? const []))
                  Map<String, dynamic>.from(x as Map),
              ]);
        }
      }
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

  /// So'nggi [days] kun uchun bo'limlar bo'yicha soniyalar.
  Map<String, int> _catTotals(int days) {
    final out = <String, int>{};
    for (final d in _lastDays(days)) {
      s.catSeconds(AppSettings.dayKey(d)).forEach((k, v) {
        out[k] = (out[k] ?? 0) + v;
      });
    }
    return out;
  }

  String _fmtDur(int sec) {
    if (sec < 60) return sec <= 0 ? '0 ${t('st_min')}' : '<1 ${t('st_min')}';
    final m = (sec / 60).round();
    if (m < 60) return '$m ${t('st_min')}';
    return '${m ~/ 60} ${t('st_hour')} ${m % 60} ${t('st_min')}';
  }

  static const _catIcons = {
    'play': Icons.sports_esports,
    'train': Icons.extension,
    'task': Icons.assignment_turned_in,
    'analysis': Icons.analytics_outlined,
    'lessons': Icons.menu_book,
    'rating': Icons.leaderboard,
    'stats': Icons.insights,
  };

  Widget _catRow(String cat, int sec, int total, {bool passive = false}) {
    final frac = total <= 0 ? 0.0 : sec / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            passive ? Icons.hourglass_empty : _catIcons[cat],
            size: 20,
            color: passive ? pal.subtext : pal.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 5,
            child: Text(
              t('st_cat_$cat'),
              style: TextStyle(fontWeight: FontWeight.w600, color: pal.text),
            ),
          ),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 8,
                backgroundColor: pal.cardBorder,
                color: passive ? pal.subtext : pal.accent,
              ),
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              _fmtDur(sec),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: passive ? pal.subtext : pal.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _catCard() {
    final today = _catTotals(1);
    final week = _catTotals(7);
    final month = _catTotals(30);
    final totals = _period == 0 ? today : (_period == 1 ? week : month);
    final total = totals.values.fold<int>(0, (a, b) => a + b);
    final active = total - (totals['passive'] ?? 0);
    return _card(
      pal,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('st_breakdown'),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15.5,
              color: pal.text,
            ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 0, label: Text(t('today'))),
              ButtonSegment(value: 1, label: Text(t('week'))),
              ButtonSegment(value: 2, label: Text(t('month'))),
            ],
            selected: {_period},
            onSelectionChanged: (v) => setState(() => _period = v.first),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _tile(_fmtDur(total), t('st_total_time')),
              const SizedBox(width: 8),
              _tile(_fmtDur(active), t('st_active_time')),
              const SizedBox(width: 8),
              _tile(_fmtDur(totals['passive'] ?? 0), t('st_cat_passive')),
            ],
          ),
          const SizedBox(height: 10),
          for (final c in AppSettings.activeCats)
            _catRow(c, totals[c] ?? 0, total),
          const Divider(height: 18),
          _catRow('passive', totals['passive'] ?? 0, total, passive: true),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              t('st_passive_hint'),
              style: TextStyle(fontSize: 11.5, color: pal.subtext),
            ),
          ),
        ],
      ),
    );
  }

  Widget _studentsCard() {
    return _card(
      pal,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('st_students'),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15.5,
              color: pal.text,
            ),
          ),
          const SizedBox(height: 6),
          if (_students.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(t('st_no_students'),
                  style: TextStyle(color: pal.subtext)),
            ),
          for (final st in _students)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: pal.accentSoft,
                child: Icon(Icons.person, color: pal.accent),
              ),
              title: Text('${st['name']}',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: pal.text)),
              subtitle: Text(
                '${t('st_rating')}: ${st['rating']}  ·  ${st['minutes7'] ?? 0} ${t('st_min')} / ${t('week')}',
                style: TextStyle(color: pal.subtext, fontSize: 12.5),
              ),
              trailing: Icon(Icons.chevron_right, color: pal.subtext),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => StudentStatsPage(
                  settings: s,
                  pal: pal,
                  studentId: st['id'] as int,
                  name: '${st['name']}',
                ),
              )),
            ),
        ],
      ),
    );
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
                _catCard(),
                if (!_isCoach) ...[
                  const SizedBox(height: 14),
                  _bars(t('st_time_chart'), days, minutes),
                  const SizedBox(height: 14),
                  _bars(t('st_puzzles_chart'), days, solved),
                  const SizedBox(height: 14),
                  _bars(t('st_blocks_chart'), days, blocks),
                ],
                if (_isCoach) ...[
                  const SizedBox(height: 14),
                  _studentsCard(),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}


/// Trener uchun: bitta o'quvchining batafsil statistikasi.
class StudentStatsPage extends StatefulWidget {
  const StudentStatsPage({
    super.key,
    required this.settings,
    required this.pal,
    required this.studentId,
    required this.name,
  });
  final AppSettings settings;
  final Pal pal;
  final int studentId;
  final String name;

  @override
  State<StudentStatsPage> createState() => _StudentStatsPageState();
}

class _StudentStatsPageState extends State<StudentStatsPage> {
  Map<String, dynamic>? _data;
  bool _err = false;
  int _period = 1; // 0 bugun, 1 hafta, 2 oy

  Pal get pal => widget.pal;
  String t(String k) => tr(widget.settings.lang, k);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Api.get(
          '/coach/students/${widget.studentId}/stats', widget.settings.token!);
      if (mounted) setState(() => _data = res);
    } catch (_) {
      if (mounted) setState(() => _err = true);
    }
  }

  String _fmt(int sec) {
    final m = (sec / 60).round();
    if (sec <= 0) return '0 ${t('st_min')}';
    if (m < 60) return '${m < 1 ? '<1' : '$m'} ${t('st_min')}';
    return '${m ~/ 60} ${t('st_hour')} ${m % 60} ${t('st_min')}';
  }

  Widget _tile(String v, String l) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: pal.accentSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            Text(v,
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: pal.text)),
            Text(l,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: pal.subtext)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = _data;
    Widget body;
    if (d == null) {
      body = Center(
        child: _err
            ? Text(t('st_load_err'), style: TextStyle(color: pal.text))
            : const CircularProgressIndicator(),
      );
    } else {
      final st = Map<String, dynamic>.from(d['student'] as Map);
      final days = [
        for (final x in (d['days'] as List)) Map<String, dynamic>.from(x as Map)
      ];
      final n = _period == 0 ? 1 : (_period == 1 ? 7 : 30);
      final now = DateTime.now();
      final from = AppSettings.dayKey(
          DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: n - 1)));
      final sel = [for (final x in days) if ((x['day'] as String).compareTo(from) >= 0) x];
      final cats = <String, int>{};
      var total = 0, solved = 0, blocks = 0;
      for (final x in sel) {
        total += (x['seconds'] as num).toInt();
        solved += (x['solved'] as num).toInt();
        blocks += (x['blocks'] as num).toInt();
        (x['cats'] as Map).forEach((k, v) {
          cats[k as String] = (cats[k] ?? 0) + (v as num).toInt();
        });
      }
      final passive = cats['passive'] ?? 0;
      final catSum = cats.values.fold<int>(0, (a, b) => a + b);
      final shownTotal = catSum > total ? catSum : total;
      final maxSec = sel.fold<int>(
          1, (m, x) => (x['seconds'] as num).toInt() > m ? (x['seconds'] as num).toInt() : m);
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            pal,
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.name,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: pal.text)),
              const SizedBox(height: 10),
              Row(children: [
                _tile('${st['rating']}', t('st_rating')),
                const SizedBox(width: 8),
                _tile('${st['solvedTotal']}', t('st_solved')),
                const SizedBox(width: 8),
                _tile('${st['tasksDone']}/${st['tasksTotal']}', t('st_tasks_done')),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          _card(
            pal,
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('st_breakdown'),
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                      color: pal.text)),
              const SizedBox(height: 10),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 0, label: Text(t('today'))),
                  ButtonSegment(value: 1, label: Text(t('week'))),
                  ButtonSegment(value: 2, label: Text(t('month'))),
                ],
                selected: {_period},
                onSelectionChanged: (v) => setState(() => _period = v.first),
              ),
              const SizedBox(height: 12),
              Row(children: [
                _tile(_fmt(shownTotal), t('st_total_time')),
                const SizedBox(width: 8),
                _tile(_fmt(shownTotal - passive), t('st_active_time')),
                const SizedBox(width: 8),
                _tile(_fmt(passive), t('st_cat_passive')),
              ]),
              const SizedBox(height: 10),
              for (final c in [...AppSettings.activeCats, 'passive'])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Expanded(
                      flex: 5,
                      child: Text(t('st_cat_$c'),
                          style: TextStyle(
                              fontWeight: FontWeight.w600, color: pal.text)),
                    ),
                    Expanded(
                      flex: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: shownTotal <= 0
                              ? 0
                              : (cats[c] ?? 0) / shownTotal,
                          minHeight: 8,
                          backgroundColor: pal.cardBorder,
                          color: c == 'passive' ? pal.subtext : pal.accent,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 92,
                      child: Text(_fmt(cats[c] ?? 0),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontWeight: FontWeight.w800, color: pal.text)),
                    ),
                  ]),
                ),
              const SizedBox(height: 8),
              Text('${t('st_solved')}: $solved  ·  ${t('st_blocks_chart')}: $blocks',
                  style: TextStyle(color: pal.subtext, fontSize: 12.5)),
            ]),
          ),
          const SizedBox(height: 14),
          _card(
            pal,
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('st_time_chart'),
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                      color: pal.text)),
              const SizedBox(height: 10),
              for (final x in sel.reversed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(
                      width: 52,
                      child: Text((x['day'] as String).substring(5),
                          style: TextStyle(fontSize: 12, color: pal.subtext)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (x['seconds'] as num).toInt() / maxSec,
                          minHeight: 8,
                          backgroundColor: pal.cardBorder,
                          color: pal.accent,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 84,
                      child: Text(_fmt((x['seconds'] as num).toInt()),
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 12, color: pal.text)),
                    ),
                  ]),
                ),
            ]),
          ),
        ],
      );
    }
    return Scaffold(
      backgroundColor: pal.bg1,
      appBar: AppBar(
        title: Text(widget.name),
        backgroundColor: pal.bg1,
        foregroundColor: pal.text,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: body,
        ),
      ),
    );
  }
}
