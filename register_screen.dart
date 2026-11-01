import 'package:flutter/material.dart';
import '../api.dart';
import '../l10n.dart';
import '../settings.dart';
import 'otp_screen.dart';

/// Birinchi kirish oynasi: til, rejim va telefon raqami.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _phone = TextEditingController(text: '+998 ');
  bool _loading = false;
  String? _error;

  AppSettings get s => widget.settings;
  String t(String key) => tr(s.lang, key);

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9 || digits.length > 15) {
      setState(() => _error = t('err_invalid_phone'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final phone = '+$digits';
      final devCode = await Api.requestCode(phone);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OtpScreen(settings: s, phone: phone, devCode: devCode),
      ));
    } on ApiException catch (e) {
      setState(() => _error = t(e.l10nKey));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
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
                            const SizedBox(height: 16),
                            const Center(
                              child: Text('♞︎',
                                  style: TextStyle(fontSize: 72)),
                            ),
                            Text(t('welcome'),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.headlineMedium),
                            const SizedBox(height: 8),
                            Text(t('register_sub'),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(height: 28),
                            Text(t('language'),
                                style: Theme.of(context).textTheme.labelLarge),
                            const SizedBox(height: 8),
                            SegmentedButton<String>(
                              showSelectedIcon: false,
                              segments: [
                                for (final e in languageNames.entries)
                                  ButtonSegment(value: e.key, label: Text(e.value)),
                              ],
                              selected: {s.lang},
                              onSelectionChanged: (v) => s.setLang(v.first),
                            ),
                            const SizedBox(height: 20),
                            Text(t('theme'),
                                style: Theme.of(context).textTheme.labelLarge),
                            const SizedBox(height: 8),
                            SegmentedButton<bool>(
                              showSelectedIcon: false,
                              segments: [
                                ButtonSegment(
                                  value: false,
                                  icon: const Icon(Icons.light_mode),
                                  label: Text(t('light')),
                                ),
                                ButtonSegment(
                                  value: true,
                                  icon: const Icon(Icons.dark_mode),
                                  label: Text(t('dark')),
                                ),
                              ],
                              selected: {s.dark},
                              onSelectionChanged: (v) => s.setDark(v.first),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              onSubmitted: (_) => _next(),
                              decoration: InputDecoration(
                                labelText: t('phone'),
                                hintText: t('phone_hint'),
                                prefixIcon: const Icon(Icons.phone),
                                border: const OutlineInputBorder(),
                                errorText: _error,
                              ),
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
                        onPressed: _loading ? null : _next,
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : Text(t('next')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
