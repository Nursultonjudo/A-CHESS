import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'page_frame.dart';
import 'package:open_filex/open_filex.dart';

import 'api.dart';
import 'game_viewer.dart';
import 'games_data.dart';
import 'l10n.dart';
import 'openings.dart';
import 'pgn.dart';
import 'settings.dart';
import 'widgets/chess_board.dart';

String _fmtSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

String _fmtDate(Object? ms) {
  if (ms is! num) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
  String two(int x) => x.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// Materialni serverdan olib ochadi: PGN — tahlil sahifasida, PDF — tizim
/// PDF dasturida. Xato bo'lsa, foydalanuvchiga ko'rsatiladigan matnni qaytaradi.
Future<String?> openMaterialFile(
  BuildContext context,
  AppSettings s,
  Pal pal,
  int id,
) async {
  final token = s.token;
  if (token == null) return tr(s.lang, 'err_network');
  try {
    final res = await Api.get(
      '/materials/$id/file',
      token,
      timeout: const Duration(seconds: 90),
    );
    final bytes = base64Decode(res['data'] as String);
    final kind = res['kind'] as String;
    final title = (res['title'] as String?) ?? '';
    if (kind == 'pgn') {
      final text = utf8.decode(bytes, allowMalformed: true);
      if (!context.mounted) return null;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PgnDatabasePage(
          settings: s,
          pal: pal,
          initialText: text,
          initialName: title,
        ),
      ));
    } else {
      final path =
          '${Directory.systemTemp.path}${Platform.pathSeparator}achess_material_$id.pdf';
      await File(path).writeAsBytes(bytes, flush: true);
      final r = await OpenFilex.open(path);
      if (r.type != ResultType.done) return tr(s.lang, 'ls_pdf_fail');
    }
    return null;
  } catch (e) {
    return e is ApiException ? tr(s.lang, e.l10nKey) : tr(s.lang, 'err_network');
  }
}

/// "Darsliklar": trener materiallari (PGN / PDF), PGN fayl ochish va
/// namunaviy partiyalar.
class LessonsView extends StatefulWidget {
  const LessonsView({super.key, required this.settings, required this.pal});
  final AppSettings settings;
  final Pal pal;

  @override
  State<LessonsView> createState() => _LessonsViewState();
}

