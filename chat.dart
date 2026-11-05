import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'page_frame.dart';
import 'people.dart';
import 'settings.dart';
import 'widgets/chess_board.dart';

/// O'qilmagan xabarlar soni (HomeScreen yangilab turadi).
final ValueNotifier<int> chatUnread = ValueNotifier<int>(0);

/// Yuqori o'ng burchakdagi xabar ikonkasi (o'qilmagan xabarlar soni bilan).
class ChatButton extends StatelessWidget {
  const ChatButton({super.key, required this.settings, required this.pal});
  final AppSettings settings;
  final Pal pal;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: chatUnread,
      builder: (_, n, __) => Tooltip(
        message: tr(settings.lang, 'ch_title'),
        child: Material(
          color: pal.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: pal.cardBorder),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => showChatList(context, settings, pal),
            child: SizedBox(
              width: 42,
              height: 38,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 21, color: pal.subtext),
                  if (n > 0)
                    Positioned(
                      right: 3,
                      top: 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD93025),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          n > 99 ? '99+' : '$n',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showChatList(BuildContext context, AppSettings s, Pal pal) =>
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatListPage(settings: s, pal: pal),
    ));

Future<void> openChatWith(BuildContext context, AppSettings s, Pal pal,
        {required int userId, String name = ''}) =>
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatPage(settings: s, pal: pal, userId: userId, name: name),
    ));

