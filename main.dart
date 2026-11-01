import 'package:flutter/material.dart';
import 'api.dart';
import 'l10n.dart';
import 'screens/home_screen.dart';
import 'screens/register_screen.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();

  // Saqlangan kirish hali amal qiladimi? Server rad etsa, ro'yxatdan o'tish oynasi ochiladi.
  if (settings.token != null) {
    final ok = await Api.checkToken(settings.token!)
        .timeout(const Duration(seconds: 5), onTimeout: () => true);
    if (!ok) await settings.signOut();
  }

  runApp(ChessApp(settings: settings));
}

class ChessApp extends StatelessWidget {
  const ChessApp({super.key, required this.settings});
  final AppSettings settings;

  ThemeData _theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8D6E63),
          brightness: b,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: tr(settings.lang, 'app_title'),
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: settings.dark ? ThemeMode.dark : ThemeMode.light,
        home: settings.loggedIn
            ? HomeScreen(settings: settings)
            : RegisterScreen(settings: settings),
      ),
    );
  }
}
