import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import 'api.dart';
import 'game_viewer.dart';
import 'games_data.dart';
import 'l10n.dart';
import 'openings.dart';
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
    final token = s.token;
    if (token == null || _busy) return;
    setState(() => _busy = true);
    try {
      final res = await Api.get(
        '/materials/${m['id']}/file',
        token,
        timeout: const Duration(seconds: 90),
      );
      final bytes = base64Decode(res['data'] as String);
      final kind = res['kind'] as String;
      final title = (res['title'] as String?) ?? '';
      if (kind == 'pgn') {
        final text = utf8.decode(bytes, allowMalformed: true);
        if (!mounted) return;
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
            '${Directory.systemTemp.path}${Platform.pathSeparator}achess_material_${m['id']}.pdf';
        await File(path).writeAsBytes(bytes, flush: true);
        final r = await OpenFilex.open(path);
        if (r.type != ResultType.done) _snack(t('ls_pdf_fail'));
      }
    } catch (e) {
      _snack(_err(e));
    }
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

  Widget _gamesCard() {
    final q = _gq.trim().toLowerCase();
    final ids = <int>[];
    for (var i = 0; i < kGameData.length; i++) {
      if (q.isEmpty) {
        ids.add(i);
      } else {
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
          const SizedBox(height: 8),
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
            Text(t('ls_intro'), style: TextStyle(color: pal.subtext)),
            const SizedBox(height: 12),
            _materialsCard(),
            _gamesCard(),
          ],
        ),
      ),
    );
  }
}
