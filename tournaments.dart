import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'chat.dart';
import 'l10n.dart';
import 'online.dart';
import 'page_frame.dart';
import 'people.dart';
import 'settings.dart';
import 'widgets/chess_board.dart';

String _fmtDt(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}  ${two(d.hour)}:${two(d.minute)}';
}

/// "Turnirlar" bo'limi: turnirlar ro'yxati (nom bo'yicha tartiblangan).
class TournamentsView extends StatefulWidget {
  const TournamentsView({super.key, required this.settings, required this.pal});
  final AppSettings settings;
  final Pal pal;
  @override
  State<TournamentsView> createState() => _TournamentsViewState();
}

class _TournamentsViewState extends State<TournamentsView> {
  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);
  final _q = TextEditingController();
  Timer? _deb;
  Timer? _poll;
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _deb?.cancel();
    _poll?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (s.token == null) return;
    if (!quiet) setState(() => _loading = true);
    try {
      final r = await Api.get(
          '/tournaments?q=${Uri.encodeQueryComponent(_q.text.trim())}', s.token!);
      if (!mounted) return;
      setState(() {
        _list = ((r['tournaments'] as List?) ?? const []).cast<Map<String, dynamic>>();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? t(e.l10nKey) : t('err_network');
        _loading = false;
      });
    }
  }

  String _statusText(Map<String, dynamic> x) {
    switch (x['status']) {
      case 'running':
        return '${t('tr_running')} · ${t('tr_round')} ${x['round']}/${x['rounds']}';
      case 'finished':
        return t('tr_finished');
      default:
        return t('tr_upcoming');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColumnsView(
        padding: const EdgeInsets.all(16),
        fullFirst: true,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.emoji_events, color: pal.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(t('tr_title'),
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800, color: pal.text)),
            ),
            FilledButton.icon(
              onPressed: () async {
                final id = await Navigator.of(context).push<int>(MaterialPageRoute(
                  builder: (_) => CreateTournamentPage(settings: s, pal: pal),
                ));
                if (id != null && context.mounted) {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TournamentPage(settings: s, pal: pal, id: id),
                  ));
                }
                _load(quiet: true);
              },
              icon: const Icon(Icons.add),
              label: Text(t('tr_create')),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _q,
            onChanged: (_) {
              _deb?.cancel();
              _deb = Timer(const Duration(milliseconds: 350), () => _load(quiet: true));
            },
            decoration: InputDecoration(
              hintText: t('tr_search'),
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 4),
          Text(t('tr_sorted'), style: TextStyle(fontSize: 11.5, color: pal.subtext)),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator())),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          if (!_loading && _error == null && _list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                  child: Text(t('tr_none'), style: TextStyle(color: pal.subtext))),
            ),
          ]),
          for (final x in _list)
            Card(
              color: pal.card,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                    color: x['myStatus'] == 'invited' ? pal.accent : pal.cardBorder),
              ),
              child: ListTile(
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        TournamentPage(settings: s, pal: pal, id: (x['id'] as num).toInt()),
                  ));
                  _load(quiet: true);
                },
                title: Text('${x['name']}',
                    style: TextStyle(color: pal.text, fontWeight: FontWeight.w800)),
                subtitle: Text(
                  '${_fmtDt((x['startAt'] as num).toInt())}  ·  ${x['minutes']}+${x['inc']}  ·  '
                  '${x['rounds']} ${t('tr_rounds_short')}  ·  ${x['players']} ${t('tr_players_short')}\n'
                  '${_statusText(x)}  ·  ${(x['owner'] as Map?)?['name'] ?? ''}',
                  style: TextStyle(color: pal.subtext, height: 1.4),
                ),
                isThreeLine: true,
                trailing: x['isOwner'] == true
                    ? Icon(Icons.shield_outlined, color: pal.accent)
                    : switch (x['myStatus']) {
                        'joined' => Icon(Icons.check_circle, color: pal.accent),
                        'requested' => Icon(Icons.hourglass_top, color: pal.subtext),
                        'invited' => Icon(Icons.mail, color: pal.accent),
                        _ => null,
                      },
              ),
            ),
        ],
    );
  }
}

