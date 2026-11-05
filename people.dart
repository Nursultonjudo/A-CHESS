import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'online.dart';
import 'page_frame.dart';
import 'settings.dart';
import 'widgets/chess_board.dart';

/// Asosiy oynadagi ixcham qidiruv tugmasi: chapda xira "Qidirish", o'ngda lupa.
class PeopleSearchButton extends StatelessWidget {
  const PeopleSearchButton({
    super.key,
    required this.settings,
    required this.pal,
    this.onPick,
    this.width = 190,
  });
  final AppSettings settings;
  final Pal pal;

  /// Berilsa, ro'yxatdan tanlash rejimi: foydalanuvchi tanlansa shu chaqiriladi.
  final void Function(Map<String, dynamic> user)? onPick;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 38,
      child: Material(
        color: pal.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: pal.cardBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            final r = await showUserSearch(context, settings, pal,
                pick: onPick != null);
            if (r != null && onPick != null) onPick!(r);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr(settings.lang, 'pe_search'),
                    style: TextStyle(
                      color: pal.subtext.withAlpha(0xAA),
                      fontSize: 14,
                    ),
                  ),
                ),
                Icon(Icons.search, size: 20, color: pal.subtext),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Foydalanuvchilar ro'yxati va qidiruv. [pick] bo'lsa tanlangan foydalanuvchi qaytadi.
Future<Map<String, dynamic>?> showUserSearch(
        BuildContext context, AppSettings s, Pal pal,
        {bool pick = false}) =>
    Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
      builder: (_) => UserSearchPage(settings: s, pal: pal, pick: pick),
    ));

