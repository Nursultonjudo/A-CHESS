import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'l10n.dart';
import 'puzzle_maker.dart';
import 'puzzles.dart';
import 'settings.dart';
import 'widgets/chess_board.dart';

String _msg(AppSettings s, Object e) =>
    e is ApiException ? tr(s.lang, e.l10nKey) : tr(s.lang, 'err_network');

/// Birinchi kirishda rolni tanlash: o'quvchi yoki trener.
Future<void> showRoleDialog(
  BuildContext context,
  AppSettings s,
  Pal pal,
) async {
  final token = s.token;
  if (token == null) return;
  String t(String k) => tr(s.lang, k);
  var coach = false;
  final ctl = TextEditingController();
  String? error;
  var busy = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Widget choice(bool isCoach, IconData icon, String label) {
          final sel = coach == isCoach;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() {
                coach = isCoach;
                ctl.clear();
                error = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: sel ? pal.accentSoft : null,
                  border: Border.all(
                    color: sel ? pal.accent : pal.cardBorder,
                    width: sel ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(icon, size: 30, color: sel ? pal.accent : pal.subtext),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: pal.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        Future<void> submit() async {
          setState(() {
            busy = true;
            error = null;
          });
          try {
            Map<String, dynamic> res;
            if (coach) {
              res = await Api.post('/me/role', token, {
                'role': 'coach',
                'secret': ctl.text.trim(),
              });
            } else {
              final code = ctl.text.trim();
              res = code.isEmpty
                  ? await Api.post('/me/role', token, {'role': 'student'})
                  : await Api.post('/me/join', token, {'code': code});
            }
            try {
              await Api.post('/me/name', token, {
                'firstName': s.firstName,
                'lastName': s.lastName,
              });
            } catch (_) {}
            await s.applyServerUser(res['user'] as Map<String, dynamic>);
            if (ctx.mounted) Navigator.of(ctx).pop();
          } catch (e) {
            setState(() {
              busy = false;
              error = _msg(s, e);
            });
          }
        }

        return Dialog(
          backgroundColor: pal.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: pal.cardBorder),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('co_role_title'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: pal.text,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      choice(false, Icons.school_outlined, t('co_student')),
                      const SizedBox(width: 10),
                      choice(true, Icons.workspace_premium_outlined,
                          t('co_coach')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: ctl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: coach
                          ? t('co_coach_secret')
                          : t('co_join_code_opt'),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                        child: Text(t('co_later')),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: busy ? null : submit,
                        child: Text(t('co_continue')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  ctl.dispose();
}

// ---------------------------------------------------------------------------
// Trener: o'quvchi kalendarini tahrirlash (4 ta blok)
// ---------------------------------------------------------------------------

class _PlanBlockEdit {
  final title = TextEditingController();
  final desc = TextEditingController();
  final minutes = TextEditingController();
  final puzzles = <int>{};
  int? materialId;
  int? openFrom; // ochilish vaqti (ms)
  int? openUntil; // yopilish vaqti (ms)
  bool lockOutside = true;
  int kind = 1;
  int level = 0;
  int count = 10;

  void load(Map<String, dynamic>? m) {
    title.text = (m?['title'] as String?) ?? '';
    desc.text = (m?['description'] as String?) ?? '';
    final mi = m?['minutes'];
    minutes.text = mi is num ? '${mi.toInt()}' : '';
    puzzles
      ..clear()
      ..addAll(((m?['puzzleIds'] as List?) ?? const []).map((e) => (e as num).toInt()));
    materialId = (m?['materialId'] as num?)?.toInt();
    openFrom = (m?['openFrom'] as num?)?.toInt();
    openUntil = (m?['openUntil'] as num?)?.toInt();
    lockOutside = (m?['lockOutside'] as bool?) ?? true;
  }

  void clear() => load(null);

  void dispose() {
    title.dispose();
    desc.dispose();
    minutes.dispose();
  }

  Map<String, dynamic> toJson(int idx) => {
        'idx': idx,
        'title': title.text.trim(),
        'description': desc.text.trim(),
        'minutes': int.tryParse(minutes.text.trim()),
        'puzzleIds': puzzles.toList()..sort(),
        'materialId': materialId,
        'openFrom': openFrom,
        'openUntil': openUntil,
        'lockOutside': lockOutside,
      };
}

/// Kalendar tahrirlagich. [preselect] — oldindan tanlangan o'quvchi.
Future<void> showPlanEditor(
  BuildContext context,
  AppSettings s,
  Pal pal,
  List<Map<String, dynamic>> students, {
  int? preselect,
}) async {
  final token = s.token;
  if (token == null) return;
  String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);
  final blocks = List.generate(4, (_) => _PlanBlockEdit());
  final recipients = <int>{if (preselect != null) preselect};
  var materials = <Map<String, dynamic>>[];
  String? error;
  var busy = false;

  try {
    final m = await Api.get('/coach/materials', token);
    materials = (m['materials'] as List).cast<Map<String, dynamic>>();
  } catch (_) {}
  if (preselect != null) {
    try {
      final res = await Api.get('/coach/plan/$preselect', token);
      for (final b in (res['blocks'] as List).cast<Map<String, dynamic>>()) {
        final i = (b['idx'] as num).toInt();
        if (i >= 0 && i < 4) blocks[i].load(b);
      }
    } catch (_) {}
  }
  if (!context.mounted) return;

  const defaultMin = [15, 20, 20, 25];

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        Future<void> save() async {
          if (recipients.isEmpty) {
            setState(() => error = t('pl_pick_students'));
            return;
          }
          setState(() {
            busy = true;
            error = null;
          });
          try {
            await Api.post('/coach/plan', token, {
              'studentIds': recipients.toList(),
              'blocks': [for (var i = 0; i < 4; i++) blocks[i].toJson(i)],
            });
            if (ctx.mounted) Navigator.of(ctx).pop();
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(t('pl_saved'))));
            }
          } catch (e) {
            setState(() {
              busy = false;
              error = _msg(s, e);
            });
          }
        }

        Widget blockEditor(int i) {
          final b = blocks[i];
          return Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: pal.cardBorder),
              color: pal.bg1.withAlpha(0x66),
            ),
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              initiallyExpanded: i == 0,
              title: Text(
                '${i + 1}. ${b.title.text.trim().isEmpty ? t('plan_b${i + 1}') : b.title.text.trim()}',
                style: TextStyle(fontWeight: FontWeight.w800, color: pal.text),
              ),
              subtitle: Text(
                [
                  '${int.tryParse(b.minutes.text.trim()) ?? defaultMin[i]} ${t('minutes_short')}',
                  if (b.puzzles.isNotEmpty)
                    t('pz_selected', {'n': '${b.puzzles.length}'}),
                  if (b.materialId != null) t('pl_has_material'),
                ].join('  ·  '),
                style: TextStyle(fontSize: 12.5, color: pal.subtext),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              children: [
                TextField(
                  controller: b.title,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: t('pl_block_name'),
                    hintText: t('plan_b${i + 1}'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: b.desc,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: t('pl_block_desc'),
                    hintText: t('plan_b${i + 1}d'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: b.minutes,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: t('pl_block_minutes'),
                    hintText: '${defaultMin[i]}',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  t('pl_window'),
                  style: TextStyle(fontWeight: FontWeight.w700, color: pal.text),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final v = await pickDateTimeMs(ctx, b.openFrom);
                        if (v != null) setState(() => b.openFrom = v);
                      },
                      icon: const Icon(Icons.play_circle_outline, size: 18),
                      label: Text(b.openFrom == null
                          ? t('pl_open_from')
                          : '${t('pl_open_from')}: ${fmtDateTimeMs(b.openFrom!)}'),
                    ),
                    if (b.openFrom != null)
                      IconButton(
                        onPressed: () => setState(() => b.openFrom = null),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final v = await pickDateTimeMs(ctx, b.openUntil);
                        if (v != null) setState(() => b.openUntil = v);
                      },
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: Text(b.openUntil == null
                          ? t('pl_open_until')
                          : '${t('pl_open_until')}: ${fmtDateTimeMs(b.openUntil!)}'),
                    ),
                    if (b.openUntil != null)
                      IconButton(
                        onPressed: () => setState(() => b.openUntil = null),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                  ],
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: b.lockOutside,
                  onChanged: (v) => setState(() => b.lockOutside = v),
                  title: Text(t('pl_lock'),
                      style: TextStyle(color: pal.text, fontSize: 13.5)),
                  subtitle: Text(t('pl_lock_hint'),
                      style: TextStyle(color: pal.subtext, fontSize: 12)),
                ),
                const SizedBox(height: 6),
                Text(
                  t('co_pick_puzzles'),
                  style: TextStyle(fontWeight: FontWeight.w700, color: pal.text),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final k in kKinds)
                      ChoiceChip(
                        label: Text(kindLabel(s.lang, k)),
                        selected: b.kind == k,
                        onSelected: (_) => setState(() => b.kind = k),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final l in const [0, 1, 2, 3])
                      ChoiceChip(
                        label: Text(l == 0 ? t('pz_all') : t('pz_lv$l')),
                        selected: b.level == l,
                        onSelected: (_) => setState(() => b.level = l),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final n in const [5, 10, 20, 30])
                      ChoiceChip(
                        label: Text('$n'),
                        selected: b.count == n,
                        onSelected: (_) => setState(() => b.count = n),
                      ),
                    FilledButton.icon(
                      onPressed: () => setState(() {
                        final pool = [
                          for (final p in allPuzzles())
                            if (p.kind == b.kind &&
                                (b.kind == 7 || b.level == 0 || p.level == b.level))
                              p.id,
                        ]..shuffle();
                        b.puzzles
                          ..clear()
                          ..addAll(pool.take(b.count));
                      }),
                      icon: const Icon(Icons.casino, size: 18),
                      label: Text(t('pz_random')),
                    ),
                    if (b.puzzles.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(b.puzzles.clear),
                        child: Text(t('pl_clear_puzzles')),
                      ),
                  ],
                ),
                if (b.kind == 7)
                  customPuzzlePicker(
                    context: ctx,
                    s: s,
                    pal: pal,
                    isPicked: b.puzzles.contains,
                    toggle: (id) => setState(() {
                      b.puzzles.contains(id)
                          ? b.puzzles.remove(id)
                          : b.puzzles.add(id);
                    }),
                    added: (id) => setState(() {
                      if (!b.puzzles.contains(id)) b.puzzles.add(id);
                    }),
                  ),
                const SizedBox(height: 4),
                Text(
                  t('pz_selected', {'n': '${b.puzzles.length}'}),
                  style: TextStyle(color: pal.subtext),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  value: materials.any((m) => (m['id'] as num).toInt() == b.materialId)
                      ? b.materialId
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: t('pl_material')),
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text(t('pl_no_material')),
                    ),
                    for (final m in materials)
                      DropdownMenuItem<int?>(
                        value: (m['id'] as num).toInt(),
                        child: Text(
                          '${m['kind'] == 'pdf' ? 'PDF' : 'PGN'} · ${m['title']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => b.materialId = v),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => setState(b.clear),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: Text(t('pl_reset_block')),
                  ),
                ),
              ],
            ),
          );
        }

        return Dialog(
          backgroundColor: pal.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: pal.cardBorder),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('pl_editor_title'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: pal.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t('pl_editor_hint'),
                    style: TextStyle(fontSize: 12.5, color: pal.subtext),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t('pl_students', {'n': '${recipients.length}'}),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: pal.text,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          recipients
                            ..clear()
                            ..addAll(students.map((x) => (x['id'] as num).toInt()));
                        }),
                        child: Text(t('co_all')),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final st in students)
                        FilterChip(
                          label: Text(st['name'] as String),
                          selected: recipients.contains((st['id'] as num).toInt()),
                          onSelected: (v) => setState(() {
                            final id = (st['id'] as num).toInt();
                            v ? recipients.add(id) : recipients.remove(id);
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [for (var i = 0; i < 4; i++) blockEditor(i)],
                      ),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      TextButton(
                        onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                        child: Text(t('co_cancel')),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: busy ? null : save,
                        child: Text(t('save')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  for (final b in blocks) {
    b.dispose();
  }
}

/// Trener uchun: "Vazifalar" oynasidagi kunlik kalendar boshqaruvi.
class CoachCalendarCard extends StatefulWidget {
  const CoachCalendarCard({super.key, required this.settings, required this.pal});
  final AppSettings settings;
  final Pal pal;

  @override
  State<CoachCalendarCard> createState() => _CoachCalendarCardState();
}

class _CoachCalendarCardState extends State<CoachCalendarCard> {
  List<Map<String, dynamic>> _students = [];
  bool _loading = true;
  String? _error;
  int? _sel; // ko'rsatilayotgan o'quvchi
  List<Map<String, dynamic>?> _blocks = List.filled(4, null);

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
      final st = await Api.get('/coach/students', token);
      if (!mounted) return;
      setState(() {
        _students = (st['students'] as List).cast<Map<String, dynamic>>();
        _loading = false;
        final ids = _students.map((x) => (x['id'] as num).toInt()).toList();
        if (_sel == null || !ids.contains(_sel)) {
          _sel = ids.isEmpty ? null : ids.first;
        }
      });
      await _loadPreview();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _msg(s, e);
        _loading = false;
      });
    }
  }

  Future<void> _loadPreview() async {
    final token = s.token;
    final id = _sel;
    if (token == null || id == null) return;
    try {
      final res = await Api.get('/coach/plan/$id', token);
      final out = List<Map<String, dynamic>?>.filled(4, null);
      for (final b in (res['blocks'] as List).cast<Map<String, dynamic>>()) {
        final i = (b['idx'] as num).toInt();
        if (i >= 0 && i < 4) out[i] = b;
      }
      if (mounted) setState(() => _blocks = out);
    } catch (_) {}
  }

  Widget _previewBlock(int i) {
    final b = _blocks[i];
    final title = ((b?['title'] as String?) ?? '').trim();
    final mins = (b?['minutes'] as num?)?.toInt();
    final pz = ((b?['puzzleIds'] as List?) ?? const []).length;
    final mat = (b?['materialTitle'] as String?) ?? '';
    final from = (b?['openFrom'] as num?)?.toInt();
    final until = (b?['openUntil'] as num?)?.toInt();
    const defMin = [15, 20, 20, 25];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pal.cardBorder),
        color: pal.bg1.withAlpha(0x66),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: pal.accent.withAlpha(0x26),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${mins ?? defMin[i]} ${t('minutes_short')}',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: pal.accent),
                ),
              ),
              const Spacer(),
              if (from != null || until != null)
                Icon(Icons.schedule, size: 18, color: pal.subtext),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${i + 1}. ${title.isEmpty ? t('plan_b${i + 1}') : title}',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: pal.text),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (pz > 0) t('pz_selected', {'n': '$pz'}),
              if (mat.isNotEmpty) mat,
              if (from != null) fmtDateTimeMs(from),
              if (until != null) '→ ${fmtDateTimeMs(until)}',
            ].join('\n').trim().isEmpty
                ? t('plan_b${i + 1}d')
                : [
                    if (pz > 0) t('pz_selected', {'n': '$pz'}),
                    if (mat.isNotEmpty) mat,
                    if (from != null) fmtDateTimeMs(from),
                    if (until != null) '→ ${fmtDateTimeMs(until)}',
                  ].join('\n'),
            style: TextStyle(fontSize: 12.5, color: pal.subtext),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _card(
      pal,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_calendar, color: pal.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('plc_title'),
                  style: TextStyle(
                    fontSize: 18,
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
          Text(
            t('plc_hint'),
            style: TextStyle(fontSize: 12.5, color: pal.subtext),
          ),
          const SizedBox(height: 10),
          if (_loading)
            Text(t('co_loading'), style: TextStyle(color: pal.subtext))
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.redAccent))
          else if (_students.isEmpty)
            Text(t('co_no_students'), style: TextStyle(color: pal.subtext))
          else ...[
            DropdownButtonFormField<int>(
              value: _sel,
              isExpanded: true,
              decoration: InputDecoration(labelText: t('plc_preview_for')),
              items: [
                for (final st in _students)
                  DropdownMenuItem(
                    value: (st['id'] as num).toInt(),
                    child: Text(st['name'] as String,
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) {
                setState(() => _sel = v);
                _loadPreview();
              },
            ),
            const SizedBox(height: 10),
            LayoutBuilder(builder: (context, box) {
              final two = box.maxWidth >= 520;
              final w = two ? (box.maxWidth - 10) / 2 : box.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < 4; i++)
                    SizedBox(width: w, child: _previewBlock(i)),
                ],
              );
            }),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    await showPlanEditor(context, s, pal, _students,
                        preselect: _sel);
                    _loadPreview();
                  },
                  icon: const Icon(Icons.edit_calendar),
                  label: Text(t('plc_edit_sel')),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await showPlanEditor(context, s, pal, _students);
                    _loadPreview();
                  },
                  icon: const Icon(Icons.groups_outlined),
                  label: Text(t('plc_all')),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final st in _students)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        st['name'] as String,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: pal.text,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => showPlanEditor(
                        context,
                        s,
                        pal,
                        _students,
                        preselect: (st['id'] as num).toInt(),
                      ),
                      icon: const Icon(Icons.edit_calendar, size: 18),
                      label: Text(t('pl_edit')),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// "Vazifalar" bo'limidagi trener qismi: o'quvchi uchun topshiriqlar,