class CreateTournamentPage extends StatefulWidget {
  const CreateTournamentPage({super.key, required this.settings, required this.pal});
  final AppSettings settings;
  final Pal pal;
  @override
  State<CreateTournamentPage> createState() => _CreateTournamentPageState();
}

class _CreateTournamentPageState extends State<CreateTournamentPage> {
  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);
  final _name = TextEditingController();
  final _desc = TextEditingController();
  DateTime _start = DateTime.now().add(const Duration(hours: 1));
  int _min = 5;
  int _inc = 0;
  int _rounds = 5;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null || !mounted) return;
    final tm = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_start));
    if (tm == null) return;
    setState(() => _start = DateTime(d.year, d.month, d.day, tm.hour, tm.minute));
  }

  Future<void> _create() async {
    if (_name.text.trim().length < 3) {
      setState(() => _error = t('err_tour_bad_name'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await Api.post('/tournaments', s.token!, {
        'name': _name.text.trim(),
        'description': _desc.text.trim(),
        'startAt': _start.millisecondsSinceEpoch,
        'minutes': _min,
        'inc': _inc,
        'rounds': _rounds,
      });
      if (mounted) Navigator.pop(context, (r['id'] as num).toInt());
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is ApiException ? t(e.l10nKey) : t('err_network');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pal.bg1,
      appBar: AppBar(title: Text(t('tr_create'))),
      body: PageFrame(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: pal.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: pal.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _name,
                    maxLength: 60,
                    decoration: InputDecoration(
                        labelText: t('tr_name'), border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _desc,
                    maxLength: 300,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                        labelText: t('tr_desc'), border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _pickStart,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: t('tr_start'),
                        prefixIcon: const Icon(Icons.event),
                        border: const OutlineInputBorder(),
                      ),
                      child: Text(_fmtDt(_start.millisecondsSinceEpoch),
                          style: TextStyle(color: pal.text, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TimeControlPicker(
                    pal: pal,
                    lang: s.lang,
                    minutes: _min,
                    inc: _inc,
                    onChanged: (m, i) => setState(() {
                      _min = m;
                      _inc = i;
                    }),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Text('${t('tr_rounds')}: $_rounds',
                        style: TextStyle(color: pal.text, fontWeight: FontWeight.w700)),
                    Expanded(
                      child: Slider(
                        value: _rounds.toDouble(),
                        min: 1,
                        max: 11,
                        divisions: 10,
                        label: '$_rounds',
                        onChanged: (v) => setState(() => _rounds = v.round()),
                      ),
                    ),
                  ]),
                  Text(t('tr_swiss_hint'),
                      style: TextStyle(fontSize: 11.5, color: pal.subtext)),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.emoji_events),
              label: Text(t('tr_create')),
            ),
          ],
        ),
      ),
    );
  }
}

class TournamentPage extends StatefulWidget {
  const TournamentPage(
      {super.key, required this.settings, required this.pal, required this.id});
  final AppSettings settings;
  final Pal pal;
  final int id;
  @override
  State<TournamentPage> createState() => _TournamentPageState();
}

