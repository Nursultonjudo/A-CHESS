import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'settings.dart';
import 'widgets/chess_board.dart';
import 'page_frame.dart';
import 'robot_button.dart';

class _Msg {
  _Msg(this.role, this.text);
  final String role; // 'user' | 'assistant'
  final String text;
}

/// A-CHESS AI bilan suhbat oynasi (o'quvchilar uchun).
class AiChatView extends StatefulWidget {
  const AiChatView({super.key, required this.settings, required this.pal});
  final AppSettings settings;
  final Pal pal;

  @override
  State<AiChatView> createState() => _AiChatViewState();
}

class _AiChatViewState extends State<AiChatView> {
  final _msgs = <_Msg>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;
  String? _error;

  AppSettings get s => widget.settings;
  Pal get pal => widget.pal;
  String t(String k) => tr(s.lang, k);

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    final token = s.token;
    if (text.isEmpty || _busy || token == null) return;
    setState(() {
      _msgs.add(_Msg('user', text));
      _input.clear();
      _busy = true;
      _error = null;
    });
    _toEnd();
    try {
      final res = await Api.post(
        '/ai/chat',
        token,
        {
          'messages': [
            for (final m in _msgs) {'role': m.role, 'content': m.text},
          ],
        },
        timeout: const Duration(seconds: 90),
      );
      if (!mounted) return;
      setState(() => _msgs.add(_Msg('assistant', '${res['reply']}')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error =
          e is ApiException ? tr(s.lang, e.l10nKey) : t('err_network'));
    } finally {
      if (mounted) setState(() => _busy = false);
      _toEnd();
    }
  }

  /// **qalin** belgilarini oddiy qalin matnga aylantiradi.
  List<InlineSpan> _spans(String text, Color color) {
    final out = <InlineSpan>[];
    final parts = text.split('**');
    for (var i = 0; i < parts.length; i++) {
      out.add(TextSpan(
        text: parts[i],
        style: TextStyle(
          color: color,
          fontWeight: i.isOdd ? FontWeight.w800 : FontWeight.w400,
        ),
      ));
    }
    return out;
  }

  Widget _bubble(_Msg m) {
    final me = m.role == 'user';
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 640),
        decoration: BoxDecoration(
          color: me ? pal.accent.withAlpha(0x33) : pal.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: me ? pal.accent : pal.cardBorder),
        ),
        child: SelectableText.rich(
          TextSpan(children: _spans(m.text, pal.text), style: const TextStyle(height: 1.4)),
        ),
      ),
    );
  }

  Widget _welcome() {
    final tips = [t('ai_tip1'), t('ai_tip2'), t('ai_tip3'), t('ai_tip4')];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        const RobotFace(size: 92, color: Color(0xFF58E6FF)),
        const SizedBox(height: 14),
        Text('A-CHESS AI',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w900, color: pal.text)),
        const SizedBox(height: 6),
        Text(t('ai_intro'),
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.subtext, height: 1.4)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final tip in tips)
              ActionChip(label: Text(tip), onPressed: () => _send(tip)),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        children: [
          Expanded(
            child: _msgs.isEmpty
                ? Center(child: SingleChildScrollView(child: _welcome()))
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    children: [
                      for (final m in _msgs) _bubble(m),
                      if (_busy)
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              const RobotFace(size: 30, color: Color(0xFF58E6FF)),
                              const SizedBox(width: 10),
                              Text(t('ai_thinking'),
                                  style: TextStyle(color: pal.subtext)),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: t('ai_hint'),
                      filled: true,
                      fillColor: pal.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _busy ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