/// trener uchun boshqaruv paneli.
class CoachSection extends StatelessWidget {
  const CoachSection({
    super.key,
    required this.settings,
    required this.pal,
    required this.onOpen,
  });
  final AppSettings settings;
  final Pal pal;
  final Future<void> Function(Puzzle) onOpen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final role = settings.role;
        if (role == 'coach') {
          return _CoachPanel(settings: settings, pal: pal);
        }
        if (role == 'student') {
          return _StudentTasks(settings: settings, pal: pal, onOpen: onOpen);
        }
        return _card(
          pal,
          Row(
            children: [
              Icon(Icons.school_outlined, color: pal.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tr(settings.lang, 'coach_tasks'),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: pal.text,
                  ),
                ),
              ),
              FilledButton(
                onPressed: () => showRoleDialog(context, settings, pal),
                child: Text(tr(settings.lang, 'co_pick_role')),
              ),
            ],
          ),
        );
      },
    );
  }
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

Widget _bar(Pal pal, int done, int total) => ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: LinearProgressIndicator(
        value: total == 0 ? 0 : done / total,
        minHeight: 7,
        backgroundColor: pal.cardBorder,
        color: pal.accent,
      ),
    );

// ---------------------------------------------------------------------------
// O'quvchi
// ---------------------------------------------------------------------------

