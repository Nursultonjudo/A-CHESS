import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'l10n.dart';
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
        for (final p in kPuzzles) {
          if (p.id == id) {
            target = p;
            break;
          }
        }
      }
      if (target != null) break;
    }
    if (target == null) {
      for (final p in kPuzzles) {
        if (ids.contains(p.id)) {
          target = p;
          break;
        }
      }
    }
    if (target == null) return;
    await widget.onOpen(target);
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
      if (!mounted) return;
      setState(() {
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
                          for (final p in kPuzzles)
                            FilterChip(
                              label: Text('${p.id}'),
                              selected: picked.contains(p.id),
                              onSelected: (v) => setState(() {
                                if (v) {
                                  picked.add(p.id);
                                } else {
                                  picked.remove(p.id);
                                }
                              }),
                            ),
                        ],
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
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final st in _students)
                    Chip(
                      label: Text(st['name'] as String),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
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