class _LessonsViewState extends State<LessonsView> {
  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);

  List<Map<String, dynamic>> _mats = [];
  List<Map<String, dynamic>> _students = [];
  bool _loading = false;
  bool _busy = false;
  String _error = '';

  final _gctl = TextEditingController();
  String _gq = '';
  int _gShown = 40;
  int _gMode = 0; // 0 ochilish, 1 o'yinchi, 2 davr, 3 natija
  final Map<int, List<MapEntry<String, List<int>>>> _groupCache = {};
  final Map<String, int> _groupShown = {};

  bool get _isCoach => s.role == 'coach';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _gctl.dispose();
    super.dispose();
  }

  String _err(Object e) =>
      e is ApiException ? tr(s.lang, e.l10nKey) : tr(s.lang, 'err_network');

  Future<void> _load() async {
    final token = s.token;
    if (token == null || s.role == null) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      if (_isCoach) {
        final m = await Api.get('/coach/materials', token);
        final st = await Api.get('/coach/students', token);
        _mats = (m['materials'] as List).cast<Map<String, dynamic>>();
        _students = (st['students'] as List).cast<Map<String, dynamic>>();
      } else {
        final m = await Api.get('/me/materials', token);
        _mats = (m['materials'] as List).cast<Map<String, dynamic>>();
      }
    } catch (e) {
      _error = _err(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---- Materialni ochish ------------------------------------------------------

  Future<void> _open(Map<String, dynamic> m) async {
    if (_busy) return;
    setState(() => _busy = true);
    final err = await openMaterialFile(
      context,
      s,
      pal,
      (m['id'] as num).toInt(),
    );
    if (err != null) _snack(err);
    if (mounted) setState(() => _busy = false);
  }

  // ---- Trener: yuklash va biriktirish ------------------------------------------

  /// Sarlavha, izoh va o'quvchilarni tanlash oynasi.
  Future<({String title, String note, List<int> ids})?> _dialog({
    required String heading,
    required String title,
    required bool askTitle,
    required List<int> selected,
    required String okLabel,
  }) async {
    final tctl = TextEditingController(text: title);
    final nctl = TextEditingController();
    final ids = {...selected};
    final res = await showDialog<({String title, String note, List<int> ids})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Dialog(
          backgroundColor: pal.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: pal.cardBorder),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    heading,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: pal.text,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (askTitle) ...[
                    TextField(
                      controller: tctl,
                      decoration:
                          InputDecoration(labelText: t('ls_title_label')),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: nctl,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: t('ls_note_label')),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t('ls_who', {'n': '${ids.length}'}),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: pal.text,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setSt(() {
                          ids
                            ..clear()
                            ..addAll(
                                _students.map((x) => (x['id'] as num).toInt()));
                        }),
                        child: Text(t('co_all')),
                      ),
                      TextButton(
                        onPressed: () => setSt(ids.clear),
                        child: Text(t('ls_none')),
                      ),
                    ],
                  ),
                  if (_students.isEmpty)
                    Text(t('co_no_students'),
                        style: TextStyle(color: pal.subtext))
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final st in _students)
                          FilterChip(
                            label: Text(st['name'] as String),
                            selected: ids.contains((st['id'] as num).toInt()),
                            onSelected: (v) => setSt(() {
                              final id = (st['id'] as num).toInt();
                              v ? ids.add(id) : ids.remove(id);
                            }),
                          ),
                      ],
                    ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(t('co_cancel')),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () {
                          if (askTitle && tctl.text.trim().isEmpty) return;
                          Navigator.of(ctx).pop((
                            title: tctl.text.trim(),
                            note: nctl.text.trim(),
                            ids: ids.toList(),
                          ));
                        },
                        child: Text(okLabel),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    tctl.dispose();
    nctl.dispose();
    return res;
  }

  Future<void> _upload() async {
    final token = s.token;
    if (token == null || _busy) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pgn', 'pdf'],
        withData: true,
      );
      final f = picked?.files.single;
      if (f == null) return;
      Uint8List? bytes = f.bytes;
      if (bytes == null && f.path != null) {
        bytes = await File(f.path!).readAsBytes();
      }
      if (bytes == null) return;
      if (bytes.length > 20 * 1024 * 1024) {
        _snack(t('err_too_large'));
        return;
      }
      final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
      final kind = ext == 'pdf' ? 'pdf' : 'pgn';
      final base = f.name.contains('.')
          ? f.name.substring(0, f.name.lastIndexOf('.'))
          : f.name;
      if (!mounted) return;
      final r = await _dialog(
        heading: t('ls_upload'),
        title: base,
        askTitle: true,
        selected: const [],
        okLabel: t('ls_upload_btn'),
      );
      if (r == null) return;
      setState(() => _busy = true);
      await Api.post(
        '/coach/materials',
        token,
        {
          'title': r.title,
          'kind': kind,
          'filename': f.name,
          'data': base64Encode(bytes),
          'studentIds': r.ids,
          'note': r.note,
        },
        timeout: const Duration(seconds: 120),
      );
      _snack(t('ls_uploaded'));
      await _load();
    } catch (e) {
      _snack(_err(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _assign(Map<String, dynamic> m) async {
    final token = s.token;
    if (token == null) return;
    final cur = ((m['studentIds'] as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    final r = await _dialog(
      heading: t('ls_assign_title', {'t': '${m['title']}'}),
      title: '',
      askTitle: false,
      selected: cur,
      okLabel: t('save'),
    );
    if (r == null) return;
    try {
      await Api.post('/coach/materials/${m['id']}/assign', token, {
        'studentIds': r.ids,
        'note': r.note,
      });
      _snack(t('ls_saved'));
      await _load();
    } catch (e) {
      _snack(_err(e));
    }
  }

  Future<void> _delete(Map<String, dynamic> m) async {
    final token = s.token;
    if (token == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('ls_delete_q')),
        content: Text('${m['title']}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('co_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('co_delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.post('/coach/materials/${m['id']}/delete', token, {});
      await _load();
    } catch (e) {
      _snack(_err(e));
    }
  }

  // ---- UI ---------------------------------------------------------------------

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: pal.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: pal.cardBorder),
        ),
        child: child,
      );

  Widget _materialTile(Map<String, dynamic> m) {
    final pdf = m['kind'] == 'pdf';
    final assigned = ((m['studentIds'] as List?) ?? const []).length;
    final sub = <String>[
      pdf ? 'PDF' : 'PGN',
      _fmtSize((m['size'] as num?)?.toInt() ?? 0),
      _fmtDate(m['assignedAt'] ?? m['createdAt']),
      if (_isCoach)
        (assigned == 0
            ? t('ls_not_assigned')
            : t('ls_assigned_n', {'n': '$assigned'}))
      else if ((m['coachName'] as String?)?.isNotEmpty ?? false)
        t('ls_from_coach', {'n': m['coachName'] as String}),
    ].where((x) => x.isNotEmpty).join(' · ');
    final note = (m['note'] as String?) ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: pal.bg1,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _busy ? null : () => _open(m),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: pal.cardBorder),
            ),
            child: Row(
              children: [
                Icon(
                  pdf ? Icons.picture_as_pdf : Icons.table_chart_outlined,
                  color: pdf ? const Color(0xFFE53935) : pal.accent,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${m['title']}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: pal.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(sub,
                          style:
                              TextStyle(fontSize: 12.5, color: pal.subtext)),
                      if (note.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(note,
                            style: TextStyle(
                                fontSize: 13, color: pal.text)),
                      ],
                    ],
                  ),
                ),
                if (_isCoach)
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'assign') _assign(m);
                      if (v == 'delete') _delete(m);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'assign',
                        child: Text(t('ls_assign')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(t('co_delete')),
                      ),
                    ],
                  )
                else
                  Icon(Icons.chevron_right, color: pal.subtext),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _materialsCard() {
    if (s.role == null) {
      return _card(
        child: Text(t('ls_pick_role'), style: TextStyle(color: pal.subtext)),
      );
    }
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.school, color: pal.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isCoach ? t('ls_my_materials') : t('ls_received'),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: pal.text,
                  ),
                ),
              ),
              IconButton(
                tooltip: t('ls_refresh'),
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
              if (_isCoach)
                FilledButton.icon(
                  onPressed: _busy ? null : _upload,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: Text(t('ls_upload')),
                ),
            ],
          ),
          if (_isCoach) ...[
            const SizedBox(height: 4),
            Text(t('ls_coach_hint'),
                style: TextStyle(fontSize: 12.5, color: pal.subtext)),
          ],
          const SizedBox(height: 10),
          if (_loading || _busy) const LinearProgressIndicator(),
          if (_error.isNotEmpty)
            Text(_error, style: const TextStyle(color: Colors.redAccent)),
          if (!_loading && _error.isEmpty && _mats.isEmpty)
            Text(
              _isCoach ? t('ls_empty_coach') : t('ls_empty_student'),
              style: TextStyle(color: pal.subtext),
            ),
          const SizedBox(height: 4),
          for (final m in _mats) _materialTile(m),
        ],
      ),
    );
  }

  // ---- Namunaviy partiyalarni guruhlash ----------------------------------

  static String _ecoGroup(String eco) {
    if (eco.length < 3) return 'ZZ';
    final l = eco[0].toUpperCase();
    final n = int.tryParse(eco.substring(1, 3)) ?? -1;
    if (n < 0 || !'ABCDE'.contains(l)) return 'ZZ';
    String r(int a, int b, String name) =>
        '$l${a.toString().padLeft(2, '0')}–$l${b.toString().padLeft(2, '0')}  $name';
    switch (l) {
      case 'A':
        if (n <= 3) return r(0, 3, "Uncommon openings, Bird, Polish");
        if (n <= 9) return r(4, 9, "Réti, Zukertort, King's Indian Attack");
        if (n <= 39) return r(10, 39, 'English Opening');
        if (n <= 44) return r(40, 44, "Queen's pawn, Old Benoni, Modern Benoni setups");
        if (n <= 49) return r(45, 49, 'Indian systems (London, Trompowsky, Torre)');
        if (n <= 79) return r(50, 79, 'Benoni, Benko Gambit, Budapest, Old Indian');
        return r(80, 99, 'Dutch Defence');
      case 'B':
        if (n <= 9) return r(0, 9, 'Scandinavian, Alekhine, Pirc, Modern');
        if (n <= 19) return r(10, 19, 'Caro-Kann Defence');
        if (n <= 49) return r(20, 49, 'Sicilian: Alapin, Closed, Taimanov, Kan');
        return r(50, 99, 'Sicilian: Najdorf, Dragon, Scheveningen, Sveshnikov');
      case 'C':
        if (n <= 19) return r(0, 19, 'French Defence');
        if (n <= 29) return r(20, 29, "Open games, Vienna, Center Game");
        if (n <= 39) return r(30, 39, "King's Gambit");
        if (n <= 49) return r(40, 49, 'Petroff, Scotch, Philidor, Four Knights');
        if (n <= 59) return r(50, 59, 'Italian Game, Two Knights');
        return r(60, 99, 'Ruy Lopez (Spanish)');
      case 'D':
        if (n <= 5) return r(0, 5, "Queen's pawn, London, Colle");
        if (n <= 9) return r(6, 9, "Queen's Gambit: Albin, Chigorin, Marshall");
        if (n <= 19) return r(10, 19, 'Slav Defence');
        if (n <= 29) return r(20, 29, "Queen's Gambit Accepted");
        if (n <= 69) return r(30, 69, "Queen's Gambit Declined");
        return r(70, 99, 'Grünfeld Defence');
      default:
        if (n <= 9) return r(0, 9, 'Catalan Opening');
        if (n <= 19) return r(10, 19, "Queen's Indian, Bogo-Indian");
        if (n <= 59) return r(20, 59, 'Nimzo-Indian Defence');
        return r(60, 99, "King's Indian Defence");
    }
  }

  List<MapEntry<String, List<int>>> _groups(int mode) {
    return _groupCache.putIfAbsent(mode, () {
      final map = <String, List<int>>{};
      Map<String, int>? counts;
      if (mode == 1) {
        counts = {};
        for (final row in kGameData) {
          final p = row.split('|');
          counts[p[0]] = (counts[p[0]] ?? 0) + 1;
          counts[p[1]] = (counts[p[1]] ?? 0) + 1;
        }
      }
      for (var i = 0; i < kGameData.length; i++) {
        final p = kGameData[i].split('|');
        String key;
        switch (mode) {
          case 0:
            key = _ecoGroup(p[6]);
          case 1:
            final cn = counts!;
            final a = cn[p[0]] ?? 0;
            final b = cn[p[1]] ?? 0;
            final top = a >= b ? p[0] : p[1];
            key = (cn[top] ?? 0) >= 8 ? top : 'ZZ';
          case 2:
            final y = int.tryParse(p[4].length >= 4 ? p[4].substring(0, 4) : '');
            key = y == null ? 'ZZ' : '${y ~/ 10 * 10}–${y ~/ 10 * 10 + 9}';
          default:
            key = p[5] == '1-0'
                ? 'A'
                : (p[5] == '0-1' ? 'B' : (p[5] == '1/2-1/2' ? 'C' : 'ZZ'));
        }
        (map[key] ??= []).add(i);
      }
      final list = map.entries.toList();
      if (mode == 1) {
        list.sort((a, b) {
          if (a.key == 'ZZ') return 1;
          if (b.key == 'ZZ') return -1;
          return b.value.length.compareTo(a.value.length);
        });
      } else {
        list.sort((a, b) => a.key.compareTo(b.key));
      }
      return list;
    });
  }

  String _groupTitle(int mode, String key) {
    if (key == 'ZZ') return mode == 2 ? t('ls_unknown') : t('ls_others');
    if (mode == 3) {
      return key == 'A'
          ? t('ls_res_w')
          : (key == 'B' ? t('ls_res_b') : t('ls_res_d'));
    }
    return key;
  }

  Widget _modeChips() {
    final names = [
      t('ls_g_open'),
      t('ls_g_player'),
      t('ls_g_era'),
      t('ls_g_result'),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < names.length; i++)
          ChoiceChip(
            label: Text(names[i]),
            selected: _gMode == i,
            selectedColor: pal.accent.withAlpha(0x55),
            onSelected: (_) => setState(() => _gMode = i),
          ),
      ],
    );
  }

  Widget _groupTile(String key, List<int> ids) {
    final gk = '$_gMode:$key';
    final shown = _groupShown[gk] ?? 30;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pal.cardBorder),
        color: pal.bg1.withAlpha(0x66),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          _groupTitle(_gMode, key),
          style: TextStyle(fontWeight: FontWeight.w800, color: pal.text),
        ),
        subtitle: Text(
          t('db_games', {'n': '${ids.length}'}),
          style: TextStyle(fontSize: 12.5, color: pal.subtext),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        children: [
          for (final i in ids.take(shown)) _gameTile(gameById(i)),
          if (ids.length > shown)
            TextButton(
              onPressed: () => setState(() => _groupShown[gk] = shown + 30),
              child: Text(t('ls_show_more')),
            ),
        ],
      ),
    );
  }

  Widget _gamesCard() {
    final q = _gq.trim().toLowerCase();
    final searching = q.isNotEmpty;
    final ids = <int>[];
    if (searching) {
      for (var i = 0; i < kGameData.length; i++) {
        final row = kGameData[i];
        final head = row.substring(0, row.lastIndexOf('|')).toLowerCase();
        if (head.contains(q)) ids.add(i);
      }
    }
    final shown = ids.take(_gShown).toList();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sports_esports_outlined, color: pal.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t('ls_games_title'),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: pal.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(t('ls_games_hint'),
              style: TextStyle(fontSize: 12.5, color: pal.subtext)),
          const SizedBox(height: 10),
          TextField(
            controller: _gctl,
            onChanged: (v) => setState(() {
              _gq = v;
              _gShown = 40;
            }),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: t('db_filter'),
              suffixIcon: _gq.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _gctl.clear();
                        _gq = '';
                      }),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          if (!searching) ...[
            _modeChips(),
            const SizedBox(height: 10),
            for (final e in _groups(_gMode)) _groupTile(e.key, e.value),
          ] else ...[
            Text(
              t('db_games', {'n': '${ids.length}'}),
              style: TextStyle(fontWeight: FontWeight.w700, color: pal.text),
            ),
            const SizedBox(height: 8),
            for (final i in shown) _gameTile(gameById(i)),
            if (ids.length > shown.length)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _gShown += 40),
                  child: Text(t('ls_show_more')),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ---- O'yinchining o'zi saqlagan partiyalari -----------------------------

  // ---- Shaxsiy partiyalar: PGN yuklash va tahrirlash ----------------------------

  Future<void> _importPgn() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pgn'],
        withData: true,
      );
      final f = picked?.files.single;
      if (f == null) return;
      Uint8List? bytes = f.bytes;
      if (bytes == null && f.path != null) {
        bytes = await File(f.path!).readAsBytes();
      }
      if (bytes == null) return;
      final text = utf8.decode(bytes, allowMalformed: true);
      final games = parsePgn(text);
      if (games.isEmpty) {
        _snack(t('ls_pgn_empty'));
        return;
      }
      final base = DateTime.now().millisecondsSinceEpoch;
      final list = <Map<String, dynamic>>[];
      for (var i = 0; i < games.length && i < 200; i++) {
        final g = games[i];
        list.add({
          'id': base + i,
          'date': g.date.isEmpty ? '?' : g.date,
          'white': g.white,
          'black': g.black,
          'result': g.res,
          'moves': g.sans.length,
          'pgn': g.toPgn(),
        });
      }
      await s.addSavedGames(list);
      _snack(t('ls_pgn_added', {'n': '${list.length}'}));
    } catch (_) {
      _snack(t('ls_pgn_empty'));
    }
  }

  Future<void> _editGame(Map<String, dynamic> g) async {
    final wc = TextEditingController(text: '${g['white']}');
    final bc = TextEditingController(text: '${g['black']}');
    final dc = TextEditingController(text: '${g['date']}');
    final rc = TextEditingController(text: '${g['result']}');
    final pc = TextEditingController(text: '${g['pgn']}');
    String err = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: pal.card,
          title: Text(t('ls_edit')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: wc,
                      decoration: InputDecoration(labelText: t('white'))),
                  TextField(
                      controller: bc,
                      decoration: InputDecoration(labelText: t('black'))),
                  TextField(
                      controller: dc,
                      decoration: InputDecoration(labelText: t('ls_date'))),
                  TextField(
                      controller: rc,
                      decoration: InputDecoration(labelText: t('ls_result'))),
                  const SizedBox(height: 8),
                  TextField(
                    controller: pc,
                    minLines: 5,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      labelText: 'PGN',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (err.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(err,
                          style: const TextStyle(color: Colors.redAccent)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t('co_cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (parsePgn(pc.text).isEmpty) {
                  setSt(() => err = t('ls_pgn_empty'));
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              child: Text(t('save')),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      final parsed = parsePgn(pc.text).first;
      final w = wc.text.trim().isEmpty ? '?' : wc.text.trim();
      final b = bc.text.trim().isEmpty ? '?' : bc.text.trim();
      final d = dc.text.trim().isEmpty ? '?' : dc.text.trim();
      final r = rc.text.trim().isEmpty ? '*' : rc.text.trim();
      final headers = {
        ...parsed.headers,
        'White': w,
        'Black': b,
        'Date': d,
        'Result': r,
      };
      await s.updateSavedGame({
        ...g,
        'white': w,
        'black': b,
        'date': d,
        'result': r,
        'moves': parsed.sans.length,
        'pgn': buildPgn(headers, parsed.sans, r),
      });
    }
    wc.dispose();
    bc.dispose();
    dc.dispose();
    rc.dispose();
    pc.dispose();
  }

  // ---- Shaxsiy fayllar: PGN, PDF, DJVU -------------------------------------------

  Future<void> _addMyFile() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pgn', 'pdf', 'djvu', 'djv'],
      );
      final f = picked?.files.single;
      if (f == null || f.path == null) return;
      final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
      final base = f.name.contains('.')
          ? f.name.substring(0, f.name.lastIndexOf('.'))
          : f.name;
      await s.addMyFile({
        'id': DateTime.now().millisecondsSinceEpoch,
        'name': base,
        'path': f.path,
        'kind': ext == 'djv' ? 'djvu' : ext,
      });
    } catch (_) {
      _snack(t('err_network'));
    }
  }

  Future<void> _openMyFile(Map<String, dynamic> f) async {
    final path = '${f['path']}';
    if (!File(path).existsSync()) {
      _snack(t('ls_file_missing'));
      return;
    }
    if (f['kind'] == 'pgn') {
      final text = utf8.decode(await File(path).readAsBytes(), allowMalformed: true);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PgnDatabasePage(
          settings: s,
          pal: pal,
          initialText: text,
          initialName: '${f['name']}',
        ),
      ));
    } else {
      final r = await OpenFilex.open(path);
      if (r.type != ResultType.done) _snack(t('ls_pdf_fail'));
    }
  }

  Future<void> _renameMyFile(Map<String, dynamic> f) async {
    final c = TextEditingController(text: '${f['name']}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: pal.card,
        title: Text(t('ls_edit')),
        content: TextField(controller: c),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t('co_cancel'))),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t('save'))),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      await s.renameMyFile((f['id'] as num).toInt(), c.text.trim());
    }
    c.dispose();
  }

  Widget _myFilesCard() {
    final list = s.myFiles;
    IconData icon(String k) => k == 'pgn'
        ? Icons.description_outlined
        : (k == 'pdf' ? Icons.picture_as_pdf_outlined : Icons.menu_book_outlined);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_open, color: pal.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t('ls_my_files'),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: pal.text,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _addMyFile,
                icon: const Icon(Icons.add, size: 18),
                label: Text(t('ls_add_file')),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            list.isEmpty ? t('ls_no_files') : t('ls_my_files_hint'),
            style: TextStyle(fontSize: 12.5, color: pal.subtext),
          ),
          for (final f in list)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(icon('${f['kind']}'), color: pal.accent),
              title: Text('${f['name']}',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: pal.text)),
              subtitle: Text('${f['kind']}'.toUpperCase(),
                  style: TextStyle(fontSize: 12, color: pal.subtext)),
              onTap: () => _openMyFile(f),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: t('ls_edit'),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => _renameMyFile(f),
                  ),
                  IconButton(
                    tooltip: t('co_delete'),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => s.deleteMyFile((f['id'] as num).toInt()),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _savedCard() {
    final list = s.savedGames;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bookmark_added_outlined, color: pal.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t('ls_my_games'),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: pal.text,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _importPgn,
                icon: const Icon(Icons.upload_file, size: 18),
                label: Text(t('ls_pgn_upload')),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            list.isEmpty ? t('ls_no_saved') : t('ls_my_games_hint'),
            style: TextStyle(fontSize: 12.5, color: pal.subtext),
          ),
          const SizedBox(height: 8),
          for (final g in list.take(50))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: pal.bg1,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    final games = parsePgn('${g['pgn']}');
                    if (games.isEmpty) return;
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => GameViewerPage(
                        settings: s,
                        pal: pal,
                        game: games.first,
                      ),
                    ));
                  },
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
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
                                '${g['white']} – ${g['black']}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: pal.text,
                                ),
                              ),
                              Text(
                                '${g['date']}  ·  ${g['moves']} ${t('ls_moves')}',
                                style: TextStyle(
                                    fontSize: 12.5, color: pal.subtext),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${g['result']}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: pal.accent,
                          ),
                        ),
                        IconButton(
                          tooltip: t('ls_edit'),
                          onPressed: () => _editGame(g),
                          icon: Icon(Icons.edit_outlined,
                              size: 20, color: pal.subtext),
                        ),
                        IconButton(
                          tooltip: t('co_delete'),
                          onPressed: () =>
                              s.deleteSavedGame((g['id'] as num).toInt()),
                          icon: Icon(Icons.delete_outline,
                              size: 20, color: pal.subtext),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _gameTile(GameRec g) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: pal.bg1,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GameViewerPage(
                  settings: s,
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
                            if (g.eco.isNotEmpty) g.eco,
                          ].join(' · '),
                          style:
                              TextStyle(fontSize: 12.5, color: pal.subtext),
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

  @override
  Widget build(BuildContext context) {
    return ColumnsView(
          padding: const EdgeInsets.all(16),
          fullFirst: true,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            Text(t('ls_intro'), style: TextStyle(color: pal.subtext)),
            ]),
            const SizedBox(height: 12),
            _materialsCard(),
            ListenableBuilder(listenable: s, builder: (_, __) => _savedCard()),
            ListenableBuilder(listenable: s, builder: (_, __) => _myFilesCard()),
            _gamesCard(),
          ],
        );
  }
}