class _StudentTasks extends StatefulWidget {
  const _StudentTasks({
    required this.settings,
    required this.pal,
    required this.onOpen,
  });
  final AppSettings settings;
  final Pal pal;
  final Future<void> Function(Puzzle) onOpen;

  @override
  State<_StudentTasks> createState() => _StudentTasksState();
}

class _StudentTasksState extends State<_StudentTasks> {
  List<Map<String, dynamic>> _tasks = [];
  bool _loading = true;
  String? _error;
  final _codeCtl = TextEditingController();

  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = s.token;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Api.post('/me/solved', token, {'solved': s.solved});
      final res = await Api.get('/tasks', token);
      final list = (res['tasks'] as List).cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _tasks = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _msg(s, e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _join() async {
    final token = s.token;
    final code = _codeCtl.text.trim();
    if (token == null || code.isEmpty) return;
    try {
      final res = await Api.post('/me/join', token, {'code': code});
      await s.applyServerUser(res['user'] as Map<String, dynamic>);
      _codeCtl.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_msg(s, e))));
    }
  }

  Future<void> _markDone(int assignmentId) async {
    final token = s.token;
    if (token == null) return;
    try {
      await Api.post('/assignments/$assignmentId/done', token, {});
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_msg(s, e))));
    }
  }

  Future<void> _start(Map<String, dynamic> task) async {
    final ids = (task['puzzleIds'] as List).map((e) => (e as num).toInt());
    Puzzle? target;
    for (final id in ids) {
      if (!s.solved.containsKey('$id')) {
        target = puzzleById(id);
      }
      if (target != null) break;
    }
    if (target == null) {
      for (final id in ids) {
        target = puzzleById(id);
        if (target != null) break;
      }
    }
    if (target == null) return;
    s.pushCtx('task');
    try {
      await widget.onOpen(target);
    } finally {
      s.popCtx();
    }
    await _load();
  }

  Widget _taskTile(Map<String, dynamic> task) {
    final prog = task['progress'] as Map<String, dynamic>;
    final done = (prog['done'] as num).toInt();
    final total = (prog['total'] as num).toInt();
    final completed = prog['completed'] == true;
    final isPuzzles = task['type'] == 'puzzles';
    final status = task['status'] as String;
    final due = task['dueDate'] as String?;
    final desc = (task['description'] as String?) ?? '';

    Widget action;
    if (isPuzzles) {
      action = completed
          ? Text(t('co_task_done'),
              style: const TextStyle(
                  color: Color(0xFF34D399), fontWeight: FontWeight.w800))
          : FilledButton(
              onPressed: () => _start(task),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              child: Text(t('plan_start')),
            );
    } else if (status == 'confirmed') {
      action = Text(t('co_confirmed'),
          style: const TextStyle(
              color: Color(0xFF34D399), fontWeight: FontWeight.w800));
    } else if (status == 'done') {
      action = Text(t('co_wait_confirm'),
          style: TextStyle(color: pal.subtext, fontWeight: FontWeight.w700));
    } else {
      action = OutlinedButton(
        onPressed: () => _markDone((task['assignmentId'] as num).toInt()),
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
        child: Text(t('co_mark_done')),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pal.cardBorder),
        color: pal.bg1.withAlpha(0x66),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task['title'] as String,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15.5,
              color: pal.text,
            ),
          ),
          if (desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(desc, style: TextStyle(color: pal.subtext)),
            ),
          if (due != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                t('co_due_on', {'d': due}),
                style: TextStyle(fontSize: 12.5, color: pal.subtext),
              ),
            ),
          if (isPuzzles) ...[
            const SizedBox(height: 8),
            _bar(pal, done, total),
            const SizedBox(height: 4),
            Text('$done / $total',
                style: TextStyle(fontSize: 12.5, color: pal.subtext)),
          ],
          const SizedBox(height: 10),
          action,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _card(
      pal,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.school_outlined, color: pal.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('coach_tasks'),
                  style: TextStyle(
                    fontSize: 18,
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
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(t('co_loading'), style: TextStyle(color: pal.subtext)),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            )
          else if (_tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(t('co_no_tasks'), style: TextStyle(color: pal.subtext)),
            )
          else
            for (final task in _tasks) _taskTile(task),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: t('co_join_code'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _join,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                child: Text(t('co_join')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Trener
// ---------------------------------------------------------------------------

class _CoachPanel extends StatefulWidget {
  const _CoachPanel({required this.settings, required this.pal});
  final AppSettings settings;
  final Pal pal;

  @override
  State<_CoachPanel> createState() => _CoachPanelState();
}

class _CoachPanelState extends State<_CoachPanel> {
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _invites = [];
  String _invite = '';
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

  Future<void> _newInvite() async {
    final token = s.token;
    if (token == null) return;
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('inv_new')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: t('inv_label'),
            hintText: t('inv_label_hint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('co_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('co_create')),
          ),
        ],
      ),
    );
    final label = ctl.text.trim();
    ctl.dispose();
    if (ok != true) return;
    try {
      await Api.post('/coach/invites', token, {'label': label});
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_msg(s, e))));
    }
  }

  Widget _inviteRow(Map<String, dynamic> inv) {
    final used = inv['usedBy'] != null;
    final label = (inv['label'] as String?) ?? '';
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: pal.cardBorder),
        color: pal.bg1.withAlpha(0x66),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.isEmpty ? t('inv_no_label') : label,
                  style: TextStyle(fontWeight: FontWeight.w700, color: pal.text),
                ),
                Text(
                  used
                      ? t('inv_used_by', {'n': '${inv['usedByName'] ?? ''}'})
                      : t('inv_free'),
                  style: TextStyle(
                    fontSize: 12,
                    color: used ? const Color(0xFF34D399) : pal.subtext,
                  ),
                ),
              ],
            ),
          ),
          Text(
            inv['code'] as String,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: pal.text,
            ),
          ),
          IconButton(
            tooltip: t('co_copy'),
            visualDensity: VisualDensity.compact,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: inv['code'] as String));
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(t('co_copied'))));
            },
            icon: Icon(Icons.copy, size: 18, color: pal.accent),
          ),
          IconButton(
            tooltip: t('co_delete'),
            visualDensity: VisualDensity.compact,
            onPressed: () => _post('/coach/invites/${inv['code']}/delete'),
            icon: Icon(Icons.delete_outline, size: 18, color: pal.subtext),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    final token = s.token;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final st = await Api.get('/coach/students', token);
      final tk = await Api.get('/coach/tasks', token);
      final iv = await Api.get('/coach/invites', token);
      if (!mounted) return;
      setState(() {
        _invites = (iv['invites'] as List).cast<Map<String, dynamic>>();
        _invite = (st['inviteCode'] as String?) ?? '';
        _students = (st['students'] as List).cast<Map<String, dynamic>>();
        _tasks = (tk['tasks'] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _msg(s, e);
        _loading = false;
      });
    }
  }

  Future<void> _post(String path) async {
    final token = s.token;
    if (token == null) return;
    try {
      await Api.post(path, token, {});
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_msg(s, e))));
    }
  }

  Future<void> _newTask() async {
    final token = s.token;
    if (token == null) return;
    final titleCtl = TextEditingController();
    final descCtl = TextEditingController();
    var isPuzzles = true;
    final picked = <int>{};
    var pKind = 1;
    var pLevel = 0;
    var pCount = 10;
    final recipients = <int>{};
    String? due;
    String? error;
    var busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> create() async {
            if (titleCtl.text.trim().isEmpty ||
                (isPuzzles && picked.isEmpty)) {
              setState(() => error = t('err_invalid_task'));
              return;
            }
            setState(() {
              busy = true;
              error = null;
            });
            try {
              await Api.post('/coach/tasks', token, {
                'title': titleCtl.text.trim(),
                'description': descCtl.text.trim(),
                'type': isPuzzles ? 'puzzles' : 'text',
                'puzzleIds': picked.toList()..sort(),
                'dueDate': due,
                'studentIds': recipients.toList(),
              });
              if (ctx.mounted) Navigator.of(ctx).pop();
            } catch (e) {
              setState(() {
                busy = false;
                error = _msg(s, e);
              });
            }
          }

          return Dialog(
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
                      t('co_new_task'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: pal.text,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: titleCtl,
                      decoration: InputDecoration(labelText: t('co_task_title')),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descCtl,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(labelText: t('co_task_desc')),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(t('co_type_puzzles')),
                          selected: isPuzzles,
                          onSelected: (_) => setState(() => isPuzzles = true),
                        ),
                        ChoiceChip(
                          label: Text(t('co_type_text')),
                          selected: !isPuzzles,
                          onSelected: (_) => setState(() => isPuzzles = false),
                        ),
                      ],
                    ),
                    if (isPuzzles) ...[
                      const SizedBox(height: 12),
                      Text(
                        t('co_pick_puzzles'),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: pal.text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final k in kKinds)
                            ChoiceChip(
                              label: Text(kindLabel(s.lang, k)),
                              selected: pKind == k,
                              onSelected: (_) => setState(() => pKind = k),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final l in const [0, 1, 2, 3])
                            ChoiceChip(
                              label: Text(l == 0 ? t('pz_all') : t('pz_lv$l')),
                              selected: pLevel == l,
                              onSelected: (_) => setState(() => pLevel = l),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final n in const [5, 10, 20, 30])
                            ChoiceChip(
                              label: Text('$n'),
                              selected: pCount == n,
                              onSelected: (_) => setState(() => pCount = n),
                            ),
                          FilledButton.icon(
                            onPressed: () => setState(() {
                              final pool = [
                                for (final p in allPuzzles())
                                  if (p.kind == pKind &&
                                      (pKind == 7 || pLevel == 0 || p.level == pLevel))
                                    p.id,
                              ]..shuffle();
                              picked
                                ..clear()
                                ..addAll(pool.take(pCount));
                            }),
                            icon: const Icon(Icons.casino, size: 18),
                            label: Text(t('pz_random')),
                          ),
                        ],
                      ),
                      if (pKind == 7)
                        customPuzzlePicker(
                          context: ctx,
                          s: s,
                          pal: pal,
                          isPicked: picked.contains,
                          toggle: (id) => setState(() {
                            picked.contains(id)
                                ? picked.remove(id)
                                : picked.add(id);
                          }),
                          added: (id) => setState(() => picked.add(id)),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        t('pz_selected', {'n': '${picked.length}'}),
                        style: TextStyle(color: pal.subtext),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final now = DateTime.now();
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: now.add(const Duration(days: 3)),
                              firstDate: now,
                              lastDate: now.add(const Duration(days: 365)),
                            );
                            if (d != null) {
                              setState(() => due = AppSettings.dayKey(d));
                            }
                          },
                          icon: const Icon(Icons.event, size: 18),
                          label: Text(due ?? t('co_no_due')),
                        ),
                        if (due != null)
                          IconButton(
                            onPressed: () => setState(() => due = null),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                      ],
                    ),
                    if (_students.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        '${t('co_task_to')}: ${recipients.isEmpty ? t('co_all') : '${recipients.length}'}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: pal.text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final st in _students)
                            FilterChip(
                              label: Text(st['name'] as String),
                              selected:
                                  recipients.contains((st['id'] as num).toInt()),
                              onSelected: (v) => setState(() {
                                final id = (st['id'] as num).toInt();
                                if (v) {
                                  recipients.add(id);
                                } else {
                                  recipients.remove(id);
                                }
                              }),
                            ),
                        ],
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!,
                          style: const TextStyle(color: Colors.redAccent)),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton(
                          onPressed:
                              busy ? null : () => Navigator.of(ctx).pop(),
                          child: Text(t('co_cancel')),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: busy ? null : create,
                          child: Text(t('co_create')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    titleCtl.dispose();
    descCtl.dispose();
    await _load();
  }

  Widget _result(Map<String, dynamic> task, Map<String, dynamic> r) {
    final prog = r['progress'] as Map<String, dynamic>;
    final done = (prog['done'] as num).toInt();
    final total = (prog['total'] as num).toInt();
    final completed = prog['completed'] == true;
    final status = r['status'] as String;
    final isPuzzles = task['type'] == 'puzzles';

    Widget trailing;
    if (isPuzzles) {
      trailing = Text(
        '$done / $total',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: completed ? const Color(0xFF34D399) : pal.subtext,
        ),
      );
    } else if (status == 'confirmed') {
      trailing = Text(t('co_confirmed'),
          style: const TextStyle(
              color: Color(0xFF34D399), fontWeight: FontWeight.w800));
    } else if (status == 'done') {
      trailing = FilledButton(
        onPressed: () =>
            _post('/coach/assignments/${(r['assignmentId'] as num).toInt()}/confirm'),
        style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
        child: Text(t('co_confirm')),
      );
    } else {
      trailing = Text('—', style: TextStyle(color: pal.subtext));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(r['name'] as String,
                style: TextStyle(color: pal.text),
                overflow: TextOverflow.ellipsis),
          ),
          if (isPuzzles)
            SizedBox(
              width: 80,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _bar(pal, done, total),
              ),
            ),
          trailing,
        ],
      ),
    );
  }

  Widget _taskTile(Map<String, dynamic> task) {
    final results = (task['results'] as List).cast<Map<String, dynamic>>();
    final due = task['dueDate'] as String?;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pal.cardBorder),
        color: pal.bg1.withAlpha(0x66),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          task['title'] as String,
          style: TextStyle(fontWeight: FontWeight.w800, color: pal.text),
        ),
        subtitle: Text(
          [
            task['type'] == 'puzzles' ? t('co_type_puzzles') : t('co_type_text'),
            if (due != null) t('co_due_on', {'d': due}),
            '${results.length} ${t('co_students_short')}',
          ].join('  ·  '),
          style: TextStyle(fontSize: 12.5, color: pal.subtext),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (results.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(t('co_no_students'),
                  style: TextStyle(color: pal.subtext)),
            )
          else
            for (final r in results) _result(task, r),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _post('/coach/tasks/${(task['id'] as num).toInt()}/delete'),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(t('co_delete')),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _card(
      pal,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_outlined, color: pal.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('co_panel'),
                  style: TextStyle(
                    fontSize: 18,
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
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: pal.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(
                  '${t('co_invite_code')}: ',
                  style: TextStyle(color: pal.subtext),
                ),
                Text(
                  _invite.isEmpty ? '—' : _invite,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: pal.text,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: t('co_copy'),
                  onPressed: _invite.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: _invite));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(t('co_copied'))),
                          );
                        },
                  icon: Icon(Icons.copy, size: 18, color: pal.accent),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  t('inv_title'),
                  style: TextStyle(fontWeight: FontWeight.w700, color: pal.text),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _newInvite,
                icon: const Icon(Icons.vpn_key_outlined, size: 18),
                label: Text(t('inv_new')),
              ),
            ],
          ),
          Text(
            t('inv_hint'),
            style: TextStyle(fontSize: 12, color: pal.subtext),
          ),
          for (final inv in _invites) _inviteRow(inv),
          const SizedBox(height: 12),
          Text(
            '${t('co_students')}: ${_students.length}',
            style: TextStyle(fontWeight: FontWeight.w700, color: pal.text),
          ),
          if (_students.isEmpty && !_loading)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(t('co_no_students'),
                  style: TextStyle(color: pal.subtext, fontSize: 13)),
            )
          else
            Column(
              children: [
                for (final st in _students)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            st['name'] as String,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: pal.text,
                            ),
                          ),
                        ),
                        Text(
                          '${st['rating'] ?? 1200}  ·  ${st['solved'] ?? 0} ${t('st_solved_short')}  ·  ${st['minutes7'] ?? 0} ${t('st_min')}/7',
                          style: TextStyle(fontSize: 12.5, color: pal.subtext),
                        ),
                        IconButton(
                          tooltip: t('pl_edit'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => showPlanEditor(
                            context,
                            s,
                            pal,
                            _students,
                            preselect: (st['id'] as num).toInt(),
                          ),
                          icon: Icon(Icons.edit_calendar, size: 20, color: pal.accent),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _newTask,
            icon: const Icon(Icons.add),
            label: Text(t('co_new_task')),
          ),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(t('co_loading'), style: TextStyle(color: pal.subtext)),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            )
          else if (_tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(t('co_no_tasks'), style: TextStyle(color: pal.subtext)),
            )
          else
            for (final task in _tasks) _taskTile(task),
        ],
      ),
    );
  }
}