String _hm(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  String two(int x) => x.toString().padLeft(2, '0');
  final hm = '${two(d.hour)}:${two(d.minute)}';
  if (d.year == now.year && d.month == now.month && d.day == now.day) return hm;
  return '${two(d.day)}.${two(d.month)} $hm';
}

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key, required this.settings, required this.pal});
  final AppSettings settings;
  final Pal pal;
  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String k) => tr(s.lang, k);
  List<Map<String, dynamic>> _chats = [];
  bool _loading = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final r = await Api.get('/chat/list', s.token!);
      if (!mounted) return;
      final list = ((r['chats'] as List?) ?? const []).cast<Map<String, dynamic>>();
      chatUnread.value =
          list.fold<int>(0, (a, c) => a + ((c['unread'] as num?)?.toInt() ?? 0));
      setState(() {
        _chats = list;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pal.bg1,
      appBar: AppBar(title: Text(t('ch_title'))),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: pal.accent,
        foregroundColor: Colors.black,
        onPressed: () async {
          final u = await showUserSearch(context, s, pal, pick: true);
          if (u != null && context.mounted) {
            final name = '${u['firstName'] ?? ''} ${u['lastName'] ?? ''}'.trim();
            await openChatWith(context, s, pal,
                userId: (u['id'] as num).toInt(), name: name);
            _load(quiet: true);
          }
        },
        icon: const Icon(Icons.edit_outlined),
        label: Text(t('ch_new')),
      ),
      body: PageFrame(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: TextStyle(color: pal.text)))
                : _chats.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(t('ch_empty'),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: pal.subtext)),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                        children: [
                          for (final c in _chats)
                            Card(
                              color: pal.card,
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(color: pal.cardBorder),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: pal.accent.withAlpha(0x44),
                                  child: Text(
                                    '${(c['user'] as Map)['name']}'.substring(0, 1).toUpperCase(),
                                    style: TextStyle(color: pal.text),
                                  ),
                                ),
                                title: Text('${(c['user'] as Map)['name']}',
                                    style: TextStyle(
                                        color: pal.text,
                                        fontWeight: ((c['unread'] as num?) ?? 0) > 0
                                            ? FontWeight.w800
                                            : FontWeight.w600)),
                                subtitle: Text(
                                  '${c['mine'] == true ? '${t('ch_you')}: ' : ''}${c['last']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: pal.subtext),
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(_hm((c['at'] as num).toInt()),
                                        style: TextStyle(fontSize: 11.5, color: pal.subtext)),
                                    if (((c['unread'] as num?) ?? 0) > 0)
                                      Container(
                                        margin: const EdgeInsets.only(top: 4),
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: pal.accent,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text('${c['unread']}',
                                            style: const TextStyle(
                                                color: Colors.black,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800)),
                                      ),
                                  ],
                                ),
                                onTap: () async {
                                  final u = (c['user'] as Map).cast<String, dynamic>();
                                  await openChatWith(context, s, pal,
                                      userId: (u['id'] as num).toInt(),
                                      name: '${u['name']}');
                                  _load(quiet: true);
                                },
                              ),
                            ),
                        ],
                      ),
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.settings,
    required this.pal,
    required this.userId,
    this.name = '',
  });
  final AppSettings settings;
  final Pal pal;
  final int userId;
  final String name;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String k) => tr(s.lang, k);

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _msgs = [];
  String _name = '';
  Timer? _timer;
  Timer? _deb;
  String? _blockReason; // yuborib bo'lmaydigan sabab
  bool _sending = false;
  bool _checking = false;
  int _checkSeq = 0;

  @override
  void initState() {
    super.initState();
    _name = widget.name;
    _load();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _deb?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final after = _msgs.isEmpty ? 0 : (_msgs.last['id'] as num).toInt();
      final r = await Api.get('/chat/with/${widget.userId}?after=$after', s.token!);
      if (!mounted) return;
      final fresh = ((r['messages'] as List?) ?? const []).cast<Map<String, dynamic>>();
      final u = (r['user'] as Map?)?.cast<String, dynamic>();
      if (fresh.isNotEmpty || (u != null && _name.isEmpty)) {
        setState(() {
          if (u != null) _name = '${u['name']}';
          _msgs.addAll(fresh);
        });
        _toEnd();
      }
    } catch (_) {}
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
      }
    });
  }

  /// Matn o'zgarganda serverda tekshiriladi: taqiqlangan bo'lsa tugma o'chadi va sabab ko'rinadi.
  void _onChanged(String v) {
    _deb?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _blockReason = null;
        _checking = false;
      });
      return;
    }
    setState(() => _checking = true);
    final seq = ++_checkSeq;
    _deb = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await Api.post('/chat/check', s.token!, {'text': v});
        if (!mounted || seq != _checkSeq) return;
        setState(() {
          _checking = false;
          _blockReason = r['ok'] == true ? null : '${r['reason']}';
        });
      } catch (_) {
        if (mounted && seq == _checkSeq) setState(() => _checking = false);
      }
    });
  }

  String _reasonText(String r) => switch (r) {
        'code' => t('ch_block_code'),
        'profanity' => t('ch_block_bad'),
        'long' => t('ch_block_long'),
        _ => '',
      };

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || _blockReason != null || _checking) return;
    setState(() => _sending = true);
    try {
      final r = await Api.post('/chat/with/${widget.userId}', s.token!, {'text': text});
      if (!mounted) return;
      setState(() {
        _msgs.add((r['message'] as Map).cast<String, dynamic>());
        _input.clear();
        _blockReason = null;
      });
      _toEnd();
    } on ApiException catch (e) {
      if (!mounted) return;
      final key = e.code.startsWith('chat_') ? e.code.substring(5) : '';
      setState(() => _blockReason = key.isEmpty ? null : key);
      if (key.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr(s.lang, e.l10nKey))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _blockReason != null && _blockReason != 'empty';
    return Scaffold(
      backgroundColor: pal.bg1,
      appBar: AppBar(title: Text(_name.isEmpty ? t('ch_title') : _name)),
      body: PageFrame(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                children: [
                  if (_msgs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(t('ch_say_hi'),
                            style: TextStyle(color: pal.subtext)),
                      ),
                    ),
                  for (final m in _msgs)
                    Align(
                      alignment: m['mine'] == true
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        constraints: const BoxConstraints(maxWidth: 520),
                        decoration: BoxDecoration(
                          color: m['mine'] == true
                              ? pal.accent.withAlpha(0x33)
                              : pal.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: m['mine'] == true ? pal.accent : pal.cardBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            SelectableText('${m['text']}',
                                style: TextStyle(color: pal.text, height: 1.35)),
                            const SizedBox(height: 2),
                            Text(_hm((m['at'] as num).toInt()),
                                style: TextStyle(fontSize: 10.5, color: pal.subtext)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (blocked)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Row(children: [
                  const Icon(Icons.block, size: 16, color: Colors.redAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_reasonText(_blockReason!),
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
                  ),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 500,
                      onChanged: _onChanged,
                      decoration: InputDecoration(
                        hintText: t('ch_hint'),
                        counterText: '',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: (blocked || _checking || _sending) ? null : _send,
                    icon: const Icon(Icons.send),
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