class _TournamentPageState extends State<TournamentPage> {
  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);
  Map<String, dynamic>? _d;
  String? _error;
  Timer? _poll;
  final _inviteCtl = TextEditingController();
  String? _openedGame;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _inviteCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/tournaments/${widget.id}', s.token!);
      if (!mounted) return;
      setState(() {
        _d = r;
        _error = null;
      });
      final gid = r['myGameId']?.toString();
      if (gid != null && gid != _openedGame && !DuelWatcher.inGame) {
        _openedGame = gid;
        await openDuelGame(context, s, pal, gid);
      }
    } catch (e) {
      if (!mounted) return;
      if (_d == null) {
        setState(() => _error = e is ApiException ? t(e.l10nKey) : t('err_network'));
      }
    }
  }

  Future<void> _act(String path, [Map<String, dynamic> body = const {}]) async {
    try {
      await Api.post('/tournaments/${widget.id}/$path', s.token!, body);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t(e.l10nKey))));
      }
    }
  }

  Widget _card(Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: pal.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: pal.cardBorder),
        ),
        child: child,
      );

  Widget _h(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: pal.text)),
      );

  String _res(String r) => r == 'bye'
      ? t('tr_bye')
      : (r == '' ? '…' : (r == '0-0' ? '–' : r));

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final tt = (d?['tournament'] as Map?)?.cast<String, dynamic>();
    return Scaffold(
      backgroundColor: pal.bg1,
      appBar: AppBar(title: Text(tt == null ? t('tr_title') : '${tt['name']}')),
      body: PageFrame(
        child: _error != null
            ? Center(child: Text(_error!, style: TextStyle(color: pal.text)))
            : (d == null || tt == null)
                ? const Center(child: CircularProgressIndicator())
                : _body(d, tt),
      ),
    );
  }

  Widget _body(Map<String, dynamic> d, Map<String, dynamic> tt) {
    final isOwner = tt['isOwner'] == true;
    final status = '${tt['status']}';
    final my = tt['myStatus'];
    final owner = (tt['owner'] as Map?)?.cast<String, dynamic>();
    final standings = ((d['standings'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final rounds = ((d['rounds'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final requests = ((d['requests'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final invited = ((d['invited'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final myGame = d['myGameId']?.toString();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${tt['name']}',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900, color: pal.text)),
            if ('${tt['description']}'.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('${tt['description']}', style: TextStyle(color: pal.text, height: 1.4)),
            ],
            const SizedBox(height: 10),
            Text(
              '${t('tr_start')}: ${_fmtDt((tt['startAt'] as num).toInt())}\n'
              '${t('du_time')}: ${tt['minutes']}+${tt['inc']}   ·   ${t('tr_rounds')}: ${tt['rounds']}\n'
              '${t('tr_organizer')}: ${owner?['name'] ?? ''}\n'
              '${status == 'running' ? '${t('tr_running')} · ${t('tr_round')} ${tt['round']}/${tt['rounds']}' : (status == 'finished' ? t('tr_finished') : t('tr_upcoming'))}',
              style: TextStyle(color: pal.subtext, height: 1.5),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (!isOwner && status == 'upcoming' && (my == null || my == 'declined'))
                FilledButton.icon(
                  onPressed: () => _act('join'),
                  icon: const Icon(Icons.how_to_reg),
                  label: Text(t('tr_join_req')),
                ),
              if (!isOwner && my == 'requested')
                OutlinedButton.icon(
                  onPressed: () => _act('leave'),
                  icon: const Icon(Icons.hourglass_top),
                  label: Text(t('tr_req_sent')),
                ),
              if (!isOwner && my == 'invited') ...[
                FilledButton.icon(
                  onPressed: () => _act('join'),
                  icon: const Icon(Icons.check),
                  label: Text(t('tr_accept_invite')),
                ),
                OutlinedButton(
                  onPressed: () => _act('leave'),
                  child: Text(t('du_decline')),
                ),
              ],
              if (!isOwner && my == 'joined' && status == 'upcoming')
                OutlinedButton(
                  onPressed: () => _act('leave'),
                  child: Text(t('tr_leave')),
                ),
              if (!isOwner && owner != null)
                OutlinedButton.icon(
                  onPressed: () => openChatWith(context, s, pal,
                      userId: (owner['id'] as num).toInt(), name: '${owner['name']}'),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: Text(t('tr_chat_org')),
                ),
              if (isOwner && status == 'upcoming')
                FilledButton.icon(
                  onPressed: () => _act('start'),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(t('tr_start_now')),
                ),
              if (isOwner && status == 'upcoming')
                OutlinedButton(
                  onPressed: () async {
                    await _act('cancel');
                    if (mounted && _d == null) Navigator.pop(context);
                  },
                  child: Text(t('tr_cancel')),
                ),
              if (myGame != null)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                  onPressed: () => openDuelGame(context, s, pal, myGame),
                  icon: const Icon(Icons.sports_esports),
                  label: Text(t('tr_open_game')),
                ),
            ]),
            if (status == 'running' && tt['nextRoundAt'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(t('tr_next_round_soon'),
                    style: TextStyle(color: pal.accent, fontWeight: FontWeight.w700)),
              ),
          ],
        )),
        if (isOwner && status == 'upcoming') ...[
          _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _h(t('tr_requests')),
              if (requests.isEmpty)
                Text(t('tr_no_requests'), style: TextStyle(color: pal.subtext)),
              for (final u in requests)
                Row(children: [
                  Expanded(
                    child: Text('${u['name']}  (${u['rating']})',
                        style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    tooltip: t('ch_title'),
                    onPressed: () => openChatWith(context, s, pal,
                        userId: (u['id'] as num).toInt(), name: '${u['name']}'),
                    icon: Icon(Icons.chat_bubble_outline, color: pal.subtext),
                  ),
                  IconButton(
                    tooltip: t('du_decline'),
                    onPressed: () => _act('respond', {'userId': u['id'], 'accept': false}),
                    icon: const Icon(Icons.close, color: Colors.redAccent),
                  ),
                  IconButton(
                    tooltip: t('du_accept'),
                    onPressed: () => _act('respond', {'userId': u['id'], 'accept': true}),
                    icon: const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
                  ),
                ]),
              const Divider(height: 24),
              _h(t('tr_invite')),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _inviteCtl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: t('du_opp_id'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    final id = _inviteCtl.text.trim();
                    if (id.isEmpty) return;
                    await _act('invite', {'publicId': id});
                    _inviteCtl.clear();
                  },
                  child: Text(t('tr_invite_btn')),
                ),
              ]),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: PeopleSearchButton(
                  settings: s,
                  pal: pal,
                  onPick: (u) => setState(() => _inviteCtl.text = '${u['publicId']}'),
                ),
              ),
              if (invited.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('${t('tr_invited')}: ${invited.map((u) => u['name']).join(', ')}',
                    style: TextStyle(color: pal.subtext, fontSize: 12.5)),
              ],
            ],
          )),
        ],
        _card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _h('${t('tr_standings')} (${standings.length})'),
            for (final r in standings)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(
                    width: 28,
                    child: Text('${r['rank']}',
                        style: TextStyle(color: pal.subtext, fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    child: Text('${r['name']}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
                  ),
                  Text('${r['rating']}',
                      style: TextStyle(color: pal.subtext, fontSize: 12.5)),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 64,
                    child: Text(
                      '${(r['score'] as num) % 1 == 0 ? (r['score'] as num).toInt() : r['score']}'
                      '  (${(r['buchholz'] as num) % 1 == 0 ? (r['buchholz'] as num).toInt() : r['buchholz']})',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: pal.accent, fontWeight: FontWeight.w800),
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 4),
            Text(t('tr_tiebreak'), style: TextStyle(fontSize: 11.5, color: pal.subtext)),
          ],
        )),
        for (final r in rounds.reversed)
          _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _h('${t('tr_round')} ${r['round']}'),
              for (final p in ((r['pairings'] as List).cast<Map<String, dynamic>>()))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        '${(p['white'] as Map)['name']}  –  ${p['black'] == null ? t('tr_bye') : (p['black'] as Map)['name']}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: pal.text),
                      ),
                    ),
                    Text(_res('${p['result']}'),
                        style: TextStyle(
                            color: pal.accent, fontWeight: FontWeight.w800)),
                  ]),
                ),
            ],
          )),
      ],
    );
  }
}