/// Trener boshqotirmalarini tanlash va yangisini yaratish (kind = 7).
Widget customPuzzlePicker({
  required BuildContext context,
  required AppSettings s,
  required Pal pal,
  required bool Function(int) isPicked,
  required void Function(int) toggle,
  required void Function(int) added,
}) {
  final t = (String k) => tr(s.lang, k);
  return ValueListenableBuilder<int>(
    valueListenable: customPuzzlesRev,
    builder: (ctx, _, __) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () async {
                final id = await showPuzzleMaker(context, s, pal);
                if (id != null) added(id);
              },
              icon: const Icon(Icons.add, size: 18),
              label: Text(t('pm_create_btn')),
            ),
            for (final p in kCustomPuzzles)
              FilterChip(
                label: Text('#${shownNo(p)}'),
                selected: isPicked(p.id),
                onSelected: (_) => toggle(p.id),
              ),
          ],
        ),
      ],
    ),
  );
}


/// Sana va vaqtni ketma-ket tanlash (millisekund qaytaradi).
Future<int?> pickDateTimeMs(BuildContext context, int? initial) async {
  final now = DateTime.now();
  final base = initial == null
      ? now
      : DateTime.fromMillisecondsSinceEpoch(initial);
  final d = await showDatePicker(
    context: context,
    initialDate: base,
    firstDate: now.subtract(const Duration(days: 30)),
    lastDate: now.add(const Duration(days: 730)),
  );
  if (d == null || !context.mounted) return null;
  final tm = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(base),
  );
  if (tm == null) return null;
  return DateTime(d.year, d.month, d.day, tm.hour, tm.minute)
      .millisecondsSinceEpoch;
}

String fmtDateTimeMs(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}