class UserSearchPage extends StatefulWidget {
  const UserSearchPage({
    super.key,
    required this.settings,
    required this.pal,
    this.pick = false,
  });
  final AppSettings settings;
  final Pal pal;
  final bool pick;
  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);

  final _q = TextEditingController();
  Timer? _deb;
  String _sort = 'rating';
  final List<Map<String, dynamic>> _users = [];
  bool _loading = false;
  bool _more = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _deb?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    final token = s.token;
    if (token == null) return;
    if (reset) _users.clear();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Api.get(
        '/users/search?q=${Uri.encodeQueryComponent(_q.text.trim())}'
        '&sort=$_sort&offset=${_users.length}&limit=30',
        token,
      );
      if (!mounted) return;
      setState(() {
        _users.addAll(((r['users'] as List?) ?? const []).cast<Map<String, dynamic>>());
        _more = r['hasMore'] == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? t(e.l10nKey) : t('err_network');
        _loading = false;
      });
    }
  }

  void _onChanged(String _) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 350), () => _load(reset: true));
  }

  String _name(Map<String, dynamic> u) {
    final n = '${u['firstName'] ?? ''} ${u['lastName'] ?? ''}'.trim();
    return n.isEmpty ? 'ID ${u['publicId']}' : n;
  }

  @override
  Widget build(BuildContext context) {
    Widget chip(String key, String label) => ChoiceChip(
          label: Text(label),
          selected: _sort == key,
          selectedColor: pal.accent.withAlpha(0x55),
          onSelected: (_) {
            setState(() => _sort = key);
            _load(reset: true);
          },
        );
    return Scaffold(
      backgroundColor: pal.bg1,
      appBar: AppBar(title: Text(t('pe_title'))),
      body: PageFrame(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: TextField(
                controller: _q,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: t('pe_search_hint'),
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: 8, children: [
                  chip('rating', t('pe_by_rating')),
                  chip('name', t('pe_by_name')),
                  chip('username', t('pe_by_username')),
                ]),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  if (_users.isEmpty && !_loading && _error == null)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(t('pe_none'),
                            style: TextStyle(color: pal.subtext)),
                      ),
                    ),
                  for (var i = 0; i < _users.length; i++)
                    Card(
                      color: pal.card,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: pal.cardBorder),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor: pal.accent.withAlpha(0x44),
                          child: Text(
                            _name(_users[i]).substring(0, 1).toUpperCase(),
                            style: TextStyle(color: pal.text),
                          ),
                        ),
                        title: Text(_name(_users[i]),
                            style: TextStyle(
                                color: pal.text, fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          [
                            if ('${_users[i]['username']}'.isNotEmpty)
                              '@${_users[i]['username']}',
                            'ID ${_users[i]['publicId']}',
                          ].join('  ·  '),
                          style: TextStyle(color: pal.subtext),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_rounded, size: 18, color: pal.accent),
                            const SizedBox(width: 4),
                            Text('${_users[i]['rating']}',
                                style: TextStyle(
                                    color: pal.text, fontWeight: FontWeight.w800)),
                          ],
                        ),
                        onTap: () {
                          if (widget.pick) {
                            Navigator.pop(context, _users[i]);
                          } else {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => UserProfilePage(
                                settings: s,
                                pal: pal,
                                publicId: '${_users[i]['publicId']}',
                              ),
                            ));
                          }
                        },
                      ),
                    ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (_more && !_loading)
                    Center(
                      child: TextButton(
                        onPressed: _load,
                        child: Text(t('pe_more')),
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

/// Boshqa foydalanuvchining ochiq profili.
class UserProfilePage extends StatefulWidget {
  const UserProfilePage({
    super.key,
    required this.settings,
    required this.pal,
    required this.publicId,
  });
  final AppSettings settings;
  final Pal pal;
  final String publicId;
  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String k, [Map<String, String> a = const {}]) => tr(s.lang, k, a);
  Map<String, dynamic>? _u;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.get('/users/${widget.publicId}/profile', s.token!);
      if (mounted) setState(() => _u = (r['user'] as Map).cast<String, dynamic>());
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is ApiException ? t(e.l10nKey) : t('err_network'));
      }
    }
  }

  String _birth(String v) {
    final d = DateTime.tryParse(v);
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: pal.accent),
            const SizedBox(width: 10),
            SizedBox(
              width: 120,
              child: Text(label, style: TextStyle(color: pal.subtext)),
            ),
            Expanded(
              child: Text(value,
                  style: TextStyle(color: pal.text, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final u = _u;
    final name = u == null
        ? ''
        : '${u['firstName'] ?? ''} ${u['lastName'] ?? ''}'.trim();
    final bio = '${u?['bio'] ?? ''}'.trim();
    final un = '${u?['username'] ?? ''}';
    final birth = '${u?['birthDate'] ?? ''}';
    final age = u?['age'];
    return Scaffold(
      backgroundColor: pal.bg1,
      appBar: AppBar(title: Text(t('pe_profile'))),
      body: PageFrame(
        child: _error != null
            ? Center(child: Text(_error!, style: TextStyle(color: pal.text)))
            : u == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: pal.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: pal.cardBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name.isEmpty ? 'ID ${u['publicId']}' : name,
                                style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: pal.text)),
                            const SizedBox(height: 10),
                            _row(Icons.alternate_email, t('username'),
                                un.isEmpty ? '—' : '@$un'),
                            _row(Icons.star_rounded, t('my_rating'),
                                '${u['rating']}'),
                            _row(Icons.cake_outlined, t('birth_date'),
                                birth.isEmpty ? '—' : _birth(birth)),
                            _row(Icons.hourglass_bottom, t('pe_age'),
                                age == null ? '—' : '$age'),
                            _row(Icons.tag, 'ID', '${u['publicId']}'),
                            const Divider(height: 24),
                            Text(t('bio'),
                                style: TextStyle(
                                    color: pal.subtext, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(bio.isEmpty ? '—' : bio,
                                style: TextStyle(color: pal.text, height: 1.4)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () => showDuelLobby(context, s, pal,
                            presetId: '${u['publicId']}'),
                        icon: const Icon(Icons.sports_martial_arts),
                        label: Text(t('du_challenge')),
                      ),
                    ],
                  ),
      ),
    );
  }
}
