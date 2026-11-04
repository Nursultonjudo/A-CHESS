import 'package:flutter/material.dart';
import 'api.dart';
import 'desktop_shortcut.dart';
import 'l10n.dart';
import 'screens/home_screen.dart';
import 'screens/register_screen.dart';
import 'settings.dart';
import 'widgets/chess_board.dart' show Pal;

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
  ensureDesktopShortcut();
}

class ChessApp extends StatelessWidget {
  const ChessApp({super.key, required this.settings});
  final AppSettings settings;

  ThemeData _theme(Brightness b) {
    final dark = b == Brightness.dark;
    final pal = Pal.of(settings.boardStyle, dark, settings.uiStyle);
    final onAccent = ThemeData.estimateBrightnessForColor(pal.accent) ==
            Brightness.dark
        ? Colors.white
        : const Color(0xFF1B1B1B);
    final base = ColorScheme.fromSeed(seedColor: pal.accent, brightness: b);
    final scheme = base.copyWith(
      primary: pal.accent,
      onPrimary: onAccent,
      surface: pal.card,
      onSurface: pal.text,
      outline: pal.cardBorder,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    const label = TextStyle(fontSize: 15, fontWeight: FontWeight.w800);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: pal.bg1,
      dividerColor: pal.cardBorder,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: pal.accent,
          foregroundColor: onAccent,
          minimumSize: const Size(64, 50),
          shape: shape,
          textStyle: label,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: pal.text,
          minimumSize: const Size(64, 50),
          side: BorderSide(color: pal.cardBorder, width: 1.4),
          shape: shape,
          textStyle: label,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: pal.accent,
          shape: shape,
          textStyle: label,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: pal.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: pal.card,
        surfaceTintColor: Colors.transparent,
        shape: shape,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        side: BorderSide(color: pal.cardBorder),
        labelStyle: TextStyle(color: pal.text, fontWeight: FontWeight.w600),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? Colors.white.withAlpha(0x0A) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: pal.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: pal.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: pal.accent, width: 2),
        ),
      ),
    );
  }

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
