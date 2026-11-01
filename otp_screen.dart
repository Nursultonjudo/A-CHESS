import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart';
import '../l10n.dart';
import '../settings.dart';

/// Telefonga kelgan bir martalik kodni kiritish oynasi.
class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.settings,
    required this.phone,
    this.devCode,
  });

  final AppSettings settings;
  final String phone;
  final String? devCode;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _devCode;
  int _cooldown = 60;
  Timer? _timer;

  AppSettings get s => widget.settings;
  String t(String key, [Map<String, String> args = const {}]) =>
      tr(s.lang, key, args);

  @override
  void initState() {
    super.initState();
    _devCode = widget.devCode;
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_cooldown <= 1) {
        timer.cancel();
      }
      if (mounted) setState(() => _cooldown--);
    });
  }

  Future<void> _resend() async {
    setState(() => _error = null);
    try {
      final dev = await Api.requestCode(widget.phone);
      if (!mounted) return;
      setState(() => _devCode = dev);
      _startCooldown();
    } on ApiException catch (e) {
      setState(() => _error = t(e.l10nKey));
    }
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = t('err_invalid_code'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await Api.verify(
        widget.phone,
        code,
        lang: s.lang,
        dark: s.dark,
      );
      await s.signIn(token, widget.phone);
      // Asosiy oynaga o'tish: ro'yxatdan o'tish oynalarini yopamiz.
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = t(e.l10nKey));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('otp_title'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 24),
                          const Icon(Icons.sms_outlined, size: 64),
                          const SizedBox(height: 16),
                          Text(t('otp_sent', {'phone': widget.phone}),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyLarge),
                          const SizedBox(height: 24),
                          TextField(
                            controller: _code,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 6,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: const TextStyle(fontSize: 28, letterSpacing: 10),
                            onSubmitted: (_) => _confirm(),
                            decoration: InputDecoration(
                              labelText: t('code'),
                              border: const OutlineInputBorder(),
                              errorText: _error,
                            ),
                          ),
                          if (_devCode != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(t('dev_code', {'code': _devCode!}),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Theme.of(context).colorScheme.tertiary)),
                            ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _cooldown > 0 ? null : _resend,
                            child: Text(_cooldown > 0
                                ? t('resend_in', {'s': '$_cooldown'})
                                : t('resend')),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _loading ? null : _confirm,
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : Text(t('confirm')),
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
